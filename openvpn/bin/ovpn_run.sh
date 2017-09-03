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
  rc=$?
  echo "------------------------------------------------------------------ Output end ---"
  if [ $rc -eq 0 ]; then
    echo "INFO: Command successfully executed"
  else
    echo "ERROR: Command failed (rc=$rc)"
    exit 1
  fi
}

function f_get_squid_ip {
  SQUID_IP=$(getent hosts squid | head -n 1 | cut -d ' ' -f 1)
  if [ $? -ne 0 ]; then
    echo 'ERROR: Could not determine Squid IP. Internal Error'
  fi
}

# setup iptables/routing for intercepting proxy
function f_setup_intercept {
  OVPN_IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')
  if [[ $? -ne 0 || -z "$OVPN_IP" ]]; then
    echo 'ERROR: Could not determine own IP. Should not happen.'
    exit 1
  fi
  # Dont mark container network traffic
  run_or_exit "iptables -t mangle -A PREROUTING -j ACCEPT -p tcp -m multiport --dports 80,443 -s 172.17.0.0/16"
  run_or_exit "iptables -t mangle -A PREROUTING -j ACCEPT -p tcp -m multiport --dports 80,443 -d 172.17.0.0/16"

  # Now mark our traffic
  run_or_exit "iptables -t mangle -A PREROUTING -p tcp -m multiport --dports 80,443 -j MARK --set-mark 1"

  # route marked traffic to Squid
  run_or_exit "ip rule add fwmark 1 table 100"

  # Source NAT other traffic (e.g. DNS, SSH), except the already marked one
  run_or_exit "iptables -t nat -A POSTROUTING -m mark --mark 1 -j ACCEPT"
  run_or_exit "iptables -t nat -A POSTROUTING -s 10.128.81.0/24 -o eth0 -j SNAT --to-source $OVPN_IP"

  # same as above, just for IPv6
  #run_or_exit "ip6tables -t mangle -A PREROUTING -j ACCEPT -p tcp -m multiport --dports 80,443 -s todo"
  #run_or_exit "ip6tables -t mangle -A PREROUTING -j ACCEPT -p tcp -m multiport --dports 80,443 -d todo"
  #run_or_exit "ip6tables -t mangle -A PREROUTING -p tcp -m multiport --dports 80,443 -j MARK --set-mark 1"
  #run_or_exit "ip -f inet6 rule add fwmark 1 table 100"
  #run_or_exit "ip6tables -t nat -A POSTROUTING -m mark --mark 1 -j ACCEPT"
  #run_or_exit "ip6tables -t nat -A POSTROUTING -s 10.128.81.0/24 -o eth0 -j SNAT --to-source $OVPN_IP6"

  # wait a bit until the SQUID container is ready and IP can be determined
  for i in {1..10}; do
    f_get_squid_ip
    if [ -n "$SQUID_IP" ]; then
      break;
    fi
    echo .
    sleep 3
  done
  if [ -z "$SQUID_IP" ]; then
    echo 'ERROR: Could not determine Squid IP. Make sure to start service with docker-compose!'
    exit 1
  fi
  echo "INFO: Determined SQUID_IP=$SQUID_IP ($i tries)"
  run_or_exit "ip route add default via $SQUID_IP dev eth0 table 100"
  #run_or_exit "ip -f inet6 route add default via $SQUID_IP6 dev eth0 table 100"
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
      echo "Valid: [none] | --init=<vpn_server_uri> | --getclient=<client_cn> | --post-run=<squid_ip>"
      exit 1
    ;;
  esac
done

if [ ! -d "/data" ]; then
  echo 'ERROR: Public data directory missing, please ensure to start with a data volume mounted at /data!'
  exit 1
fi
if [ ! -d "${VPNCONFIG}" ]; then
  echo 'ERROR: Private data directory missing, please ensure to start with a data volume mounted at ${VPNCONFIG}!'
  exit 1
fi
run_or_exit "chown -f openvpn ${VPNCONFIG}"

if [ "$MODE" = "init" ]; then
  # init with (public) VPN server url, like udp://vpn.server.com:1194
  ovpn_init.sh $VALUE
  if [ $? -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
elif [ "$MODE" = "getclient" ]; then
  # getclient with CN of client to retrieve/create
  ovpn_getclient.sh $VALUE
  if [ $? -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
fi

if [ ! -d "/data/openvpn" ]; then
  echo "INFO: Creating data directory (/data/openvpn)"
  run_or_exit "mkdir -p /data/openvpn"
  run_or_exit "chown -f openvpn /data/openvpn"
fi

# check CA exists
if [ ! -d "$EASYRSA_PKI" ]; then
  echo "ERROR: CA is not yet created. Run init first, e.g. '--init udp://vpn.server.com:1194'"
  exit 1
fi
run_or_exit "chown -R openvpn ${EASYRSA_PKI}"

# check net_admin capability
res=$(ip link set dev lo down)
if [ $? -ne 0 ]; then
  echo "ERROR: You have to run docker with '--cap-add=NET_ADMIN'"
  exit 1
fi
run_or_exit "ip link set dev lo up"

# check config
if [ ! -e "${VPNCONFIG}/openvpn.conf" ]; then
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

# run as non-root
exec su openvpn -s /bin/sh --command="openvpn --cd /data/openvpn --config ${VPNCONFIG}/openvpn.conf"