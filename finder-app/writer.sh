#!/bin/sh

set -x

if [ "$#" -ne 2 ]; then
    echo "filepath and writestr are both required"
    exit 1
fi

filepath="$1"
writestr="$2"

mkdir -p "$(dirname $filepath)" && echo "$writestr" > "$filepath"
