#!/bin/bash

set -x
set -e

BASEDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )
CONFIG_DIR=$( realpath ${BASEDIR}/mlx_roms )

# Include the build support library.
source ${BASEDIR}/lib/support.sh


BUILD=${1:? Specify build directory}

STAGE1_TEMPLATE=${CONFIG_DIR}/stage1-template.ipxe
STAGE1_CONFIG_OUTDIR=${BUILD}/stage1_scripts
ROM_OUTDIR=${BUILD}/mlx_roms
FLEXBOOT=${BUILD}/flexboot


# TODO: patch flexboot source to fix TLS download bug.
pushd $BUILD
    if ! test -d flexboot ; then
        FLEXBOOT=FlexBoot-3.4.521_SRC
        unpack ${FLEXBOOT} /moxy/vendor/${FLEXBOOT}.tar.gz
        mv ${FLEXBOOT} flexboot
        pushd flexboot
            # Use gcc-4.8 since gcc-5 (default in xenial) causes build failure.
            sed -i -e 's/ gcc/ gcc-4.8/g' Makefile
			# TODO: is there a better way than disbling all warning-errors?
			# Otherwise, net/udp/dhcp.c fails to build due to:
			#   error: dereferencing type-punned pointer will break
			#   strict-aliasing rules [-Werror=strict-aliasing]
            sed -i -e 's/-Wall//g' Makefile Makefile.housekeeping
            # Enable embedding scripts an certs in the build process.
            sed -i -e 's/"   bin/" EMBED=${EMBED} TRUST=${TRUST} bin/g' \
                pxebuild.py
		    # Copy a pre-defined configuration to enables TLS.
		    cp $CONFIG_DIR/config_general.h config/general.h
        popd
    fi
popd


# TODO: Checkout operator.
# TODO: Only generate scripts once.
# Create all stage1.ipxe scripts.
pushd $BASEDIR/operator/plsync
    mkdir -p ${STAGE1_CONFIG_OUTDIR}
    ./mlabconfig.py --format=server-network-config \
        --template "${STAGE1_TEMPLATE}" \
		--filename "${STAGE1_CONFIG_OUTDIR}/stage1-{{hostname}}.ipxe"
popd


VERSION=3.4.755
CERTS="$CONFIG_DIR/epoxy-ca.pem,$CONFIG_DIR/giag2.pem"

mkdir -p ${ROM_OUTDIR}/${VERSION}
for STAGE1 in `ls ${STAGE1_CONFIG_OUTDIR}/*iad1t*` ; do
    hostname=${STAGE1##*stage1-}
    hostname=${hostname%%.ipxe}
    pushd ${FLEXBOOT}
        EMBED=${STAGE1} TRUST=${CERTS} ./pxebuild.py -v ${VERSION} -d 4099
    popd
    cp ${FLEXBOOT}/bin/ConnectX3.mrom ${ROM_OUTDIR}/${VERSION}/${hostname}.mrom
done
