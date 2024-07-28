#!/bin/bash

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Error: Two arguments required."
    echo "Usage: $0 <file_path> <string_to_write>"
    exit 1
fi

writefile="$1"
writestr="$2"

# Create the directory path if it doesn't exist
mkdir -p "$(dirname "$writefile")"

# Write the content to the file
if echo "$writestr" > "$writefile"; then
    echo "File created successfully: $writefile"
else
    echo "Error: Could not create file $writefile"
    exit 1
fi