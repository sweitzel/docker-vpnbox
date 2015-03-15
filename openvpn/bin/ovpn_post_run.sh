#!/bin/bash

#
# Script to run post-init steps after OpenVPN has been started
#   this will basically just define the route to Squid and can become obsolete
#   as soon as docker support circular referencing links
#

################################################################################
# Functions

function run_or_exit {
  cmd=$*
  echo "INFO: Run \"$cmd\""
  echo "----------------------------------------------------------------- Output begin --"
  eval $*
  echo "------------------------------------------------------------------ Output end ---"
  if [ $? -eq 0 ]; then
    echo "INFO: Command successfully executed"
  else
    echo "ERROR: Command failed"
    exit 1
  fi
}

################################################################################
# Main

SQUID_IP=$1
if [[ $SQUID_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  # add the route for marked HTTP(S) traffic, to Squid
  run_or_exit "ip route add default via $SQUID_IP dev eth0 table 100"
else
  echo "ERROR: Please specify the IP of squid container as the only parameter to this script!"
fi
