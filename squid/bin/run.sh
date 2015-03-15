#!/bin/bash

#
# Run the SQUID daemon
#
# Notes:
# - It is required that the link to the c-icap container is established.
#   This will lead to an added /etc/host entry for the c-icap server, which is configured in the squid.conf
# - Certificates ssl_bump will be generated on a...

################################################################################
# Functions

function run_or_exit {
  cmd=$*
  echo "INFO: Run \"$cmd\""
  echo "----------------------------------------------------------------- Output begin --"
  eval $*
  echo "------------------------------------------------------------------ Output end ---"
  if [ $? -eq 0 ]; then
    echo "INFO: Command successfully executed"
  else
    echo "ERROR: Command failed"
    exit 1
  fi
}


# intercept for TPROXY mode
#   Note: requires packets routed properly from openvpn container
function f_setup_intercept {
  SQUID_IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')
  # openvpn IP known via --links <container>:openvpn
  OPENVPN_IP=$(getent hosts openvpn | head -n 1 | cut -d ' ' -f 1)
  if [ $? -ne 0 ]; then
    echo "ERROR: Could not determine Openvpn IP. Check docker link!"
    exit 1
  fi

  # Setup a chain DIVERT to mark packets
  run_or_exit "iptables -t mangle -N DIVERT"
  run_or_exit "iptables -t mangle -A DIVERT -j MARK --set-mark 1"
  run_or_exit "iptables -t mangle -A DIVERT -j ACCEPT"
  # Use DIVERT to prevent existing connections going through TPROXY twice
  run_or_exit "iptables -t mangle -A PREROUTING -p tcp -m socket -j DIVERT"
  # Redirection
  run_or_exit "iptables -t mangle -A PREROUTING -p tcp --dport 80 -j TPROXY --tproxy-mark 0x1/0x1 --on-port 3129"
  run_or_exit "iptables -t mangle -A PREROUTING -p tcp --dport 443 -j TPROXY --tproxy-mark 0x1/0x1 --on-port 3130"

  run_or_exit "iptables -t nat -A POSTROUTING -s 10.128.81.0/24 -o eth0 -p tcp -m tcp -m multiport --dports 80,443 -j SNAT --to-source $SQUID_IP"
  #run_or_exit "iptables -t nat -A POSTROUTING -s 10.128.81.0/24 -o eth0 -p tcp -m tcp --dport 443 -j SNAT --to-source $SQUID_IP"

  # and finally route to Squid
  run_or_exit "ip -f inet rule add fwmark 1 lookup 100"
  run_or_exit "ip -f inet route add local default dev lo table 100"

  # route for traffic back to openvpn container
  ip route add 10.128.81.0/24 via $OPENVPN_IP
}

# return the CA in X.509 format, e.g. to import into Windows
function f_get_ca {
  if [ ! -e /usr/local/squid/ssl_cert/bumpy-ca.crt ]; then
    echo "ERROR: CA not yet initialized. Run with '--init'"
    exit 1
  fi
  openssl x509 -in /usr/local/squid/ssl_cert/bumpy-ca.crt
}

function f_generate_ca {
  # remove old SSL cache directory
  rm -rf /usr/local/squid/ssl_db/
  mkdir -p /usr/local/squid/ssl_cert/
  chown squid:squid /usr/local/squid/ssl_cert/
  chmod 700 /usr/local/squid/ssl_cert/
  if [ -e /etc/squid/x509v3ca.cnf ]; then
    # Generate RSA CA private key:
    echo "INFO: Generating CA private key"
    run_or_exit "openssl genrsa -out /usr/local/squid/ssl_cert/bumpy-ca.key 2048"
    #Create CA certificate
    echo "INFO: Generating CA certificate"
    run_or_exit "openssl req -new -nodes -x509 -out /usr/local/squid/ssl_cert/bumpy-ca.crt -key \
      /usr/local/squid/ssl_cert/bumpy-ca.key -config /etc/squid/x509v3ca.cnf -extensions v3_ca \
      -subj '/O=Squid3/OU=Squid3 RootCA/CN=Squid3/' -days 3650"
    echo "INFO: Generating DH parameter, this takes a while"
    run_or_exit "openssl gendh -5 -out /usr/local/squid/ssl_cert/dh.pem 2048 2>/dev/null"
  else
    echo "WARN: Unable to generate CA via openssl; /etc/squid/x509v3ca.cnf does not exist"
  fi
}

