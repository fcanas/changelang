#!/bin/bash

# given a file extension as a parameter, find all files with that extension in the current directory and its subdirectories
# and run the program `changelang.swift` on each file with the additional parameters "-l eng"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file_extension>"
    exit 1
fi

file_extension=$1


find . -type f -name "*.$file_extension" | while read -r file; do
    echo "Processing $file"
    changelang.swift "$file" -l eng
done



