# Build a docker image for dnsmasq
FROM alpine:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

WORKDIR /tmp

RUN apk --no-cache add dnsmasq
EXPOSE 53 53/udp

# add additional servers with --server=<server>
ENTRYPOINT ["dnsmasq", "-k"]
