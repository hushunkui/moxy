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
ROM_OUTDIR=${BUILD}/mellanox-roms
FLEXBOOT=${BUILD}/flexboot


# TODO: patch flexboot source to fix TLS download bug.
pushd $BUILD
    if ! test -d flexboot ; then
        version=FlexBoot-3.4.521_SRC
        version=flexboot-20160705
        unpack ${version} /moxy/vendor/${version}.tar.gz
        mv ${version} ${FLEXBOOT}
        pushd flexboot/src
            # Use gcc-4.8 since gcc-5 (default in xenial) causes build failure.
            sed -i -e 's/ gcc/ gcc-4.8/g' -e 's/)gcc/)gcc-4.8/g' Makefile

            git apply $CONFIG_DIR/romprefix.S.diff

            # TODO: is there a better way than disbling all warning-errors?
            # Otherwise, net/udp/dhcp.c fails to build due to:
            #   error: dereferencing type-punned pointer will break
            #   strict-aliasing rules [-Werror=strict-aliasing]
            # sed -i -e 's/-Wall//g' Makefile Makefile.housekeeping
            # Enable embedding scripts an certs in the build process.
            # sed -i -e 's/"   bin/" EMBED=${EMBED} TRUST=${TRUST} bin/g' \
            #     pxebuild.py

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


define() {
  IFS='\n' read -r -d '' ${1} || true;
}

get_extra_flags() {
  local target=$1
  local version=$2
  local device_id=

  local major=${version%%.*}
  local sub=${version%.*} ; sub=${sub#*.}
  local minor=${version##*.}

  major=$( printf "%04x" $major )
  sub=$( printf "%04x" $sub )
  minor=$( printf "%04x" $minor )

  case $target in

    ConnectX-3.mrom)
      device_id=0x1003
      ;;

    ConnectX-3Pro.mrom)
      device_id=0x1007
      ;;

    *)
      echo "Error: unsupported target name: $target" 1>&2
      exit 1
      ;;
  esac

  define extra_flags <<EOM
    -Wno-error=strict-aliasing
    -Wno-error=address
    -Wno-pointer-to-int-cast
    -Wno-error=maybe-uninitialized
    -DMLX_BUILD
    -DDEVICE_CX3
    -DFLASH_CONFIGURATION
    -D__MLX_0001_MAJOR_VER_=0x0010${major}
    -D__MLX_MIN_SUB_MIN_VER_=0x${sub}${minor}
    -D__MLX_DEV_ID_00ff=${device_id}00ff
    -D__BUILD_VERSION__=\"$version\"
    -Idrivers/infiniband/mlx_utils_flexboot/include/
    -Idrivers/infiniband/mlx_utils/include/
    -Idrivers/infiniband/mlx_utils/include/public/
    -Idrivers/infiniband/mlx_utils/include/private/
    -Idrivers/infiniband/mlx_nodnic/include/
    -Idrivers/infiniband/mlx_nodnic/include/public/
    -Idrivers/infiniband/mlx_nodnic/include/private/
    -Idrivers/infiniband/mlx_utils_flexboot/tests/include/
    -Idrivers/infiniband/mlx_utils/mlx_lib/mlx_reg_access/
    -Idrivers/infiniband/mlx_utils/mlx_lib/mlx_nvconfig/
    -Idrivers/infiniband/mlx_utils/mlx_lib/mlx_vmac/
EOM
  echo $extra_flags
}

VERSION=3.4.800
CERTS="$CONFIG_DIR/epoxy-ca.pem,$CONFIG_DIR/giag2.pem"
PROCS=`getconf _NPROCESSORS_ONLN`

for stage1 in `ls ${STAGE1_CONFIG_OUTDIR}/*mlab3.iad1t*` ; do
    hostname=${stage1##*stage1-}
    hostname=${hostname%%.ipxe}
    pushd ${FLEXBOOT}/src
        for device in ConnectX-3.mrom ConnectX-3Pro.mrom ; do
            mkdir -p ${ROM_OUTDIR}/$device/${VERSION}
            make clean; rm -rf bin
            # iPXE does not detect that the embedded script is different.
            # So, we must start over.
            # TODO(soltesz): make the reset more fine-grained.
            EXTRA_CFLAGS="$( get_extra_flags $device $VERSION )"
            make -j ${PROCS} bin/$device EXTRA_CFLAGS="$EXTRA_CFLAGS" EMBED=${stage1} TRUST=${CERTS}
            cp ${FLEXBOOT}/src/bin/$device ${ROM_OUTDIR}/$device/${VERSION}/${hostname}.mrom
        done
    popd
done
