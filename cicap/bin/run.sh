#!/bin/bash

#
# Run the C-ICAP daemon
#
# It is required that the link to the clamav container is established.
# This will lead to an added /etc/host entry for the clamav server, which is configured in the c-icap.conf
#

#set -ex
echo "INFO: Starting up C-ICAP version $C_ICAP_VERSION"

if [ ! -e "/usr/local/c-icap/etc/c-icap.conf" ]; then
  echo "ERROR: /usr/local/c-icap/etc/c-icap.conf does not exist!"
  exit 1
fi

if [ ! -d "/data/c-icap" ]; then
  echo "INFO: Creating c-icap log directory (/data/c-icap)"
  mkdir -p "/data/c-icap" && chown proxy:proxy /data/c-icap
fi

if [ ! -d "/data/c-icap/tmp" ]; then
  echo "INFO: Creating c-icap tmp directory (/data/c-icap/tmp)"
  mkdir -p "/data/c-icap/tmp" && chown proxy:proxy /data/c-icap/tmp
fi

exec /usr/local/c-icap/bin/c-icap -f "/usr/local/c-icap/etc/c-icap.conf" -N -D
