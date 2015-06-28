#!/bin/bash

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

inFile="$1"
outFile=".out/`basename "$1"`"

audioOptions=( `audiodetect "$1"` )

test -d ".out" || mkdir ".out"

ffmpeg -i "$inFile" -map 0 -c:v copy "${audioOptions[@]}" -c:s copy -c:d copy -c:t copy "$outFile"
cleanFile "$outFile"


