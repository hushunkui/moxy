#!/bin/bash

set -x
set -e

# TODO(soltesz): epoxyclient should download the ROM also.
# e.g. epoxyclient --mrom <outfile>
romurl=
for field in $( cat /proc/cmdline ) ; do
  if [[ "epoxy.mrom" == "${field%%=*}" ]] ; then
    romurl=${field##epoxy.mrom=}
    break
  fi
done

if test -z "$romurl" ; then
  echo "WARNING: no ROM URL found. Giving up."
  exit 1
fi

echo "Downloading ROM"
wget -O epoxy.mrom "${$romurl}"
if ! test -f epoxy.mrom || ! test -s epoxy.mrom ; then
    echo "Error: failed to download epoxy.mrom from ${romurl}"
    exit 1
fi

echo "Updating ROM"
/usr/local/util/flashrom.sh epoxy.mrom

# TODO(soltesz): use `epoxyclient --endstage` to acknowldge.
echo "WARNING: No not acknowledging success. Taking no action."

echo "TODO: restart system on success."
