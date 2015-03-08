#!/bin/bash

inName="$1"

test -z "$crf" && crf=25

cropTop="$2"
cropLeft="$3"
cropBottom="$4"
cropRight="$5"

if [ "$cropTop" ]; then
    test -z "$cropLeft"   && cropLeft="0"
    test -z "$cropBottom" && cropBottom="$cropTop"
    test -z "$cropRight"  && cropRight="$cropLeft"
fi

outName="`dirname "$inName"`/out/`basename "$inName"`"

filter=()
if [ "$cropTop" ]; then
    filter=( "${filter[@]}" "crop=in_w-$cropLeft-$cropRight:in_h-$cropTop-$cropBottom:$cropLeft:$cropTop" )
fi

# detecting interlace
interlaced=`ffmpeg -filter:v idet -frames:v 1000 -an -f rawvideo -y /dev/null -i "$inName" 2>&1 | perl -e '
    use strict;
    my $inter= 0;
    my $progress= 0;
    while (<>) {
        if ( /TFF:\s+(\d+)\s+BFF:\s+(\d+)\s+Progressive:\s+(\d+)/ ) {
            $inter+= $1 + $2;
            $progress+= $3;
        }
    }
    print "1" if $inter > $progress;
'`

test "$interlaced" && filter=( "yadif" "${filter[@]}" )

test "${filter[*]}" && filter=( '-vf' "${filter[@]}" )

ffmpeg -i "$inName" -c:v libx264 \
    -preset medium -tune film -level 4 -crf "$crf" \
    -b-pyramid normal -partitions p8x8,b8x8,i4x4 \
    -an "${filter[@]}" \
    "$outName"
