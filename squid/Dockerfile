# Build a docker image for squid proxy
FROM centos:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

WORKDIR /tmp

# Define which filters to use, check http://www.shallalist.de/categories.html for a list
ENV SQUIDGUARD_FILTER="adv spyware tracker"

# Disable this to use the release version of Squid (e.g. as soon as Squid 4 is released)
ADD ./repos.d/squid-cache-beta.repo /etc/yum.repos.d

RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install squid squid-helpers squidGuard curl openssl tar iproute iptables sudo && \
  rm -rf /tmp/* /var/tmp/* /var/log/*

ADD ./bin /usr/local/bin
ADD ./etc /etc/squid

# 3128 = standard explicit proxy (http)
# 3129 = TPROXY  (transparent proxy for http traffic)
# 3130 = TPROXY ssl_bump (transparent proxy for https traffic with bump)
EXPOSE 3128 3129 3130

# this script will create the CA used for ssl_bump, if not existing
ENTRYPOINT ["/usr/local/bin/run.sh"]
