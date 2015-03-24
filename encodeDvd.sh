#!/bin/bash

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

simpleEncode "$@" -crf 20

# multiplex new video and all other streams from original file into out file
#mv "$outName" "$outName.tmp"
#ffmpeg -i "$outName.tmp" -i "$inName" -c copy -map 0:v -map 1 -map -1:v "$outName" && rm "$outName.tmp"
