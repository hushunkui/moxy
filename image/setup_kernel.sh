#!/bin/bash

set -x
set -e

KERNEL=${1:? Specify output filename for kernel}

BASEDIR=$( dirname "${BASH_SOURCE[0]}" )
BASEDIR=$( realpath $BASEDIR )


VER=$( uname -r | tr '-' ' ' | awk '{print $1}' )

if ! test -f /usr/src/linux-source-${VER}/Makefile ; then
    pushd /usr/src
        tar xvf linux-source-${VER}.tar.bz2 
    popd
fi

pushd /usr/src/linux-source-${VER}
    rm -f arch/x86/boot/bzImage
    rm -f usr/initramfs_data.cpio.gz

    if ! diff $BASEDIR/linux_config_minimal .config ; then
        cp $BASEDIR/linux_config_minimal .config
    fi
    make -j3 bzImage
    cp arch/x86/boot/bzImage $KERNEL
popd

# $BASEDIR/simpleiso -o $BASEDIR/build/stage2.iso $KERNEL
