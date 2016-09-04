#!/bin/bash

set -x
set -e

UTIL=$( dirname "${BASH_SOURCE[0]}" )

MROM_BIN=${1:?mrom bin file}
MROM_ZINFO=${2:?mrom zinfo file}
OUTPUT=${3:?output filename}

$UTIL/zbin $MROM_BIN $MROM_ZINFO > $OUTPUT
perl $UTIL/padimg.pl --blksize=512 --byte=0xff $OUTPUT
perl $UTIL/fixrom.pl $OUTPUT
