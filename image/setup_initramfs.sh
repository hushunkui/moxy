#!/bin/bash

set -x
set -e

BASEDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

BUILD=${1:? Specify build directory}
CONFIG=${2:? Name of configuration}

INITRAM=$BUILD/initramfs_$CONFIG
CONFDIR=$BASEDIR/$CONFIG

ARCH_ALT=$( dpkg --print-architecture | sed -e 's/i//g' )
ARCH=$( arch | sed -e 's/i686/i386/' )
KERN=$( uname --kernel-release )

mkdir -p $BUILD
mkdir -p $INITRAM

# Include the build support library.
source lib/support.sh


if ! test -f $BUILD/busybox/bin/busybox ; then
    pushd $BUILD
        unpack busybox-1.25.0 /moxy/vendor/busybox-1.25.0.tar.bz2
        pushd busybox-1.25.0
            cp $CONFDIR/busybox_config ./.config
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
        pushd kexec-tools-2.0.13
            # ./bootstrap
            LDFLAGS=-static ./configure --prefix $BUILD/kexec
            make
            make install
        popd
    popd
fi


if ! test -f $BUILD/epoxy/bin/epoxyget_386 ; then
    pushd $BUILD
        test -d epoxy || git clone git@github.com:stephen-soltesz/epoxy.git
	# x86_64
        unpack go /moxy/vendor/go1.7.linux-amd64.tar.gz
        export GOROOT=$BUILD/go
        export PATH=$PATH:$GOROOT/bin
        export EPOXYDIR=$PWD/epoxy
        # export EPOXYDIR=/epoxy
        export GOPATH=$EPOXYDIR
        GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go install epoxy/cmd/epoxyget
        strip ${EPOXYDIR}/bin/epoxyget
        mv ${EPOXYDIR}/bin/epoxyget ${BUILD}/epoxy/bin/epoxyget_amd64

        GOOS=linux GOARCH=386 CGO_ENABLED=0 go install epoxy/cmd/epoxyget
        strip ${EPOXYDIR}/bin/linux_386/epoxyget
        mv ${EPOXYDIR}/bin/linux_386/epoxyget ${BUILD}/epoxy/bin/epoxyget_386

	# i386
        # unpack go /moxy/vendor/go1.7.linux-386.tar.gz
        # mv go go386
        # export GOROOT=$BUILD/go386
        # export PATH=$PATH:$GOROOT/bin
        # export GOPATH=$PWD/epoxy
        # CGO_ENABLED=0 go install epoxy/cmd/epoxyget
        # strip $BUILD/epoxy/bin/epoxyget
        # mv $BUILD/epoxy/bin/epoxyget $BUILD/epoxy/bin/epoxyget-386
    popd
fi


if ! test -f $BUILD/keys/dropbear_ecdsa_host_key ; then
    mkdir -p $BUILD/keys
    $BUILD/dropbear/bin/dropbearkey -t rsa -f $BUILD/keys/dropbear_rsa_host_key
    $BUILD/dropbear/bin/dropbearkey -t dss -f $BUILD/keys/dropbear_dss_host_key
    $BUILD/dropbear/bin/dropbearkey -t ecdsa -f $BUILD/keys/dropbear_ecdsa_host_key
fi


echo "Compressing binaries"
mkdir -p $BUILD/upx_build
for file in $BUILD/busybox/bin/busybox \
            $BUILD/dropbear/bin/dropbearmulti \
            $BUILD/epoxy/bin/epoxyget_amd64 \
            $BUILD/epoxy/bin/epoxyget_386 \
            $BUILD/kexec/sbin/kexec ; do
    name=$(basename $file)
    if ! test -f $BUILD/upx_build/$name ; then
        upx --brute -o$BUILD/upx_build/$name $file
    fi
done

cp $BUILD/busybox/bin/busybox      $BUILD/upx_build
cp $BUILD/dropbear/bin/scp         $BUILD/upx_build
cp $BUILD/dropbear/sbin/dropbear   $BUILD/upx_build
cp $BUILD/epoxy/bin/epoxyget_amd64 $BUILD/upx_build
cp $BUILD/epoxy/bin/epoxyget_386   $BUILD/upx_build
cp $BUILD/kexec/sbin/kexec         $BUILD/upx_build

echo "Setting up directory hierarchy"
rm -rf $INITRAM
mkdir -p $INITRAM
pushd $INITRAM
    mkdir -p {tmp,bin,sbin,etc/ssl,etc/dropbear,lib/${ARCH}-linux-gnu,lib64}
    mkdir -p {proc,sys,var/log,dev/pts,root/.ssh,newroot,usr/bin,usr/sbin}
    chmod 700 root

    mknod -m 622 dev/console c 5 1
    mknod -m 622 dev/tty0 c 4 0

    cp $BUILD/upx_build/busybox       bin
    if [[ "${ARCH}" = "x86_64" ]] ; then
        cp $BUILD/upx_build/epoxyget_amd64      bin/epoxyget
    else
        cp $BUILD/upx_build/epoxyget_386        bin/epoxyget
    fi
    chmod 755 bin/epoxyget
    cp $BUILD/upx_build/dropbearmulti bin
    cp $BUILD/upx_build/kexec         sbin

    # Debug binary.
    cp /usr/bin/strace                usr/bin/

    # Server SSH Keys
    # TODO: remove when keys are generated at boot time.
    # cp $BUILD/keys/*                  etc/dropbear

    # Certificates
    cp -L -r /etc/ssl/certs           etc/ssl
    certhash=$( openssl x509 -noout -hash -in $CONFDIR/epoxy-ca.pem )
    cp $CONFDIR/epoxy-ca.pem          etc/ssl/certs/${certhash}.0
    cat etc/ssl/certs/*.pem etc/ssl/certs/*.0 > etc/ssl/certs/ca-certificates.crt

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
    ln -s /bin/busybox          bin/sh
    ln -s /bin/dropbearmulti    bin/scp
    ln -s /bin/dropbearmulti    bin/dropbearkey
    ln -s /bin/dropbearmulti    sbin/dropbear

    touch etc/mdev.conf

    # Add the root user and group.
    echo "root:UEgHv/R7qZCmQ:0:0:Linux,,,:/root:/bin/sh" > etc/passwd
    echo "root:*:0:root" > etc/group
    echo 'export PATH=$PATH:/sbin:/usr/sbin' > root/.profile
    echo 'set -o vi' >> root/.profile

    cp $CONFDIR/init        ./
    cp $CONFDIR/inittab     etc
    cp $CONFDIR/rc.local    etc
    cp $CONFDIR/resolv.conf etc

    # Force ownership for all files in the initramfs.
    chown -R root:root ./
popd


pushd $INITRAM
    find . | cpio -H newc -o | gzip -c > ${INITRAM}.cpio.gz
popd
