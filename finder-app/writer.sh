#!/bin/bash

# Check if two arguments are provided
if [ $# -ne 2 ]; then
    echo "Error: Two arguments required: <file path> <text to write>"
    exit 1
fi

writefile=$1
writestr=$2

# Extract the directory path from the given file path
writedir=$(dirname "$writefile")

# Create the directory if it doesn't exist
mkdir -p "$writedir"

# Write the string to the file (overwrite if exists)
echo "$writestr" > "$writefile"

# Check if file was successfully created
if [ $? -ne 0 ]; then
    echo "Error: Could not create file '$writefile'"
    exit 1
fi

echo "File '$writefile' successfully created with content: '$writestr'"