# setup SquidGuard, including download of Blacklist
#   Note: Download will only be done if md5 sum changed
#   conf:  /etc/squid/squidguard.conf
#   db:    /usr/local/squid/squidguard/db
#   Filter adjusted by env var SQUIDGUARD_FILTERS
function f_setup_squidguard {
  # download
  NEW=0
  dl_file=/usr/local/squid/tmp/shallalist.tar.gz
  dl_url=http://www.shallalist.de/Downloads/shallalist.tar.gz
  for tmp in /usr/local/squid/tmp /usr/local/squid/squidGuard/db; do
    if [ ! -d $tmp ]; then
      mkdir -p $tmp
    fi
  done
  pushd /usr/local/squid/tmp/
  if [ -e "$dl_file" ]; then
    run_or_exit "/usr/bin/curl -sS -O ${dl_url}.md5"
    #Check the status
    /usr/bin/md5sum --status -c *.md5
    #Do we download a new version?
    if [ $? -ne 0 ]; then
      run_or_exit "/usr/bin/curl -sS -O ${dl_url}"
      NEW=1
    else
      echo "INFO: Installed Shallalist already the latest one"
    fi
  else
    run_or_exit "/usr/bin/curl -sS -O ${dl_url}.md5"
    run_or_exit "/usr/bin/curl -sS -O ${dl_url}"
    NEW=1
  fi

  #Did we download a new tar-gzip?
  if [ $NEW -eq 1 ]; then
    echo "INFO: Installing new Shallalist"
    #Check the status
    /usr/bin/md5sum --status -c *.md5
    #MD5 match? Then commit.
    if [ $? -eq 0 ]; then
      run_or_exit "/bin/tar -xzf $dl_file"
      /bin/cp -a BL/* /usr/local/squid/squidGuard/db
      /bin/rm -rf BL
    else
      echo "WARN: MD5 of Shallist (blacklist) mismatch"
    fi
  fi
  popd

  # create squidguard config
  #   Requires the DB to be downloaded, e.g shallalist above
  #   Dockerfile defines ENV SQUIDGUARD_FILTER with list of filters to apply
  for filter in $SQUIDGUARD_FILTER; do
    if [ ! -d /usr/local/squid/squidGuard/db/$filter ]; then
      echo "WARN: SquidGuard filter $filter does not exist in db!"
      continue
    fi
    BLOCK="dest $filter {"
    BLOCK+=$'\n'
    if [ -e "/usr/local/squid/squidGuard/db/$filter/domains" ]; then
      BLOCK+="  domainlist $filter/domains"
      BLOCK+=$'\n'
    fi
    if [ -e "/usr/local/squid/squidGuard/db/$filter/urls" ]; then
      BLOCK+="  urllist $filter/urls"
      BLOCK+=$'\n'
    fi
    if [ -e "/usr/local/squid/squidGuard/db/$filter/expressions" ]; then
      BLOCK+="  expressionlist $filter/expressions"
      BLOCK+=$'\n'
    fi
    BLOCK+=$'  redirect http://upload.wikimedia.org/wikipedia/commons/c/c0/Blank.gif\n'
    BLOCK+=$'}\n'
    FILTER_BLOCKS+=$BLOCK
    FILTER_LIST+=" !$filter"
  done

  cat > /etc/squid/squidGuard_custom.conf <<EOF
dbhome /usr/local/squid/squidGuard/db
logdir /usr/local/squid/log

src my_network  {
  ip 10.128.81.0/24
  ip 172.17.0.0/16
}

$FILTER_BLOCKS

acl {
  my_network  {
    pass$FILTER_LIST any
  }
  default {
    pass none
    redirect http://upload.wikimedia.org/wikipedia/commons/c/c0/Blank.gif
  }
}
EOF

  # create squidGuard db
  run_or_exit "/usr/bin/squidGuard -d -c /etc/squid/squidGuard_custom.conf -C all"
  /bin/chown -R squid:squid /usr/local/squid/squidGuard/
}

################################################################################
# Main

#set -ex

# parse commandline
MODE=run
#  -l=*|--lib=*)
#   LIBPATH="${i#*=}"
#   shift
#  ;;
for i in "$@"
do
  case $i in
    --init)
      MODE=init
      shift
    ;;
    --getca)
      MODE=getca
      shift
    ;;
    *)
      # unknown option
    ;;
  esac
done

if [ "$MODE" = "init" ]; then
  f_generate_ca
  chown -R squid:squid /usr/local/squid
  echo "INFO: This is the generated CA certificate, to import on Clients:"
  f_get_ca
  exit 0
elif [ "$MODE" = "getca" ]; then
  f_get_ca
  exit 0
fi

echo "INFO: Prepare for starting up Squid"

if [ "$CICAP_NAME" == "" ]; then
  echo "ERROR: Docker link to C-ICAP container is not established."
  echo "NOTICE: Run example: docker run --name=squid -d --link cicap vpn-box/squid"
  exit 1
fi


if [ ! -e "/etc/squid/squid.conf" ]; then
  echo "ERROR: /etc/squid/squid.conf does not exist!"
  exit 1
fi

if [ ! -d "/usr/local/squid/log/" ]; then
  echo "INFO: Creating log directory"
  mkdir -p /usr/local/squid/log
fi

# check ssl cert dir
#   if it not exists, create self-signed CA for Squid (ssl_bump)
if [[ ! -d /usr/local/squid/ssl_cert/ || ! -e "/usr/local/squid/ssl_cert/bumpy-ca.key" ]]; then
  f_generate_ca
fi

# check ssl cache dir
if [[ ! -d /usr/local/squid/ssl_db/ || ! -e /usr/local/squid/ssl_db/index.txt ]]; then
  rm -rf /usr/local/squid/ssl_db/
  run_or_exit "/usr/lib64/squid/ssl_crtd -c -s /usr/local/squid/ssl_db/"
fi

f_setup_intercept
f_setup_squidguard

# create (eventually) missing cache_dir
run_or_exit "/usr/sbin/squid -f /etc/squid/squid.conf -N -z"

rm -f /usr/local/squid/squid.pid
chown -R squid:squid /usr/local/squid

echo "INFO: Now running squid: squid -f \"/etc/squid/squid.conf\" -d 1 -N"
exec /usr/sbin/squid -f /etc/squid/squid.conf -d 1 -N
