#!/bin/bash

set -x
set -e

ROM=${1:?PXE ROM to burn to NIC}
DEV=/dev/mst/mt4099_pci_cr0


# Backup original.
flint --device "${DEV}" rrom current.mrom

NEW_VERSION=$( flint --image "${ROM}" qrom )
CUR_VERSION=$( flint --image current.mrom qrom )

DELAY=60

if [[ "${NEW_VERSION}" == "${CUR_VERSION}" ]] ; then
    echo "Current ROM version matches new ROM version."
    echo "Sleeping $DELAY seconds..."
    sleep $DELAY
    exit 1
fi


echo "ROM Versions:"
echo "   Currently installed: $CUR_VERSION"
echo "   Updating to:         $NEW_VERSION"


# Query before.
flint --device "$DEV" query
mlxconfig --device "$DEV" query

# Burn ROM to NIC.
flint --device "$DEV" brom "$ROM"
flint --device "$DEV" verify

# Query after.
flint --device "$DEV" query
mlxconfig --device "$DEV" query

# Extra verify that new ROM matches expected ROM.
flint --device "$DEV" rrom latest.mrom
diff latest.mrom "$ROM"
