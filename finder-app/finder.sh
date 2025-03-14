#!/bin/sh

set -x

filesdir="$1"
searchstr="$2"

if [ "$#" -ne 2 ]; then
    echo "filesdir and searchstr are both required"
    exit 1
fi

if [[ ! -d "$1" ]]; then
    echo "$filesdir is not a directory"
    exit 1
fi

file_count="$(grep -R -l $searchstr $filesdir | wc -l)"
line_count="$(grep -R $searchstr $filesdir | wc -l)"

echo "The number of files are $file_count and the number of matching lines are $line_count"
