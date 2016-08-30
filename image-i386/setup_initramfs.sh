#!/bin/bash

set -x
set -e

BUILD=${1:-Specify build directory}
SSHKEY=${2:-authorized keys file}
BASEDIR=$PWD
INITRAM=$BUILD/initramfs_base

ARCH=$( arch | sed -e 's/i686/i386/' )
KERN=$( uname --kernel-release )

mkdir -p $BUILD
mkdir -p $INITRAM


function unpack () {
  dir=$1
  url=$2
  tgz=$( basename $url )
  if ! test -d $dir ; then
    if ! test -f $tgz ; then
      wget $url
      tar -xvf $tgz
    fi
  fi
}

if /bin/true ; then

if ! test -f $BUILD/busybox/bin/busybox ; then
pushd $BUILD
    unpack busybox-1.25.0 https://busybox.net/downloads/busybox-1.25.0.tar.bz2
    pushd busybox-1.25.0
        cp $BASEDIR/busybox_config ./.config
        make all
        make install
    popd
popd
fi


if ! test -f $BUILD/dropbear/sbin/dropbear ; then
pushd $BUILD
    unpack dropbear-2016.74 https://matt.ucc.asn.au/dropbear/releases/dropbear-2016.74.tar.bz2
    pushd dropbear-2016.74/
        mkdir -p zlibincludes
        cp /usr/include/zlib.h /usr/include/${ARCH}-linux-gnu/zconf.h zlibincludes
        export CFLAGS="-Izlibincludes -I../zlibincludes"
        export LDFLAGS=/usr/lib/${ARCH}-linux-gnu/libz.a
        STATIC=1 ./configure --prefix=$BUILD/dropbear
        make PROGRAMS="dropbear dropbearkey dbclient scp" MULTI=1 STATIC=1 SCPPROGRESS=1
        make PROGRAMS="dropbear dropbearkey dbclient scp" MULTI=1 STATIC=1 SCPPROGRESS=1 install
        # make STATIC=1
        # make install STATIC=1
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


if ! test -f $BUILD/epoxy-get ; then
pushd $BUILD
  arch=$( dpkg --print-architecture | sed -e 's/i//g' )
  unpack go https://storage.googleapis.com/golang/go1.7.linux-${arch}.tar.gz
  export GOROOT=$BUILD/go
  export PATH=$PATH:$GOROOT/bin

  CGO_ENABLED=0 go build /moxy/epoxy-get/epoxy-get.go 
  strip $BUILD/epoxy-get
  upx --brute $BUILD/epoxy-get
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
mkdir -p $INITRAM/{bin,sbin,etc/ssl,etc/dropbear,lib/${ARCH}-linux-gnu,proc,sys,dev/pts,root,newroot,usr/bin,usr/sbin}
cp $BUILD/busybox/bin/busybox $INITRAM/bin
#cp $BUILD/dropbear/sbin/dropbear $INITRAM/sbin
#cp $BUILD/dropbear/bin/scp $INITRAM/bin
cp $BUILD/kexec/sbin/kexec $INITRAM/sbin
cp $BUILD/epoxy-get $INITRAM/bin
cp $BUILD/keys/* $INITRAM/etc/dropbear

#test -f centos_initrd || \
#    curl -o centos_initrd https://github.com/stephen-soltesz/pxe-test/raw/master/i386/initrd.img
#test -f centos_vmlinuz || \
#    curl -o centos_vmlinuz https://github.com/stephen-soltesz/pxe-test/raw/master/i386/vmlinuz
#test -f centos_x86_64_initrd || \
#    curl -o centos_x86_64_initrd https://github.com/stephen-soltesz/pxe-test/raw/master/x86_64/initrd.img
#test -f centos_x86_64_vmlinuz || \
#    curl -o centos_x86_64_vmlinuz https://github.com/stephen-soltesz/pxe-test/raw/master/x86_64/vmlinuz

# Certificates
cp -L -r /etc/ssl/certs $INITRAM/etc/ssl/

# ssh authorized keys.
mkdir -p $INITRAM/root/.ssh
cp $SSHKEY $INITRAM/root/.ssh/authorized_keys
chown root:root $INITRAM/root/.ssh/authorized_keys
chmod 700 $INITRAM/root/


# Strace
#cp /usr/bin/strace $INITRAM/usr/bin/
cp /lib/${ARCH}-linux-gnu/libc.so.6 $INITRAM/lib/${ARCH}-linux-gnu
test -f /lib/ld-linux.so.2 && cp /lib/ld-linux.so.2 $INITRAM/lib
test -f /lib64/ld-linux-x86-64.so.2 && cp /lib64/ld-linux-x86-64.so.2 $INITRAM/lib
#cp /lib/${ARCH}-linux-gnu/libnss* $INITRAM/lib/${ARCH}-linux-gnu
#cp /lib/${ARCH}-linux-gnu/libnsl* $INITRAM/lib/${ARCH}-linux-gnu
cp /etc/nsswitch.conf $INITRAM/etc

ln -s busybox $INITRAM/bin/sh
touch $INITRAM/etc/mdev.conf

cp init.sh $INITRAM/
chmod +x $INITRAM/init.sh
ln -s init.sh $INITRAM/init

MODBASE=lib/modules/${KERN}
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
#  cp $BUILD/vmlinuz root/vmlinuz
#  find . | cpio -H newc -o | gzip -c > root/initramfs
  find . | cpio -H newc -o | gzip -c > $BUILD/initramfs
popd

chown -R root:root $INITRAM 

pushd $BUILD
  test -d ipxe || git clone git://git.ipxe.org/ipxe.git
popd


pushd $BUILD
  pushd ipxe/src
    make bin/ipxe.iso EMBED=$BASEDIR/embed.ipxe,$BUILD/vmlinuz,$BUILD/initramfs  # DEBUG=basemem,hidemem,memmap,settings
    cp bin/ipxe.iso $BASEDIR/
    #make bin/ipxe.lkrn EMBED=$BASEDIR/embed.ipxe,$BUILD/centos_vmlinuz,$BUILD/centos_initramfs  # DEBUG=basemem,hidemem,memmap,settings
    #cp bin/ipxe.lkrn $BASEDIR/ipxe_centos.lkrn
  popd
popd

fi
