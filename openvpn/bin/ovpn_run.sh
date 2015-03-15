#!/bin/bash

#
# Run the OpenVPN server
#   requires initialization (CA) to be executed in advance
#

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

# setup iptables/routing for intercepting proxy
function f_setup_intercept {
  OVPN_IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')
  # Dont mark container network traffic
  run_or_exit "iptables -t mangle -A PREROUTING -j ACCEPT -p tcp -m multiport --dports 80,443 -s 172.17.0.0/16"
  run_or_exit "iptables -t mangle -A PREROUTING -j ACCEPT -p tcp -m multiport --dports 80,443 -d 172.17.0.0/16"


  # Now mark our traffic
  run_or_exit "iptables -t mangle -A PREROUTING -j MARK --set-mark 1 -p tcp -m multiport --dports 80,443"

  # route marked traffic to Squid
  run_or_exit "ip rule add fwmark 1 table 100"

  # Source NAT other traffic (e.g. DNS, SSH), except the already marked one
  run_or_exit "iptables -A POSTROUTING -t nat -m mark --mark 1 -j ACCEPT"
  run_or_exit "iptables -t nat -A POSTROUTING -s 10.128.81.0/24 -o eth0 -j SNAT --to-source $OVPN_IP"

  # Note: the following does not work, until Circular Links are supported by docker
  #       Run ovpn_post_run.sh <squid_ip> manually
  #SQUID_IP=$(getent hosts squid | head -n 1 | cut -d ' ' -f 1)
  #run_or_exit "ip route add default via $SQUID_IP dev eth0 table 100"
}

################################################################################
# Main

# parse commandline
MODE=run
#  -l=*|--lib=*)
#   LIBPATH="${i#*=}"
#   shift
#  ;;
for i in "$@"
do
  case $i in
    --init=*)
      MODE=init
      VALUE="${i#*=}"
      shift
    ;;
    --getclient=*)
      MODE=getclient
      VALUE="${i#*=}"
      shift
    ;;
    --post-run=*)
      MODE=post-run
      VALUE="${i#*=}"
      shift
    ;;
    *)
      # unknown option
      echo "ERROR: Unknown option $i"
      echo "Valid: [none] | --init=<vpn_server> | --getclient=<client_cn> | --post-run=<squid_ip>"
      exit 1
    ;;
  esac
done

if [ "$MODE" = "init" ]; then
  # init with (public) VPN server url, like udp://vpn.server.com:1194
  res=`ovpn_init.sh $VALUE`
  if [ $? -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
elif [ "$MODE" = "getclient" ]; then
  # getclient with CN of client to retrieve/create
  res=`ovpn_getclient.sh $VALUE`
  if [ $? -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
elif [ "$MODE" = "post-run" ]; then
  # post-run with IP address of Squid container
  res=`ovpn_post_run.sh $VALUE`
  if [ $? -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
fi

# check CA exists
if [ ! -d "$EASYRSA_PKI" ]; then
  echo "ERROR: CA is not yet created. Run init first, e.g. '--init udp://vpn.server.com:1194'"
  exit 1
fi

# check net_admin capability
res=$(ip link set dev lo down)
if [ $? -ne 0 ]; then
  echo "ERROR: You have to run docker with '--cap-add=NET_ADMIN'"
  exit 1
fi
run_or_exit "ip link set dev lo up"

# check config
if [ ! -e "/usr/local/openvpn/etc/openvpn.conf" ]; then
  echo "ERROR: openvpn.conf missing!"
  exit 1
fi

# check sudo permission for ip command for user openvpn
if [ ! -e "/etc/sudoers.d/001_ip" ]; then
  cat > /etc/sudoers.d/001_ip <<EOF
openvpn ALL=(ALL) NOPASSWD: /sbin/ip
Defaults:openvpn !requiretty
EOF
fi

echo "INFO: Creating persistent tun device"
run_or_exit "mkdir -p /dev/net"
if [ ! -c /dev/net/tun ]; then
  run_or_exit "mknod /dev/net/tun c 10 200"
  run_or_exit "chown openvpn /dev/net/tun"
fi
# create tun device
run_or_exit "openvpn --rmtun --dev tun0"
run_or_exit "openvpn --mktun --dev tun0 --dev-type tun --user openvpn --group openvpn"

f_setup_intercept

run_or_exit "chown -R openvpn:openvpn /usr/local/openvpn"

# run as non-root
exec su openvpn -s /bin/sh --command="openvpn --cd /tmp --config /usr/local/openvpn/etc/openvpn.conf"