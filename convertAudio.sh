#!/bin/bash

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

inFile="$1"
outFile=".out/`basename "$1"`"

audioOptions=( `audiodetect "$inFile"` )

test -d ".out" || mkdir ".out"

ffmpegCmd=(
    ffmpeg -i "$inFile" -map 0 -c copy
    "${audioOptions[@]}"
    "$outFile"
)

echo "Running in 10s: ${ffmpegCmd[@]}" && sleep 10

"${ffmpegCmd[@]}"

cleanFile "$outFile"


