#!/bin/bash

mkv="$1"
cd "`dirname "$mkv"`"
workingFile=(`basename "$mkv" | md5sum`)
ln -s "`basename "$mkv"`" "$workingFile"

function cleanup {
    echo "Exiting"
    rm "$workingFile"
#    test -d "$tempdir" && rm -rf "$tempdir"
}

trap cleanup EXIT


if [ ! -f "$mkv" ]; then
    echo "Usage: $0 <mkv file with mvc track> [<cropTop> [<cropBottom]]"
    echo "Example (1920x1080->1920x800): $0 <mkv file with mvc track> 140"
    exit 2
fi

cropTop="$2"
cropBottom="$3"

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

widthHeight=(`widthHeight "$workingFile"`)
streamId="${widthHeight[0]}"
streamWidth="${widthHeight[1]}"
streamHeight="${widthHeight[2]}"
streamFps="${widthHeight[3]}"

if [ "$cropTop" ]; then
    test "$cropBottom" || cropBottom="$cropTop"
    crop="crop=$streamWidth:$(( $streamHeight - $cropTop - $cropBottom)):0:$cropTop"
else
    echo "Detecting crop"
    # Only crop horizontally
    crop="`cropdetect "$mkv" | perl -ne 's/^crop=\d+:(\d+):\d+:(\d+)/crop='$streamWidth':$1:0:$2/; print;'`"
fi

outdir="`dirname "$mkv"`/.out"
test -d "$outdir"  || mkdir -p "$outdir"

h264File="$outdir/tmp.$workingFile.264"
#h264File="`echo "$h264File" | tr " äöüßÄÖÜ" "_"`"
outfile="$outdir/`basename "$mkv"`"
out3d="$outdir/tmp.3d.$workingFile.mkv"

echo mkvextract tracks "$workingFile" "$streamId:$h264File"
test -s "$h264File" || mkvextract tracks "$workingFile" "$streamId:$h264File"

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
    "$out3d"
)
wineCmd=( wine FRIMDecode -i:mvc "$h264File" -o - -sbs )

"${wineCmd[@]}" | "${ffmpegCmd[@]}"

newLength=`du -m "$out3d" | cut -f 1`

# only remove h264 file if result is larger than 20m
test "$newLength" -gt 20 && rm "$h264File" || exit 1

ffmpegCmd=(
    ffmpeg -i "$out3d" -i "$mkv" -map 0:v -map 1 -map -1:v
    -c copy
    "$outfile"
)

"${ffmpegCmd[@]}"

newLength=`du -m "$outfile" | cut -f 1`

# only remove h264 file if result is larger than 20m
test "$newLength" -gt 20 && rm "$out3d" || exit 1

cleanFile "$outfile"

mkvpropedit --edit track:1 -s stereo-mode=1 "$outfile"

