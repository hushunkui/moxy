#!/bin/bash

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
