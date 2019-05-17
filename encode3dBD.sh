#!/bin/bash

mkv="$1"

if [ ! -f "$mkv" ]; then
    echo "Usage: $0 <mkv file with mvc track> [<cropTop> [<cropBottom]]"
    echo "Example (1920x1080->1920x800): $0 <mkv file with mvc track> 140"
    exit 2
fi

cropTop="$2"
cropBottom="$3"

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

widthHeight=(`widthHeight "$mkv"`)
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

function cleanup {
    echo "Exiting"
#    test -d "$tempdir" && rm -rf "$tempdir"
}

trap cleanup EXIT

h264File="$outdir/tmp.`basename "$mkv" '.mkv' | tr -c "[:alnum:].-\n" "_"`.264"
#h264File="`echo "$h264File" | tr " äöüßÄÖÜ" "_"`"
outfile="$outdir/`basename "$mkv"`"
out3d="$outdir/tmp.3d.`basename "$mkv"`"

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
    "$out3d"
)
wineCmd=( wine FRIMDecode -i:mvc "$h264File" -o - -sbs )

"${wineCmd[@]}" | "${ffmpegCmd[@]}"

newLength=`du -m "$out3d" | cut -f 1`

# only remove h264 file if result is larger than 100k
test "$newLength" -gt 20 && rm "$h264File" || exit 1

ffmpegCmd=(
    ffmpeg -i "$out3d" -i "$mkv" -map 0:v -map 1 -map -1:v
    -c copy
    "$outfile"
)

"${ffmpegCmd[@]}"

newLength=`du -m "$outfile" | cut -f 1`

# only remove h264 file if result is larger than 100k
test "$newLength" -gt 20 && rm "$out3d" || exit 1

cleanFile "$outfile"

mkvpropedit --edit track:1 -s stereo-mode=1 "$outfile"

