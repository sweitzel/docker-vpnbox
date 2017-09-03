# Build a docker image for C-ICAP+SquidClamav
FROM centos:latest

MAINTAINER Sebastian Weitzel <sebastian.weitzel@gmail.com>

ENV C_ICAP_VERSION="0.5.2" SQUIDCLAMAV_VERSION="6.16"

WORKDIR /tmp

# 1. install dependencies, includin some just needed for build purpose
# 2. build
# 3. cleanup
# Note: Maybe ugly to have all in one RUN, but it avoids creating unneccessary layers
RUN yum --quiet --assumeyes update && \
  yum --quiet --assumeyes install epel-release && \
  yum --quiet --assumeyes --setopt=tsflags=nodocs install curl zlib bzlib2 file tar gcc make zlib-devel bzip2-devel && \
  curl --silent --location --remote-name "http://downloads.sourceforge.net/project/c-icap/c-icap/0.5.x/c_icap-${C_ICAP_VERSION}.tar.gz" && \
  tar -xzf "c_icap-${C_ICAP_VERSION}.tar.gz" && \
  cd /tmp/c_icap-${C_ICAP_VERSION} && \
  ./configure 'CXXFLAGS=-O2 -m64 -pipe' 'CFLAGS=-O2 -m64 -pipe' --quiet --without-bdb --prefix=/usr/local/c-icap --enable-large-files && \
  make > /tmp/build.log 2>&1 && make install >>/tmp/build.log 2>&1 && \
  cd /tmp && \
  curl --silent --location --remote-name "http://downloads.sourceforge.net/project/squidclamav/squidclamav/${SQUIDCLAMAV_VERSION}/squidclamav-${SQUIDCLAMAV_VERSION}.tar.gz" && \
  tar -xzf "squidclamav-${SQUIDCLAMAV_VERSION}.tar.gz" && \
  cd /tmp/squidclamav-${SQUIDCLAMAV_VERSION} && \
  PATH="$PATH:/usr/local/c-icap/bin/" ./configure 'CXXFLAGS=-O2 -m64 -pipe' 'CFLAGS=-O2 -m64 -pipe' --quiet --with-c-icap=/usr/local/c-icap/ && \
  gmake > /tmp/build.log 2>&1 && gmake install-strip >>/tmp/build.log 2>&1 && \
  rm -rf /tmp/* /var/tmp/* /var/log/*

ADD ./bin/ /usr/local/bin/
ADD ./etc/ /usr/local/c-icap/etc/

# add user/group proxy, c-icap will execute as
RUN chmod a+x /usr/local/bin/* && \
  adduser -M -s /sbin/nologin -U proxy && \
  mkdir -p /var/run/c-icap/ && \
  chown -R proxy:proxy /var/run/c-icap/ && \
  chown -R proxy:proxy /usr/local/c-icap/ && \
  chmod 750 /usr/local/c-icap

EXPOSE 1344/tcp

ENTRYPOINT ["/usr/local/bin/run.sh"]
