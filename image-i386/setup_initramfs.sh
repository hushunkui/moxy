#!/bin/bash

set -x
set -e

BUILD=${1:-Specify build directory}
BASEDIR=$PWD
INITRAM=$BUILD/initramfs_base

mkdir -p $BUILD
mkdir -p $INITRAM

if /bin/false ; then

if ! test -f $BUILD/busybox/bin/busybox ; then
pushd $BUILD
    wget https://busybox.net/downloads/busybox-1.25.0.tar.bz2
    tar -xvf busybox-1.25.0.tar.bz2 
    pushd busybox-1.25.0
        cp $BASEDIR/busybox_config ./.config
        make all
        make install
    popd
popd
fi


if ! test -f $BUILD/dropbear/sbin/dropbear ; then
pushd $BUILD
    #wget https://matt.ucc.asn.au/dropbear/releases/dropbear-2016.74.tar.bz2
    #tar -xvf dropbear-2016.74.tar.bz2
    pushd dropbear-2016.74/
        mkdir -p zlibincludes
        cp /usr/include/zlib.h /usr/include/i386-linux-gnu/zconf.h zlibincludes
        export CFLAGS="-Izlibincludes -I../zlibincludes"
        export LDFLAGS=/usr/lib/i386-linux-gnu/libz.a
        # STATIC=1 ./configure --prefix=$BUILD/dropbear
        make STATIC=1
        make install STATIC=1
    popd
popd
fi


if ! test -f $BUILD/kexec/sbin/kexec ; then
pushd $BUILD
    test -d kexec-tools || git clone git://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git
    pushd kexec-tools
        ./bootstrap
        LDFLAGS=-static ./configure --prefix $BUILD/kexec
        make
        make install 
    popd
popd
fi

fi
if /bin/true ; then

if ! test -f $BUILD/keys/dropbear_ecdsa_host_key ; then
  mkdir -p $BUILD/keys
  $BUILD/dropbear/bin/dropbearkey -t rsa -f $BUILD/keys/dropbear_rsa_host_key
  $BUILD/dropbear/bin/dropbearkey -t dss -f $BUILD/keys/dropbear_dss_host_key
  $BUILD/dropbear/bin/dropbearkey -t ecdsa -f $BUILD/keys/dropbear_ecdsa_host_key
fi

rm -rf $INITRAM

echo "Setting up directory hierarchy"
mkdir -p $INITRAM/{bin,sbin,etc/dropbear,lib,proc,sys,root,newroot,usr/bin,usr/sbin}
cp $BUILD/busybox/bin/busybox $INITRAM/bin
cp $BUILD/dropbear/sbin/dropbear $INITRAM/sbin
cp $BUILD/kexec/sbin/kexec $INITRAM/sbin
cp $BUILD/keys/* $INITRAM/etc/dropbear

ln -s busybox $INITRAM/bin/sh
touch $INITRAM/etc/mdev.conf

cp init.sh $INITRAM/
chmod +x $INITRAM/init.sh
ln -s init.sh $INITRAM/init

MODBASE=lib/modules/4.4.0-21-generic
MODPATH=$MODBASE/kernel/drivers/net/ethernet/intel
mkdir -p $INITRAM/$MODPATH/e1000
mkdir -p $INITRAM/$MODPATH/e1000e

cp /$MODPATH/e1000/e1000.ko $INITRAM/$MODPATH/e1000
cp /$MODPATH/e1000e/e1000e.ko $INITRAM/$MODPATH/e1000e
cp /$MODBASE/modules.builtin $INITRAM/$MODBASE
cp /$MODBASE/modules.order $INITRAM/$MODBASE

depmod -a -b $INITRAM/

cat <<EOF > $INITRAM/etc/resolv.conf
nameserver 8.8.8.8
nameserver 192.168.0.1
EOF


cp /boot/vmlinuz-$( uname -r ) $BUILD/vmlinuz
pushd $INITRAM 
  rm -f root/initramfs
  cp $BUILD/vmlinuz root/vmlinuz
  find . | cpio -H newc -o | gzip -c > root/initramfs
  find . | cpio -H newc -o | gzip -c > $BUILD/initramfs
popd

chown -R root:root $INITRAM 

#pushd $BUILD
#  git clone git://git.ipxe.org/ipxe.git
#popd


pushd $BUILD
  pushd ipxe/src
    make bin/ipxe.iso EMBED=$BASEDIR/embed.ipxe,$BUILD/vmlinuz,$BUILD/initramfs  # DEBUG=basemem,hidemem,memmap,settings
    cp bin/ipxe.iso $BASEDIR/
  popd
popd

fi
