#!/bin/bash

inName="$1"

outName="`dirname "$inName"`/out/`basename "$inName"`"

ffmpeg -i "$inName" -c:v libx264 \
    -preset medium -tune film -level 4 -crf 20 \
    -b-pyramid normal -partitions p8x8,b8x8,i4x4 \
    -an \
    "$outName"
