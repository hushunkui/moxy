#!/bin/bash

set -x
set -e
./util/zbin bin/8086100f.mrom.bin bin/8086100f.mrom.zinfo > bin/8086100f.mrom
perl ./util/padimg.pl --blksize=512 --byte=0xff bin/8086100f.mrom
perl ./util/fixrom.pl bin/8086100f.mrom
