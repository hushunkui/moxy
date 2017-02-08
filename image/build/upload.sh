#!/bin/bash

BUCKET=${1:?Please provide bucket name}

set -ex

for dir in stage2 mellanox-roms coreos ; do
  gsutil rsync -r "${dir}" "gs://${BUCKET}/${dir}" || :
done

gsutil -m setmeta -r -h "Cache-Control:private, max-age=0, no-transform" "gs://${BUCKET}"
