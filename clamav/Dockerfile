# Build a docker image for clamav/clamd

FROM centos:latest

MAINTAINER sebastian.weitzel@gmail.com

WORKDIR /tmp

ADD ./bin /usr/local/bin
ADD ./etc /usr/local/etc

# 1. install clamav, clamd and freshclam
# 2. initial update of av databases
# 3. cleanup
# Note: Maybe ugly to have all in one RUN, but it avoids creating unneccessary layers
RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install clamav clamav-server clamav-update && \
  /usr/bin/freshclam --quiet --config-file=/usr/local/etc/freshclam.conf && \
  yum --quiet clean all && rm -rf /tmp/* /var/tmp/* /var/log/*

RUN chmod a+x /usr/local/bin/* && \
  adduser -M -s /sbin/nologin -U clamav && \
  mkdir -p /var/run/clamav /var/log/clamav/ && \
  chown -R clamav:clamav /var/run/clamav/ /var/log/clamav/

VOLUME ["/var/log/clamav"]

EXPOSE 3310/tcp

ENTRYPOINT ["/usr/local/bin/run.sh"]
