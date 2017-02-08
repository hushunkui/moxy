#!/bin/bash

set -x
set -e

ROM=${1:?PXE ROM to burn to NIC}
# TODO(soltesz): identify mt4103 if present.
if [[ -e /dev/mst/mt4099_pci_cr0 ]] ; then
    DEV=/dev/mst/mt4099_pci_cr0
elif [[ -e /dev/mst/mt4103_pci_cr0 ]] ; then
    DEV=/dev/mst/mt4103_pci_cr0
fi
ERROR_DELAY=60
PAUSE=5


# Backup original.
flint --device "${DEV}" rrom current.mrom

NEW_VERSION=$( flint --image "${ROM}" qrom )
CUR_VERSION=$( flint --image current.mrom qrom )

echo "ROM Versions:"
echo "   Currently installed: $CUR_VERSION"
echo "   Updating to:         $NEW_VERSION"

# NOTE: This permits rollbacks when NEW_VERSION is less than CUR_VERSION.
if [[ "${NEW_VERSION}" == "${CUR_VERSION}" ]] ; then
    echo "Oops! Current ROM version already matches new ROM version."
    echo "Taking no action."
    echo "Sleeping $ERROR_DELAY seconds..."
    # TODO(soltesz): log everything.
    sleep $ERROR_DELAY
    exit 0
fi


# This is required for configuring systems for the first time. These will be a
# no-ops for previously-updated machines.
# NOTE: the long options are unfortunately different from the flint command.
echo "Setting device options to PXE boot on PORT 1."
mlxconfig --dev "${DEV}" -y -e set LEGACY_BOOT_PROTOCOL_P1=PXE
mlxconfig --dev "${DEV}" -y -e set BOOT_OPTION_ROM_EN_P1=True


# Query before.
echo "Before update"
flint --device "$DEV" query
mlxconfig --dev "$DEV" query
sleep $PAUSE

# Burn ROM to NIC.
echo "Performing update now..."
# NOTE: we must specify --allow_rom_change to prevent this error on new NICs.
#
# "Burn ROM failed: The device FW contains common FW/ROM Product Version - The
# ROM cannot be updated separately."
#
# While it's true that the "Product Version" is out of sync with a custom ROM,
# we do not believe this matters.
flint --allow_rom_change --device "$DEV" brom "$ROM"
flint --device "$DEV" verify
sleep $PAUSE

# Query after.
echo "After update"
flint --device "$DEV" query
# mlxconfig does not support the long form "--device" flag.
mlxconfig --dev "$DEV" query
sleep $PAUSE

# Extra verify that new ROM matches expected ROM.
flint --device "$DEV" rrom latest.mrom
diff latest.mrom "$ROM"
