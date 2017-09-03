#!/bin/bash

#
# Generate client certificate and return a config to be stored as .ovpn file
#
set -ex

set -o errexit

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

function get_client_config {
  if [ "$1" == "" ]; then
    echo "ERROR: Specify Client CN as parameter!"
    exit 1
  fi
  if [ -e ${VPNCONFIG}/openvpn.env ]; then
    source ${VPNCONFIG}/openvpn.env
  fi
  if [ -z "$OVPN_HOST" ]; then
    echo "ERROR: Please run ovpn_init.sh script before!"
    exit 1
  fi

  for f in $EASYRSA_PKI/issued/${1}.crt $EASYRSA_PKI/private/${1}.key $EASYRSA_PKI/reqs/${1}.req; do
    if [  -e "$f" ]; then
      # dont forget to also cleanup in index.txt
      echo "ERROR: CN=$1 has been used before. Cleanup manually if you want to reuse"
      exit 1
    fi
  done

  if ! tty -s; then
    echo "ERROR: Client cert for CN $1 is missing, cannot generate non-interactive"
    exit 1
  fi
  run_or_exit "sudo -E -u openvpn -H sh -c \"${EASYRSA}/easyrsa --batch build-client-full \"$1\" nopass\" 2>&1"
  for f in $EASYRSA_PKI/issued/${1}.crt $EASYRSA_PKI/private/${1}.key; do
    if [ ! -e "$f" ]; then
      echo "ERROR: Client certificates incomplete; at least $f missing!"
      exit 1
    fi
  done
  dt=$(date +"%F %H:%M:%S")
  # return the config to the callers STDOUT
  cat <<EOT
################################################################################
# OpenVPN client config - Generated $dt: ${1}.ovpn
client
nobind
dev tun
remote-cert-tls server

persist-key
persist-tun

tls-version-min 1.2
auth SHA256

<ca>
$(cat $EASYRSA_PKI/ca.crt)
</ca>
<cert>
$(openssl x509 -in $EASYRSA_PKI/issued/${1}.crt)
</cert>
<key>
$(cat $EASYRSA_PKI/private/${1}.key)
</key>
<tls-auth>
$(cat $EASYRSA_PKI/tc.key)
</tls-auth>
key-direction 1
# anything else?
remote $OVPN_HOST $OVPN_PORT $OVPN_PROTO
EOT
}

################################################################################
# Main

if [ -z "$1" ]; then
  echo "ERROR: Specify the client CN as only parameter to the script (e.g. client01)"
  exit 1
fi
if [ -d "$EASYRSA_PKI" ]; then
  chown -R openvpn:openvpn $EASYRSA_PKI
fi
get_client_config "$1"
exit 0