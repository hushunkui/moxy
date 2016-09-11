#!/bin/bash

set -x
set -e

BASEDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

BUILD=${1:? Specify build directory}
CONFIG=${2:? Name of configuration}

BOOTSTRAP=$BUILD/initramfs_$CONFIG
CONFDIR=$BASEDIR/$CONFIG

KERN=$( uname --kernel-release )

function unpack () {
  dir=$1
  url=$2
  tgz=$( basename $url )
  if ! test -d $dir ; then
    if ! test -f $tgz ; then
      wget $url
    fi
    tar -xvf $tgz
  fi
}

mkdir -p $BOOTSTRAP
# Disable interactive prompt from some packages.
export DEBIAN_FRONTEND=noninteractive
debootstrap --arch amd64 xenial $BOOTSTRAP


cp $CONFDIR/resolv.conf $BOOTSTRAP/etc/resolv.conf
cp $CONFDIR/fstab       $BOOTSTRAP/etc/fstab
cp $CONFDIR/rc.local    $BOOTSTRAP/etc/rc.local
cp $CONFDIR/init        $BOOTSTRAP/init


if ! test -d $BOOTSTRAP/root/mft-4.4.0-44 ; then
    if ! test -f $BOOTSTRAP/usr/bin/flint ; then
        pushd $BUILD
            unpack mft-4.4.0-44 http://www.mellanox.com/downloads/MFT/mft-4.4.0-44.tgz
            cp -ar mft-4.4.0-44 $BOOTSTRAP/root
        popd
    fi
fi

if ! test -f $BOOTSTRAP/usr/bin/flint ; then
    mount -t proc proc $BOOTSTRAP/proc
    mount -t sysfs sysfs $BOOTSTRAP/sys

    PACKAGES=$( cat mlx_config/extra.packages )

    # Extra packages needed for correct operation.
    chroot $BOOTSTRAP apt-get install -y $PACKAGES

    # Run the mlx firmware tools installation script.
    chroot $BOOTSTRAP bash -c "cd /root/mft-4.4.0-44 && ./install.sh"

    # Remove unnecessary packages and data.
    chroot $BOOTSTRAP apt-get autoremove -y linux-generic linux-headers-4.4.0-21 linux-headers-`uname -r`
    chroot $BOOTSTRAP apt-get remove -y linux-firmware
    chroot $BOOTSTRAP apt-get clean -y
    chroot $BOOTSTRAP rm -rf /root/mft-4.4.0-44
    chroot $BOOTSTRAP rm -rf /boot/*

    umount $BOOTSTRAP/proc
    umount $BOOTSTRAP/sys
fi


echo "Setting up directory hierarchy"
mkdir -p $BOOTSTRAP/etc/dropbear
cp $BUILD/dropbear/sbin/dropbear $BOOTSTRAP/sbin
cp $BUILD/dropbear/bin/scp $BOOTSTRAP/bin
cp $BUILD/keys/* $BOOTSTRAP/etc/dropbear


mkdir -p $BOOTSTRAP/root/.ssh
cp $BASEDIR/authorized_keys  $BOOTSTRAP/root/.ssh/authorized_keys
chown root:root $BOOTSTRAP/root/.ssh/authorized_keys
chmod 700 $BOOTSTRAP/root/


if ! test -f $BOOTSTRAP/usr/local/util/zbin ; then
    pushd $BUILD
        pushd ipxe/src
          make util/zbin
          cp -ar util $BOOTSTRAP/usr/local/
          cp /vagrant/updaterom.sh $BOOTSTRAP/usr/local/util
          cp /vagrant/flashrom.sh $BOOTSTRAP/usr/local/util
        popd
    popd
fi


pushd $BOOTSTRAP
    find . | cpio -H newc -o | gzip -c > ${BOOTSTRAP}.cpio.gz
popd
