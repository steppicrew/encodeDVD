#!/bin/bash

mkv="$1"

if [ ! -f "$mkv" ]; then
    echo "Usage: $0 <mkv file with mvc track> [<cropTop> [<cropLeft> [<cropBottom> [<cropRight>]]]]"
    exit 2
fi

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

crop="`cropdetect "$mkv"`"

tempdir="`dirname "$0"`/tmp/`basename "$mkv" .mkv`"
outdir="`dirname "$0"`/out"
test -d "$tempdir" || mkdir -p "$tempdir"
test -d "$outdir"  || mkdir -p "$outdir"

function cleanup {
    echo "Exiting"
    test -d "$tempdir" && rm -rf "$tempdir"
}

trap cleanup EXIT


meta="$tempdir/demux.meta"
avs="$tempdir/sbs.avs"

echo "MUXOPT --no-pcr-on-video-pid --new-audio-pes --demux --vbr  --vbv-len=500" > "$meta"
tsMuxeR "$mkv" | perl -e '
    use strict;
    my %data= ();
    while (<>) {
        chomp;
        unless ( $_ ) {
            if ( %data && ( $data{type} eq "MVC" || $data{type} eq "H.264" ) ) {
                print "$data{id}, \"'"`realpath "$mkv"`"'\", insertSEI, contSPS, track=$data{track}, lang=$data{lang}, subTrack=$data{subtrack}\n";
            }
            %data= ();
            next;
        }
        $data{track}= $1 if /Track ID:\s+(\d+)/;
        $data{type}= $1 if /Stream type:\s+(\S+)/;
        $data{id}= $1 if /Stream ID:\s+(\S+)/;
        $data{lang}= $1 if /Stream lang:\s+(\w+)/;
        $data{subtrack}= $1 if /subTrack:\s+(\d+)/;
    }
' >> "$meta"

echo "************** demuxing video"
tsMuxeR "$meta" "$tempdir"

for file in "$tempdir/"*.mvc; do
    mvc="$file"
done
for file in "$tempdir/"*.264; do
    left="$file"
done

if [ ! -r "$mvc" -o ! -r "$left" ]; then
    echo "could not find MVC or 264 file in $@"
    ls -al "$tempdir"
    exit 2
fi

echo "************** trying to detect frame count"
frames=`mkvinfo "$mkv" | perl -e '
    use strict;
    my $length= 0;
    my $fps= 0;
    my $type= "";
    while ( <> ) {
        $length= $1 if /Dauer: ([\d\.]+)s/;
        $type= $1 if /Spurtyp: (\w+)/;
        $fps= $1 if $type eq "video" && /Standarddauer: [\d\.]+ms \(([\d\.]+) Bilder/;
    }
    print int($length * $fps);
'`

leftCodec="vid.selecteven()"
rightCodec="vid.selectodd()"

if [ "$cropTop" ]; then
    leftCodec="Crop($leftCodec,$cropLeft,$cropTop,-$cropRight,-$cropBottom)"
    rightCodec="Crop($rightCodec,$cropLeft,$cropTop,-$cropRight,-$cropBottom)"
fi

cat > "$avs" << EOT
LoadPlugin("DGMVCDecode.dll")
vid=dgmvcsource("`realpath "$left"`","`realpath "$mvc"`",view=0,frames=$frames)
left=$leftCodec
right=$rightCodec
stackhorizontal(horizontalreduceby2(left),horizontalreduceby2(right))
EOT

outfile="$outdir/`basename "$mkv"`"

echo "************** starting encoding $outfile"

ffmpegCmd=(
    ffmpeg -f yuv4mpegpipe -i - -i "$mkv" -map 0:v -map 1 -map -1:v -c:v libx264
    -preset medium -tune film -level 4 -crf 25
    -b-pyramid normal -partitions p8x8,b8x8,i4x4
    -c:a copy -c:s copy -c:d copy -c:t copy
    "$outfile"
)
wineCmd=( wine avs2yuv "$avs" - )

"${wineCmd[@]}" | "${ffmpegCmd[@]}"

cleanFile "$outfile"
