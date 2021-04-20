
export LANG="C"

function cropdetect {
    local file="$1"
    local length=`ffmpeg -i "file:$file" -c:none /dev/null 2>&1 | perl -ne '
        use strict;
        use warnings;
        if (/Duration:\s+(\d+):(\d+):(\d+\.\d+)/) {
            my $d= $1 * 3_600 + $2 * 60 + $3;
            print int($d * $_ / 10) . " " for (2..8);
        }
    '`
    local start
    for start in $length; do
        ffmpeg -ss $start -i "file:$file" -t 1 -vf cropdetect -f null - 2>&1
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

        # check for lefts/tops that are smaller by more than 4 pixel from found left/top (do not check last 3 values)
        my @lefts= grep { $left - $_ > 4 } map { $_->[1] } (splice @widthLeft, -3);
        my @tops=  grep { $top  - $_ > 4 } map { $_->[1] } (splice @heightTop, -3);

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

function widthHeight {
    local file="$1"
    mkvinfo --ui-language en_US "$file" | perl -e '
        use warnings;
        use strict;

        my ($id, $width, $height, $fps);

        while (<>) {
            chomp;
            ($id, $width, $height, $fps)= () if /^\| \+ Track\b/;
            $id= $1 if /^\|  \+ Track number: \d+ \(track ID for mkvmerge \& mkvextract: (\d+)\)/;
            $width= $1 if /\|   \+ Pixel width: (\d+)/;
            $height= $1 if /\|   \+ Pixel height: (\d+)/;
            $fps= $1 if /\((\d+(?:\.\d+)) frames\/fields/;
            next unless defined $id && $width && $height && $fps;
            print "$id $width $height $fps\n";
            last;
        }
    '
}

function audiodetect {
    local file="$1"

    # Convert AAC audio to AC3, returns "-c:[track number] ac3" for every AAC track
    ffmpeg -i "file:$file" -c:none /dev/null 2>&1 | perl -e '
        use strict;
        use warnings;
        my @result= ();
        while (<>) {
            next unless /^\s*Stream #0:(\d+)(?:\[0x\w+\])?(?:\(\w+\))?: Audio:\s+(\w+)/;
            my ($stream, $format)= ($1, $2);
            push @result, "-c:$stream ac3" if $format=~ /^(?:aac|ms|mp2|pcm_\w+|opus)$/;
        }
        print join(" ", @result);
    '
}

function cleanFile {
    local file="$1"

    mkclean --remux "$file" "$file.clean"
    newLength=`du -k "$file.clean" | cut -f 1`

    # only rename file if result is larger than 100k (mkclean does not always return an error)
    test "$newLength" -gt 100 && mv "$file.clean" "$file"
}

function simpleEncode {
    inName="$1"

    if [ ! -f "$inName" ]; then
        echo "Input file '$inName' does not exist."
        exit
    fi

    shift
    videoOptions=(
        "-preset" "medium"
        "-tune" "film"
        "-b-pyramid" "normal"
        "-partitions" "p8x8,b8x8,i4x4"
        "$@"
    )

    outDir="`dirname "$inName"`/.out"
    outName="$outDir/`basename "$inName" ".mkv"`.mkv"
    test -d "$outDir" || mkdir -p "$outDir"

    filter=( )

    # detecting interlace
    interlaced=`ffmpeg -filter:v idet -frames:v 1000 -an -f rawvideo -y /dev/null -i "file:$inName" 2>&1 | perl -e '
        use strict;
        my $inter= 0;
        my $progress= 0;
        while (<>) {
            if ( /Multi frame .+ TFF:\s+(\d+)\s+BFF:\s+(\d+)\s+Progressive:\s+(\d+)\s+Undetermined:\s+(\d+)/ ) {
                $inter+= $1 + $2;
                $progress+= $3 + $4;
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

    audioOptions=( `audiodetect "$inName"` )

    # if there is no crf options, add -crf 20
    test "$crfFound" -eq 0 && videoOptions=( "${videoOptions[@]}" '-crf' '20' )

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
        ffmpeg -i "file:$inName"
        -f matroska
        -map 0 -map -0:v:1?
        -c copy -c:V libx264
        "${videoOptions[@]}"
        "${audioOptions[@]}"
        "file:$outName"
    )
#        -c:s copy -c:d copy -c:t copy

    echo "Running in 10s ${cmd[@]}"
    sleep 10s
    "${cmd[@]}"

    cleanFile "$outName"
}
