#!/bin/bash

set -x
set -e

BUILD=${1:? Specify build directory}
INITRAM=${2:? Base directory for generated initramfs}

BASEDIR=$( dirname "${BASH_SOURCE[0]}" )
BASEDIR=$( realpath $BASEDIR )

ARCH_ALT=$( dpkg --print-architecture | sed -e 's/i//g' )
ARCH=$( arch | sed -e 's/i686/i386/' )
KERN=$( uname --kernel-release )

mkdir -p $BUILD
mkdir -p $INITRAM


function unpack () {
  dir=$1
  tgz=$2
  if ! test -d $dir ; then
    if ! test -f $tgz ; then
      echo "error: no such file $tgz"
      exit 1
    fi
    tar xvf $tgz
  fi
}


if ! test -f $BUILD/busybox/bin/busybox ; then
    pushd $BUILD
        unpack busybox-1.25.0 /moxy/vendor/busybox-1.25.0.tar.bz2
        pushd busybox-1.25.0
            cp $BASEDIR/busybox_config ./.config
            make all
            make install
        popd
    popd
fi


if ! test -f $BUILD/dropbear/sbin/dropbear ; then
    pushd $BUILD
        unpack dropbear-2016.74 /moxy/vendor/dropbear-2016.74.tar.bz2
        pushd dropbear-2016.74/
            mkdir -p zlibincludes
            cp /usr/include/zlib.h /usr/include/${ARCH}-linux-gnu/zconf.h zlibincludes
            export CFLAGS="-Izlibincludes -I../zlibincludes"
            export LDFLAGS=/usr/lib/${ARCH}-linux-gnu/libz.a
            STATIC=1 ./configure --prefix=$BUILD/dropbear
            make PROGRAMS="dropbear dropbearkey dbclient scp" MULTI=1 STATIC=1 SCPPROGRESS=1
            make PROGRAMS="dropbear dropbearkey dbclient scp" MULTI=1 STATIC=1 SCPPROGRESS=1 install
        popd
    popd
fi


if ! test -f $BUILD/kexec/sbin/kexec ; then
    pushd $BUILD
        unpack kexec-tools-2.0.13 /moxy/vendor/kexec-tools-2.0.13.tar.xz
        pushd kexec-tools
            # ./bootstrap
            LDFLAGS=-static ./configure --prefix $BUILD/kexec
            make
            make install
        popd
    popd
fi


if ! test -f $BUILD/epoxy-get ; then
    pushd $BUILD
        unpack go /moxy/vendor/go1.7.linux-${ARCH_ALT}.tar.gz
        export GOROOT=$BUILD/go
        export PATH=$PATH:$GOROOT/bin

        CGO_ENABLED=0 go build /moxy/epoxy-get/epoxy-get.go
        strip $BUILD/epoxy-get
    popd
fi


if ! test -f $BUILD/keys/dropbear_ecdsa_host_key ; then
    mkdir -p $BUILD/keys
    $BUILD/dropbear/bin/dropbearkey -t rsa -f $BUILD/keys/dropbear_rsa_host_key
    $BUILD/dropbear/bin/dropbearkey -t dss -f $BUILD/keys/dropbear_dss_host_key
    $BUILD/dropbear/bin/dropbearkey -t ecdsa -f $BUILD/keys/dropbear_ecdsa_host_key
fi


echo "Setting up directory hierarchy"
rm -rf $INITRAM
mkdir -p $INITRAM
pushd $INITRAM
    mkdir -p {bin,sbin,etc/ssl,etc/dropbear,lib/${ARCH}-linux-gnu,lib64}
    mkdir -p {proc,sys,var/log,dev/pts,root/.ssh,newroot,usr/bin,usr/sbin}
    chmod 700 root

    mknod -m 622 dev/console c 5 1
    mknod -m 622 dev/tty0 c 4 0

    cp $BUILD/busybox/bin/busybox     bin
    cp $BUILD/dropbear/bin/scp        bin
    cp $BUILD/dropbear/sbin/dropbear  sbin
    cp $BUILD/epoxy-get               bin
    cp $BUILD/kexec/sbin/kexec        sbin

    # Debug binary.
    cp /usr/bin/strace                usr/bin/

    # Server SSH Keys
    cp $BUILD/keys/*                  etc/dropbear

    # Certificates
    cp -L -r /etc/ssl/certs           etc/ssl

    # SSH authorized keys.
    cp $BASEDIR/authorized_keys       root/.ssh/authorized_keys

    # Copy libraries because there is no static version of nss.
    cp /lib/${ARCH}-linux-gnu/libc.so.6      lib/${ARCH}-linux-gnu
    cp /lib/${ARCH}-linux-gnu/libresolv.so.2 lib/${ARCH}-linux-gnu
    cp /lib/${ARCH}-linux-gnu/libnss*        lib/${ARCH}-linux-gnu
    cp /lib/${ARCH}-linux-gnu/libnsl*        lib/${ARCH}-linux-gnu
    cp /lib/ld-linux.so.2                    lib || :
    cp /lib64/ld-linux-x86-64.so.2           lib64 || :
    ln -s /lib64/ld-linux-x86-64.so.2        lib || :
    cp /etc/nsswitch.conf                    etc

    # Make the first symlink from busybox to sh so /init can run.
    ln -s busybox          bin/sh
    touch etc/mdev.conf

    # Add the root user and group.
    echo "root:UEgHv/R7qZCmQ:0:0:Linux,,,:/root:/bin/sh" > etc/passwd
    echo "root:*:0:root" > etc/group
    echo 'export PATH=$PATH:/sbin:/usr/sbin' > root/.profile
    echo 'set -o vi' >> root/.profile

    # Setup DNS configuration.
    echo "nameserver 8.8.8.8" > etc/resolv.conf
    echo "nameserver 8.8.4.4" >> etc/resolv.conf

    cp $BASEDIR/init       ./
    cp $BASEDIR/inittab    etc
    cp $BASEDIR/rc.local   etc

    # Force ownership for all files in the initramfs.
    chown -R root:root ./
popd


pushd $INITRAM
    find . -type f -executable \
        -a ! -name "*.so.*" \
        -a ! -name "*.sh" \
        -a ! -name "strace" \
        -a ! -name "init" \
        -a ! -name "rc.local" \
        -print \
        -a -exec upx -9 {} \;
    find . | cpio -H newc -o | gzip -c > $BUILD/initramfs.gz
popd
