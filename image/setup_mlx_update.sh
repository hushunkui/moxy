#!/bin/bash

set -x
set -e

BASEDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

BUILD=${1:? Specify build directory}
CONFIG=${2:? Name of configuration}

BOOTSTRAP=$BUILD/initramfs_$CONFIG
CONFDIR=$BASEDIR/$CONFIG

KERN=$( uname --kernel-release )
KERNVER=${KERN%%-generic}

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


function enter_with_proc() {
    local bootstrap=$1
    mount -t proc proc $bootstrap/proc
    mount -t sysfs sysfs $bootstrap/sys
}


function exit_with_proc() {
    local bootstrap=$1
    umount $bootstrap/proc
    umount $bootstrap/sys
}


if ! test -f $BOOTSTRAP/build.date ; then
    mkdir -p $BOOTSTRAP
    rm -rf $BOOTSTRAP/dev
    # Disable interactive prompt from grub-pc or other packages.
    export DEBIAN_FRONTEND=noninteractive
    debootstrap --arch amd64 xenial $BOOTSTRAP && date --iso-8601=seconds --utc > $BOOTSTRAP/build.date
fi


if ! test -d $BOOTSTRAP/root/mft-4.4.0-44 ; then
    if ! test -f $BOOTSTRAP/usr/bin/flint ; then
        pushd $BUILD
            unpack mft-4.4.0-44 http://www.mellanox.com/downloads/MFT/mft-4.4.0-44.tgz
            cp -ar mft-4.4.0-44 $BOOTSTRAP/root
        popd
    fi
fi

enter_with_proc $BOOTSTRAP
    # Extra packages needed for correct operation.
    PACKAGES=$( cat mlx_update_config/extra.packages )
    chroot $BOOTSTRAP apt-get install -y $PACKAGES
exit_with_proc $BOOTSTRAP


if ! test -f $BOOTSTRAP/lib/modules/${KERN}/updates/dkms/mst_pci.ko ; then
enter_with_proc $BOOTSTRAP

    PACKAGES=$( cat mlx_update_config/build.packages )
    chroot $BOOTSTRAP apt-get install -y $PACKAGES

    # Run the mlx firmware tools installation script.
    chroot $BOOTSTRAP bash -c "cd /root/mft-4.4.0-44 && ./install.sh"

    # Remove source directory since the unnecessary binary packages are large.
    chroot $BOOTSTRAP rm -rf /root/mft-4.4.0-44

    # Remove packages needed for building.
    # NOTE: DO NOT "autoremove" gcc or make, as this uninstalls dkms and the
    # mft module built above.
    chroot $BOOTSTRAP apt-get autoremove -y linux-headers-generic linux-generic \
        linux-headers-${KERNVER} linux-headers-${KERN}

exit_with_proc $BOOTSTRAP
fi


# Kernel panics unless /init is defined. Use systemd for init.
ln --force --symbolic sbin/init $BOOTSTRAP/init

# Copy ePoxy certificates into BOOTSTRAP fs.
certhash=$( openssl x509 -noout -hash -in $CONFDIR/epoxy-ca.pem )
cp $CONFDIR/epoxy-ca.pem        $BOOTSTRAP/etc/ssl/certs/${certhash}.0

# Enable static resolv.conf
# TODO: use systemd for network configuration entirely.
rm -f $BOOTSTRAP/etc/resolv.conf
cp $CONFDIR/resolv.conf $BOOTSTRAP/etc/resolv.conf
# If permissions are incorrect, apt-get will fail to read contents.
chmod 644 $BOOTSTRAP/etc/resolv.conf

# TODO: enable sshd?
cp $CONFDIR/fstab       $BOOTSTRAP/etc/fstab

# Set a default root passwd.
chroot $BOOTSTRAP bash -c 'echo -e "demo\ndemo\n" | passwd'

# TODO: disable root login via ssh.


# Enable simple rc.local script for post-setup processing.
# rc.local.service runs after networking.service
cp $CONFDIR/rc.local    $BOOTSTRAP/etc/rc.local
enter_with_proc $BOOTSTRAP
    chroot $BOOTSTRAP systemctl enable rc.local.service
exit_with_proc $BOOTSTRAP


echo "Removing unnecessary packages and files from $BOOTSTRAP"
enter_with_proc $BOOTSTRAP

    # Remove grub packages, since these are unnecessary.
    chroot $BOOTSTRAP apt-get autoremove -y grub-pc grub-common grub2-common grub-gfxpayload-lists grub-pc-bin
    chroot $BOOTSTRAP apt-get remove -y linux-firmware
    chroot $BOOTSTRAP apt-get clean -y
    chroot $BOOTSTRAP rm -rf /boot/*
    chroot $BOOTSTRAP rm -rf /var/cache/*

exit_with_proc $BOOTSTRAP


# echo "Setting up directory hierarchy"
# mkdir -p $BOOTSTRAP/etc/dropbear
# cp $BUILD/dropbear/sbin/dropbear $BOOTSTRAP/sbin
# cp $BUILD/dropbear/bin/scp $BOOTSTRAP/bin
# cp $BUILD/keys/* $BOOTSTRAP/etc/dropbear


echo "Adding SSH authorized keys"
mkdir -p $BOOTSTRAP/root/.ssh
cp $BASEDIR/authorized_keys  $BOOTSTRAP/root/.ssh/authorized_keys
chown root:root $BOOTSTRAP/root/.ssh/authorized_keys
chmod 700 $BOOTSTRAP/root/


if ! test -d $BOOTSTRAP/usr/local/util ; then
    pushd $BUILD
        test -d ipxe || git clone git://git.ipxe.org/ipxe.git
        pushd ipxe/src
          make util/zbin
          cp -ar util $BOOTSTRAP/usr/local/
        popd
    popd
fi
cp $CONFDIR/flashrom.sh $BOOTSTRAP/usr/local/util
cp $CONFDIR/updaterom.sh $BOOTSTRAP/usr/local/util


pushd $BOOTSTRAP
    find . | cpio -H newc -o | gzip -c > ${BOOTSTRAP}.cpio.gz
popd
cp /boot/vmlinuz-$( uname -r ) ${BUILD}/vmlinuz_${CONFIG}
