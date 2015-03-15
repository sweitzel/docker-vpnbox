# Build a docker image for squid proxy
FROM centos:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

WORKDIR /tmp

# Define which filters to use, check http://www.shallalist.de/categories.html for a list
ENV SQUIDGUARD_FILTER="adv spyware tracker"

RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install squid squidGuard curl openssl tar && \
  yum --quiet clean all && rm -rf /tmp/* /var/tmp/* /var/log/*

ADD ./bin /usr/local/bin
ADD ./etc /etc/squid

# volume for security/backup/migration purpose
#   e.g. the SQUID CA should be saved
VOLUME ["/usr/local/squid"]

# 3128 = standard proxy (http)
# 3129 = TPROXY  (http)
# 3130 = TPROXY ssl_bump (https)
EXPOSE 3128 3129 3130

# this script will create the CA used for ssl_bump, if not existing
ENTRYPOINT ["/usr/local/bin/run.sh"]