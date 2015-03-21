

function cropdetect {
    local file="$1"
    local length=`mkvinfo "$file" | perl -ne 'if (/Dauer:\s+([\d\.]+)/) { print int($1 * $_ / 11) . " " for (1..10); }'`
    local start
    for start in $length; do
        ffmpeg -ss $start -i "$file" -t 1 -vf cropdetect -f null - 2>&1
    done | perl -e '
        use strict;
        my @widthLeft= ();
        my @heightTop= ();
        while (<>) {
            next unless /Parsed_cropdetect.+crop=(\d+):(\d+):(\d+):(\d+)/;
            push @widthLeft, [$1, $3];
            push @heightTop, [$2, $4];
        }

        # find the greates width with the lowest left (same for height/top)
        @widthLeft= sort { $b->[0] <=> $a->[0] || $a->[1] <=> $b->[1] } @widthLeft;
        @heightTop= sort { $b->[0] <=> $a->[0] || $a->[1] <=> $b->[1] } @heightTop;

        my $width=  $widthLeft[0][0];
        my $left=   $widthLeft[0][1];
        my $height= $heightTop[1][0];
        my $top=    $heightTop[1][1];

        # check for lefts/tops that are smaller by more than 4 pixel from found left/top
        my @lefts= grep { $left - $_ > 4 } map { $_->[1] } @widthLeft;
        my @tops=  grep { $top  - $_ > 4 } map { $_->[1] } @heightTop;

        # if any was found, return an invalid value and exit
        if ( @lefts || @tops ) {
            for ( my $i= 0; $i < @widthLeft; $i++ ) {
                print $widthLeft[$i][0] . ":" . $heightTop[$i][0] . ":" . $widthLeft[$i][1] . ":" . $heightTop[$i][1] . " ";
            }
            exit;
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
    videoOptions=(
        "-preset" "medium"
        "-tune" "film"
        "-b-pyramid" "normal"
        "-partitions" "p8x8,b8x8,i4x4"
        "$@"
    )

    outDir="`dirname "$inName"`/.out"
    outName="$outDir/`basename "$inName"`"
    test -d "$outDir" || mkdir -p "$outDir"

    filter=( )

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

    # extract filter and look for some options (-crf)
    crfFound=0
    filter=""
    newOptions=( )
    lastOption=""
    for o in "${videoOptions[@]}"; do
        [ "$o" = '-crf' ]   && crfFound=1

        if [ "$lastOption" = "-vf" ]; then
            filter="$o"
        fi

        # skip '-vf' and filter option
        if [ "$o" != '-vf' -a "$lastOption" != '-vf' ]; then
            newOptions=( "${newOptions[@]}" "$o" )
        fi
        lastOption="$o"
    done
    videoOptions=( "${newOptions[@]}" )

    # if there is no crf options, add -crf 20
    test "$crfFound" -eq 0 && videoOptions=( "${videoOptions[@]}" '-crf' '25' )

    # if no crop is given, try detecting and prepend
    if [[ "$filter" != *crop=* ]]; then
        echo "Detecting crop...."
        crop="`cropdetect "$inName"`"
        if [ "$crop" ]; then
            test "$filter" && filter=",$filter"
            filter="${crop}${filter}"
        fi
    fi

    # if video is interaces, prepend yadif filter
    if [ "$interlaced" ]; then
        test "$filter" && filter=",$filter"
        filter="yadif${filter}"
    fi

    # append filter if needed
    if [ "$filter" ]; then
        videoOptions=( "${videoOptions[@]}" '-vf' "$filter" )
    fi

    cmd=(
        ffmpeg -i "$inName" -map 0 -c:v libx264
        "${videoOptions[@]}"
        -c:a copy -c:s copy -c:d copy -c:t copy
        "$outName"
    )

    echo "Running in 10s ${cmd[@]}"
    sleep 10s
    "${cmd[@]}"

    cleanFile "$outName"
}
