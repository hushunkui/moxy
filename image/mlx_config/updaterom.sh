#!/bin/bash

set -x
set -e
# https://epoxy-test-1.measurementlab.net/v1/hosts/$HOSTNAME/ConnectX3.mrom

ROMURL=$( cat /proc/cmdline | tr ' ' '\n' | grep -E 'epoxy.mrom=' | sed -e 's/epoxy.mrom=//g' )
ACKURL=$( cat /proc/cmdline | tr ' ' '\n' | grep -E 'epoxy.nextboot_disable_url=' | sed -e 's/epoxy.nextboot_disable_url=//g' )
if test -n "$ROMURL" ; then
    echo "DOWNLOADING ROM"
    eval "wget -O epoxy.mrom $ROMURL"
    if ! test -f epoxy.mrom ; then
        echo "Error: failed to download epoxy.mrom from $ROMURL"
        exit 1
    fi

    echo "UPDATING ROM"
    /usr/local/util/flashrom.sh epoxy.mrom
    
    echo "ACKNOWLEDGE COMPLETE"
    wget --quiet -O - --post-data='public_ssh_host_key=' $ACKURL > /dev/null
fi
