#!/bin/sh

if [ $# -ne 2 ]
then
    echo "usage: ./finder.sh filesdir searchstr"
    exit 1
fi

if ! [ -d $1 ]
then
    echo "directory '$1' does not exist"
    exit 1
fi

filesdir=$1
searchstr=$2

echo "filesdir=$filesdir searchstr=$searchstr"

total_files=$(find $filesdir -type f -print | wc -l)
found_files=$(find $filesdir -type f -print | xargs grep -l "$searchstr" | wc -l)

echo "The number of files are $total_files and the number of matching lines are $found_files"
