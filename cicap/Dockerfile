# Build a docker image for C-ICAP+SquidClamav
FROM centos:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

ENV C_ICAP_VERSION="0.3.5" SQUIDCLAMAV_VERSION="6.12"

WORKDIR /tmp

# 1. install dependencies, includin some just needed for build purpose
# 2. build
# 3. cleanup
# Note: Maybe ugly to have all in one RUN, but it avoids creating unneccessary layers
RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install zlib bzlib2 && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install curl tar gcc make zlib-devel bzip2-devel && \
  curl --silent --location --remote-name "http://downloads.sourceforge.net/project/c-icap/c-icap/0.3.x/c_icap-${C_ICAP_VERSION}.tar.gz" && \
  tar -xzf "c_icap-${C_ICAP_VERSION}.tar.gz" && \
  cd /tmp/c_icap-${C_ICAP_VERSION} && \
  ./configure --quiet --prefix=/usr/local/c-icap --enable-large-files && \
  make > /tmp/build.log 2>&1 && make install >>/tmp/build.log 2>&1 && \
  cd /tmp && \
  curl --silent --location --remote-name "http://downloads.sourceforge.net/project/squidclamav/squidclamav/6.12/squidclamav-${SQUIDCLAMAV_VERSION}.tar.gz" && \
  tar -xzf "squidclamav-${SQUIDCLAMAV_VERSION}.tar.gz" && \
  cd /tmp/squidclamav-${SQUIDCLAMAV_VERSION} && \
  ./configure --quiet --with-c-icap=/usr/local/c-icap/ && \
  make > /tmp/build.log 2>&1 && make install >>/tmp/build.log 2>&1 && \
  yum --quiet --assumeyes autoremove -- tar gcc make zlib-devel bzip2-devel && \
  yum --quiet clean all && rm -rf /tmp/* /var/tmp/* /var/log/*

ADD ./bin/ /usr/local/bin/
ADD ./etc/ /usr/local/c-icap/etc/

# add user/group proxy, c-icap will execute as
RUN chmod a+x /usr/local/bin/* && \
  adduser -M -s /sbin/nologin -U proxy && \
  mkdir -p /var/run/c-icap/ && \
  chown -R proxy:proxy /var/run/c-icap/ && \
  chown -R proxy:proxy /usr/local/c-icap/ && \
  chmod 750 /usr/local/c-icap

VOLUME ["/var/log/c-icap"]
EXPOSE 1344/tcp

ENTRYPOINT ["/usr/local/bin/run.sh"]
