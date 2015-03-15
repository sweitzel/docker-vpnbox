#!/bin/bash

#
# Run the C-ICAP daemon
#
# It is required that the link to the clamav container is established.
# This will lead to an added /etc/host entry for the clamav server, which is configured in the c-icap.conf
#

#set -ex
echo "INFO: Starting up C-ICAP version $C_ICAP_VERSION"

if [ "$CLAMAV_NAME" == "" ]; then
  echo "ERROR: ClamAV Docker link is not established."
  echo "NOTICE: Run example: docker run --name=cicap -d --link clamav vpn-box/c-icap"
  exit 1
fi

if [ ! -e "/usr/local/c-icap/etc/c-icap.conf" ]; then
  echo "ERROR: /usr/local/c-icap/etc/c-icap.conf does not exist!"
  exit 1
fi

if [ ! -d "/var/log/c-icap" ]; then
  echo "INFO: Creating log directory"
  mkdir -p "/var/log/c-icap"
fi

exec /usr/local/c-icap/bin/c-icap -f "/usr/local/c-icap/etc/c-icap.conf" -N -D
