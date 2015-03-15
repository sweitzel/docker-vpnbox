# Build a docker image for openvpn
FROM centos:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

WORKDIR /tmp

RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install openvpn openssl sudo && \
  yum --quiet clean all && rm -rf /tmp/* /var/tmp/* /var/log/*

# etc just with default config, copied to /usr/local/openvpn/etc on startup
ADD ./bin /usr/local/bin
ADD ./easyrsa3 /usr/local/share/easy-rsa

# volume for security/backup/migration purpose
VOLUME ["/usr/local/openvpn"]

# Needed by scripts
ENV EASYRSA="/usr/local/share/easy-rsa" EASYRSA_PKI="/usr/local/openvpn/pki" EASYRSA_KEY_SIZE="4096"
# does not work right now
#ENV EASYRSA="/usr/local/share/easy-rsa" EASYRSA_PKI="/usr/local/openvpn/pki" EASYRSA_KEY_SIZE="4096" EASYRSA_ALGO="ec" EASYRSA_CURVE="secp521r1"

# Internally uses port 1194, remap using docker
EXPOSE 1194/udp

# this script will create the CA used for VPN certs
ENTRYPOINT ["/usr/local/bin/ovpn_run.sh"]
