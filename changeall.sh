#!/bin/bash

# given a file extension as a parameter, find all files with that extension in the current directory and its subdirectories
# and run `changelang` on each file with the additional parameters.

if [ $# -lt 3 ]; then
    echo "Usage: $0 <file_extension> -a <audio_language_code> -s <subtitle_language_code>"
    exit 1
fi

file_extension=$1
changelang_args=("${@:2}")

find . -type f -name "*.$file_extension" -print0 | xargs -0 -I {} changelang "{}" "${changelang_args[@]}"
#                                         ▲               ▲
#  for special characters in filenames ───┘               |
#  handle null-terminated output from find ───────────────┘
