#!/bin/bash

set -x
set -e

ROM=${1:?PXE ROM to burn to NIC}
DEV=/dev/mst/mt4099_pci_cr0

# Backup original.
flint -d "$DEV" rrom backup.mrom

# Query before.
flint -d "$DEV" q
mlxconfig -d "$DEV" q

# Burn ROM to NIC.
flint -d "$DEV" brom "$ROM"
flint -d "$DEV" verify

# Query after.
flint -d "$DEV" q
mlxconfig -d "$DEV" q

# Extra verify that new ROM matches expected ROM.
flint -d "$DEV" rrom current.mrom
diff current.mrom "$ROM"
