#!/usr/bin/env bash

set -euo pipefail

rm -rf ref_builds
mkdir -p ref_builds/build-info-v1

for file in lib/ve-governance/*;
do
    echo "Processing $file"
    filename=$(echo $file | sed 's/\//-/g')
    mkdir -p ref_builds/build-info-$filename
    forge build --force --root=$file
    mv $file/out/build-info/*.json ref_builds/build-info-$filename
done
