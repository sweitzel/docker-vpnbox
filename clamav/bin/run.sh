#!/bin/bash

#
# Run the clamd and freshclam deamon
#   monitore the processes and wait for signals to abort childs

#set -ex

# for monitoring jobs
set -m

################################################################################
# Functions

function handle_signal {
  echo "INFO: Terminating CLAMD and Freshclam (pids $pids)"
  trap "" SIGCHLD
  for pid in $pids; do
    if ! kill -0 $pid 2>/dev/null; then
      wait $pid
      exitcode=$?
    fi
  done
  kill $pids 2>/dev/null
}

################################################################################
# Main

echo "INFO: Starting up CLAMD"

for f in clamd.conf freshclam.conf; do
  if [ ! -e "/usr/local/etc/$f" ]; then
    echo "FATAL: /usr/local/etc/$f.conf does not exist!"
    exit 1
  fi
done

if [ ! -d "/data/clamav" ]; then
  echo "INFO: Creating log directory (/data/clamav)"
  mkdir -p "/data/clamav" && chown clamav:clamav /data/clamav
fi
if [ ! -d "/data/clamav/db" ]; then
  echo "INFO: Creating db directory (/data/clamav/db)"
  mkdir -p "/data/clamav/db" && chown clamupdate /data/clamav/db
fi

if [ ! -e "/data/clamav/main.cld" ]; then
  echo "INFO: Initial Database Update"
  /usr/bin/freshclam --config-file=/usr/local/etc/freshclam.conf
fi

# run in background
/usr/bin/freshclam --daemon --config-file=/usr/local/etc/freshclam.conf --daemon-notify=/usr/local/etc/clamd.conf &
/usr/sbin/clamd --config-file=/usr/local/etc/clamd.conf &

pids=$(jobs -p)
exitcode=0

# set trap and then wait until terminate signal arrives
trap handle_signal SIGCHLD
trap handle_signal SIGINT
wait

exit $exitcode
