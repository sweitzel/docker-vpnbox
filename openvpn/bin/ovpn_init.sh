#!/bin/bash

#
# Initialize the CA for OpenVPN, create config and some other stuff
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

function init_pki {
  # Server name is in the form "udp://vpn.example.com:1194"
  if [[ "$1" =~ ^((udp|tcp)://)?([0-9a-zA-Z\.\-]+)(:([0-9]+))?$ ]]; then
    OVPN_PROTO=${BASH_REMATCH[2]};
    OVPN_HOST=${BASH_REMATCH[3]};
    OVPN_PORT=${BASH_REMATCH[5]};
    [ -z "$OVPN_PROTO" ] && OVPN_PROTO=udp
    [ -z "$OVPN_PORT" ] && OVPN_PORT=1194
    # save for reusage
    cat > ${VPNCONFIG}/openvpn.env <<EOF
# some user-defined settings, stored persistently
export OVPN_SERVER_URL="$1"
export OVPN_PROTO="$OVPN_PROTO"
export OVPN_PORT="$OVPN_PORT"
export OVPN_HOST="$OVPN_HOST"
EOF
  fi

  if [ -z "$OVPN_HOST" ]; then
    echo "ERROR: Please specify proper <serverstring>"
    echo "       serverstring: External server info, used also for Client config (e.g. udp://vpn.server.com:1194)"
    exit 1
  fi

  if tty -s; then
    echo "INFO: Starting OpenVPN CA initialization"
  else
    echo "ERROR: Server CA is missing, but cannot generate non-interactive"
    exit 1
  fi
  run_or_exit "${EASYRSA}/easyrsa --batch init-pki 2>&1"
  # this one will ask for password
  echo "INFO: Build CA (protect with a safe password)"
  for i in 1 2 3 4 5; do
    echo "        Suggestion ($i): $(openssl rand -hex 32)"
  done
  run_or_exit "${EASYRSA}/easyrsa --batch --dn-mode=cn_only --req-cn=\"OpenVPN CA\" build-ca"
  # create server key without password, with default cn=server01
  run_or_exit "${EASYRSA}/easyrsa --batch build-server-full \"$OVPN_HOST\" nopass"
  # generate static key for tls-crypt
  run_or_exit "openvpn --genkey --secret $EASYRSA_PKI/tc.key"
  # Just needed for RSA
  #echo "INFO: Generating DH parameters, this might take a little"
  #run_or_exit "${EASYRSA}/easyrsa --batch gen-dh 2>&1"
}

function write_server_config {
  if [ -z "$OVPN_HOST" ]; then
    echo "ERROR: Should not happen"
    exit 1
  fi
  cat > ${VPNCONFIG}/openvpn.conf <<EOF
server 10.128.81.0 255.255.255.0
remote-cert-tls client
proto udp
# Rely on Docker to do port mapping, internally always 1194
port 1194
dev tun0
verb 3

persist-key
persist-tun

key ${EASYRSA_PKI}/private/${OVPN_HOST}.key
ca ${EASYRSA_PKI}/ca.crt
cert ${EASYRSA_PKI}/issued/${OVPN_HOST}.crt
# needed for RSA
#dh ${EASYRSA_PKI}/dh.pem
dh none
#tls-crypt ${EASYRSA_PKI}/tc.key
# Workaround until Openvpn Connect (IOS) supports tls-crypt
tls-auth ${EASYRSA_PKI}/tc.key
key-direction 0

max-clients 64
keepalive 5 30
tcp-queue-limit 128
#tun-mtu 1500
#tun-mtu-extra 32
mssfix 1300
# txqueuelen 15000 # ; # doesn't work with docker

tls-version-min 1.2
tls-cipher 'TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-256-CBC-SHA384'
auth SHA256
script-security 1

ifconfig-pool-persist /data/openvpn/ifconfig-pool-persist.file
replay-persist /data/openvpn/replay-persist.file
iproute /usr/local/bin/sudo_ip.sh
status /data/openvpn/openvpn-status.log

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option PROXY_HTTP 192.168.50.5 3128"
push "dhcp-option PROXY_HTTPS 192.168.50.5 3128"
# Use DNSMASQ service
push "dhcp-option DNS 192.168.50.2"
# prevent DNS leakage https://blog.doenselmann.com/openvpn-dns-leaks-unter-windows/
push 'block-outside-dns'
EOF
}


################################################################################
# Main

OVPN_SERVER_URL=""
if [ "$1" == "" ]; then
  if [ -e ${VPNCONFIG}/openvpn.env ]; then
    source ${VPNCONFIG}/openvpn.env
  fi
  if [ -z "$OVPN_SERVER_URL" ]; then
    echo "ERROR: Need to specify server url, e.g. \"$(basename $0) udp://vpn.example.com:1194\""
    exit 1
  fi
else
  # e.g. udp://vpn.server.com:1194
  OVPN_SERVER_URL="$1"
fi

if [ "$1" == "noca" ]; then
  # just initialize the config
  if [ -e ${VPNCONFIG}/openvpn.env ]; then
    source ${VPNCONFIG}/openvpn.env
  fi
else
  # rename old CA, maybe its needed ;)
  if [ -d "$EASYRSA_PKI" ]; then
    mv "$EASYRSA_PKI" "${EASYRSA_PKI}_$(date +"%Y%m%d-%H%M%S")"
  fi
  init_pki "$OVPN_SERVER_URL"
fi

write_server_config

echo "INFO: Done"
exit 0
