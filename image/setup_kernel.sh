#!/bin/bash

set -x
set -e

BASEDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

BUILD=${1:? Specify build directory}
CONFIG=${2:? Name of configuration}

KERNEL=$BUILD/vmlinuz_$CONFIG
INITRAM=$BUILD/initramfs_$CONFIG
CONFDIR=$BASEDIR/$CONFIG

VER=$( uname -r | tr '-' ' ' | awk '{print $1}' )


if ! test -f /usr/src/linux-source-${VER}/Makefile ; then
    pushd /usr/src
        tar xvf linux-source-${VER}.tar.bz2 
    popd
fi

pushd /usr/src/linux-source-${VER}

    if test ${INITRAM}.cpio.gz -nt $KERNEL ; then
        rm -f arch/x86/boot/bzImage
        rm -f usr/initramfs_data.cpio.gz

        if ! diff <( sed -e "s|INITRAMFS_SOURCE_DIR|$INITRAM|g" \
             $CONFDIR/linux_config_minimal ) .config ; then
            sed -e "s|INITRAMFS_SOURCE_DIR|$INITRAM|g" \
                $CONFDIR/linux_config_minimal > .config
        fi

        make -j3 bzImage
        cp arch/x86/boot/bzImage $KERNEL
    fi
popd

# $BASEDIR/simpleiso -o $BASEDIR/build/stage2.iso $KERNEL
