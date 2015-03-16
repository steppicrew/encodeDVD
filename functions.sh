

function cropdetect {
    local file="$1"
    local length=`mkvinfo "$file" | perl -ne 'if (/Dauer:\s+([\d\.]+)/) { print int($1 * $_ / 11) . " " for (1..10); }'`
    local start
    for start in $length; do
        ffmpeg -ss $start -i "$file" -t 1 -vf cropdetect -f null - 2>&1
    done | perl -e '
        use strict;
        my $width= 0;
        my $height= 0;
        my $left= 10_000;
        my $top= 10_000;
        while (<>) {
            next unless /Parsed_cropdetect.+crop=(\d+):(\d+):(\d+):(\d+)/;
            $width= $1  if $1 > $width;
            $height= $2 if $2 > $height;
            $left= $3   if $3 < $left;
            $top= $4    if $4 < $top;
        }
        print "crop=$width:$height:$left:$top" if $width && $height;
    '
}

function cleanFile {
    local file="$1"

    mkclean --remux "$file" "$file.clean" && mv "$file.clean" "$file"
}

function simpleEncode {
    inName="$1"

    shift
    options=( )
    test "$*" && options=( "$@" )

    outDir="`dirname "$inName"`/.out"
    outName="$outDir/`basename "$inName"`"
    test -d "$outDir" || mkdir -p "$outDir"

    filter=( )

    echo "Detecting crop...."
    crop="`cropdetect "$inName"`"
    test "$crop" && filter=( "${filter[@]}" "$crop" )

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

    cmd=(
        ffmpeg -i "$inName" -map 0 -c:v libx264
        -preset medium -tune film -crf 20
        -b-pyramid normal -partitions p8x8,b8x8,i4x4
        "${filter[@]}"
        "${options[@]}"
        -c:a copy -c:s copy -c:d copy -c:t copy
        "$outName"
    )

    echo "Running in 10s ${cmd[@]}"
    sleep 10s
    "${cmd[@]}"

    cleanFile "$outName"
}
