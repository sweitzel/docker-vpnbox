# Build a docker image for openvpn
FROM centos:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

WORKDIR /tmp

RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install openvpn openssl iproute iptables sudo && \
  rm -rf /tmp/* /var/tmp/* /var/log/*

# etc just with default config, copied to /usr/local/openvpn/etc on startup
ADD ./bin /usr/local/bin
ADD ./easyrsa3 /usr/local/share/easy-rsa

# Needed by scripts
ENV VPNCONFIG=/data-priv RANDFILE=/data-priv/.rnd EASYRSA="/usr/local/share/easy-rsa" EASYRSA_PKI="/data-priv/pki" EASYRSA_ALGO="ec" EASYRSA_CURVE="secp521r1"

# Internally uses port 1194, remap using docker
EXPOSE 1194/udp

# this script will create the CA used for VPN certs
ENTRYPOINT ["/usr/local/bin/ovpn_run.sh"]
