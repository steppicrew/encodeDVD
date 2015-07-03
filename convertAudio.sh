#!/bin/bash

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

inFile="$1"
outFile="$inFile"

audioOptions=( `audiodetect "$inFile"` )

if test "$audioOptions"; then
    outFile=".out/`basename "$inFile"`"
    test -d ".out" || mkdir ".out"

    ffmpegCmd=(
        ffmpeg -i "$inFile" -map 0 -c copy
        "${audioOptions[@]}"
        "$outFile"
    )

    echo "Running in 10s: ${ffmpegCmd[@]}" && sleep 10

    "${ffmpegCmd[@]}"

    cleanFile "$outFile"
fi


