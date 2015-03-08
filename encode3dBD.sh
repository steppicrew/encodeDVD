#!/bin/bash

mkv="$1"

cropTop="$2"
cropLeft="$3"
cropBottom="$4"
cropRight="$5"

if [ "$cropTop" ]; then
    test -z "$cropLeft"   && cropLeft="0"
    test -z "$cropBottom" && cropBottom="$cropTop"
    test -z "$cropRight"  && cropRight="$cropLeft"
fi


if [ ! -f "$mkv" ]; then
    echo "Usage: $0 <mkv file with mvc track> [<cropTop> [<cropLeft> [<cropBottom> [<cropRight>]]]]"
    exit 2
fi

tempdir="`dirname "$0"`/tmp/`basename "$mkv" .mkv`"
outdir="`dirname "$0"`/out"
test -d "$tempdir" || mkdir -p "$tempdir"
test -d "$outdir"  || mkdir -p "$outdir"

function cleanup {
    test -d "$tempdir" && rm -rf "$tempdir"
}

trap cleanup EXIT


meta="$tempdir/demux.meta"
avs="$tempdir/sbs.avs"

echo "MUXOPT --no-pcr-on-video-pid --new-audio-pes --demux --vbr  --vbv-len=500" > demux.meta
tsMuxeR "$mkv" | perl -e '
    use strict;
    my %data= ();
    while (<>) {
        chomp;
        unless ( $_ ) {
            if ( %data && ( $data{type} eq "MVC" || $data{type} eq "H.264" ) ) {
                print "$data{id}, \"'"$mkv"'\", insertSEI, contSPS, track=$data{track}, lang=$data{lang}, subTrack=$data{subtrack}\n";
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

cat > half-sbs.avs << EOT
LoadPlugin("DGMVCDecode.dll")
vid=dgmvcsource("$left","$mvc",view=0,frames=$frames)
left=$leftCodec
right=$rightCodec
stackhorizontal(horizontalreduceby2(left),horizontalreduceby2(right))
EOT

outfile="$outdir/`basename "$mkv"`"

echo "************** starting encoding $outfile"
# wine avs2yuv full-sbs.avs - | ffmpeg -f yuv4mpegpipe -i - -c:v libx264 -preset fast -tune film "$outfile"
wine avs2yuv half-sbs.avs - | ffmpeg -f yuv4mpegpipe -i - -c:v libx264 \
    -preset medium -tune film -level 4 -crf 25 \
    -b-pyramid normal -partitions p8x8,b8x8,i4x4 \
    "$outfile"

