# Build a docker image for dnsmasq
FROM alpine:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

WORKDIR /tmp

RUN apk --no-cache add dnsmasq
EXPOSE 53 53/udp

# add additional servers with --server=<server>
# 127.0.0.11 is the Docker DNS, to enable resolution of Docker internal hostnames by VPN clients
ENTRYPOINT ["dnsmasq", "-k", "--server=127.0.0.11"]
