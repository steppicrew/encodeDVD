#!/bin/bash

mkv="$1"

if [ ! -f "$mkv" ]; then
    echo "Usage: $0 <mkv file with mvc track> [<cropTop> [<cropLeft> [<cropBottom> [<cropRight>]]]]"
    exit 2
fi

cropTop="$2"
cropLeft="$3"
cropBottom="$4"
cropRight="$5"

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

widthHeight=(`widthHeight "$mkv"`)
streamId="${widthHeight[0]}"
streamWidth="${widthHeight[1]}"
streamHeight="${widthHeight[2]}"
streamFps="${widthHeight[3]}"

if [ "$cropTop" ]; then
    test "$cropLeft" || cropLeft="0"
    test "$cropBottom" || cropBottom="$cropTop"
    test "$cropRight" || cropRight="$cropLeft"
else
    echo "Detecting crop"
    # Only crop horizontally
    crop="`cropdetect "$mkv" | perl -ne 's/^crop=\d+:(\d+):\d+:(\d+)/crop='$streamWidth':$1:0:$2/; print;'`"
fi


tempdir="`dirname "$0"`/tmp/`basename "$mkv" .mkv`"
tempdir="`echo "$tempdir" | tr " äöüßÄÖÜ" "_"`"
outdir="`dirname "$0"`/out"
test -d "$tempdir" || mkdir -p "$tempdir"
test -d "$outdir"  || mkdir -p "$outdir"

function cleanup {
    echo "Exiting"
#    test -d "$tempdir" && rm -rf "$tempdir"
}

trap cleanup EXIT

h264File="$tempdir/movie.264"
outfile="$outdir/`basename "$mkv"`"

test -s "$h264File" || mkvextract tracks "$mkv" "$streamId:$h264File"

filter="scale=$streamWidth:$streamHeight"
test "$crop" && filter="$filter,$crop"
filter=( '-vf' "$filter" )

ffmpegCmd=(
    ffmpeg -y -f rawvideo
    -s:v "$(( $streamWidth * 2 ))x$streamHeight"
    -r "$streamFps"
    -i -
    -c:v libx264
    "${filter[@]}"
    -preset medium -tune film
    -b-pyramid normal -partitions p8x8,b8x8,i4x4
    "$outfile.3d.mkv"
)
wineCmd=( wine FRIMDecode -i:mvc "$h264File" -o - -sbs )

#echo "${wineCmd[@]}"
#echo "${ffmpegCmd[@]}"
#exit

"${wineCmd[@]}" | "${ffmpegCmd[@]}"

ffmpegCmd=(
    ffmpeg -i "$outfile.3d.mkv" -i "$mkv" -map 0:v -map 1 -map -1:v
    -c copy
    "$outfile"
)

"${ffmpegCmd[@]}"

cleanFile "$outfile"
