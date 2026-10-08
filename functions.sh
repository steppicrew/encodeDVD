
export LANG="C"

function cropdetect {
    local file="$1"
    # sample 15 points between 10% and 85% of the running time: the crop is the
    # union of what is visible, so more samples can only sharpen the result
    local length=`ffmpeg -i "file:$file" -c:none /dev/null 2>&1 | perl -ne '
        use strict;
        use warnings;
        if (/Duration:\s+(\d+):(\d+):(\d+\.\d+)/) {
            my $d= $1 * 3_600 + $2 * 60 + $3;
            print int($d * $_ / 20) . " " for (2..16);
        }
    '`
    local start
    for start in $length; do
        ffmpeg -ss $start -i "file:$file" -t 1 -filter:V cropdetect -f null - 2>&1
    done | perl -e '
        use strict;
        use warnings;

        my $maxWidth     = 1920;
        my $minArea      = 0.5; # ignore samples smaller than this share of the largest
        my $minAsymmetry = 16;  # opposite bars closer than this count as symmetric

        my @boxes= ();
        my ( $frameWidth, $frameHeight );
        while (<>) {
            # the same stderr carries the probe header, take the frame size from it
            ( $frameWidth, $frameHeight )= ( $1, $2 )
                if !$frameWidth && /^\s*Stream #\d+:\d+.*: Video:.*?\D(\d{2,5})x(\d{2,5})\b/;
            next unless /Parsed_cropdetect.+crop=(\d+):(\d+):(\d+):(\d+)/;
            # store as edges: left, top, right, bottom
            push @boxes, [ $3, $4, $3 + $1, $4 + $2 ];
        }

        unless ( @boxes ) {
            print STDERR "cropdetect: no crop candidates found\n";
            exit 1;
        }

        # Drop samples that are a small fraction of the largest box. cropdetect
        # reports the *visible* area, so a dark scene yields a tiny box that says
        # nothing about where the black bars are.
        my $maxArea= 0;
        for my $b (@boxes) {
            my $a= ($b->[2] - $b->[0]) * ($b->[3] - $b->[1]);
            $maxArea= $a if $a > $maxArea;
        }
        my @kept= grep { ($_->[2] - $_->[0]) * ($_->[3] - $_->[1]) >= $maxArea * $minArea } @boxes;
        @kept= @boxes unless @kept;

        # Union of the remaining boxes: content seen in any sample must be kept.
        my @edge= ( $kept[0][0], $kept[0][1], $kept[0][2], $kept[0][3] );
        for my $b (@kept) {
            $edge[0]= $b->[0] if $b->[0] < $edge[0];   # left   -> min
            $edge[1]= $b->[1] if $b->[1] < $edge[1];   # top    -> min
            $edge[2]= $b->[2] if $b->[2] > $edge[2];   # right  -> max
            $edge[3]= $b->[3] if $b->[3] > $edge[3];   # bottom -> max
        }

        # Letterbox and pillarbox bars are cut symmetrically, so opposite bars
        # should be the same size give or take a couple of pixels. A station
        # logo sitting in a black bar breaks that: it lights up in some scenes,
        # pushes that one edge out, and leaves the opposite bar untouched. When
        # the two bars on an axis differ by a wide margin, trust the larger one
        # and mirror it - that is the bar the overlay did not reach.
        #
        # This beats a frequency test because content that genuinely fills the
        # frame (a title card, an IMAX sequence) is symmetric, so it is left
        # alone no matter how few samples show it.
        if ( $frameWidth && $frameHeight ) {
            my @axes= (
                # name, near edge index, far edge index, frame size
                [ "top/bottom", 1, 3, $frameHeight ],
                [ "left/right", 0, 2, $frameWidth  ],
            );
            for my $axis (@axes) {
                my ( $name, $near, $far, $size )= @$axis;
                my $nearBar= $edge[$near];
                my $farBar=  $size - $edge[$far];
                next if abs( $nearBar - $farBar ) < $minAsymmetry;

                my $bar= $nearBar > $farBar ? $nearBar : $farBar;
                # never mirror a bar into more than a third of the frame
                next if $bar * 3 > $size;

                printf STDERR "cropdetect: %s bars differ (%d vs %d), which usually means a "
                    . "logo or overlay sits in the smaller one; using %d for both\n",
                    $name, $nearBar, $farBar, $bar;
                $edge[$near]= $bar;
                $edge[$far]=  $size - $bar;
            }
        }

        # round outwards to even numbers, libx264 needs mod-2 dimensions
        $edge[0]-- if $edge[0] % 2;
        $edge[1]-- if $edge[1] % 2;
        $edge[2]++ if $edge[2] % 2;
        $edge[3]++ if $edge[3] % 2;

        my $left=   $edge[0];
        my $top=    $edge[1];
        my $width=  $edge[2] - $edge[0];
        my $height= $edge[3] - $edge[1];

        unless ( $width > 0 && $height > 0 ) {
            print STDERR "cropdetect: computed an empty crop\n";
            exit 1;
        }

        # Sanity check: cropping away more than a quarter of either dimension is
        # more likely a sampling accident than a real letterbox.
        if ( $left > $width / 3 || $top > $height / 3 ) {
            print STDERR "cropdetect: detected crop=$width:$height:$left:$top removes an "
                . "implausible amount of the frame; pass -vf crop=... explicitly\n";
            exit 1;
        }

        print "crop=$width:$height:$left:$top";
        print "," if $width > $maxWidth;
        print "scale=$maxWidth:-2" if $width > $maxWidth;
    '
}

# extracts attachments from infile and add them to outfile
function copyAttachments {
    local infile="$1"
    local outfile="$2"

    perl -e '
        use strict;
        use warnings;
        use JSON qw/ decode_json /;
        use Data::Dumper;
        my $inFile= <>;
        my $outFile= <>;
        chomp $inFile;
        chomp $outFile;
        my $newOutFile= "$outFile.attachments.mkv";
        my $qInFile= $inFile;
        $qInFile=~ s/([\\"\$])/\\$1/g;
        my $prefix= $$;
        my $json= `mkvmerge --identify "$inFile" --identification-format json`;
        my $data= decode_json($json);

        exit unless $data->{attachments} && @{$data->{attachments}};

        my @cmdExtract= ( "mkvextract", $inFile, "attachments" );
        my @attachments= ();
        my @parameters= ();
        my @files= ();
        my $id= 0;
        foreach my $attachment (@{$data->{attachments}}) {
            my $filename= "$prefix-$id";
            push @cmdExtract, $attachment->{id} . ":" . $filename;
            push @attachments, "-attach", $filename;
            push @parameters, "-metadata:s:t:$id", "mimetype=" . $attachment->{content_type}, "-metadata:s:t:$id", "filename=" . $attachment->{file_name};
            push @files, $filename;
            $id++;
        }
        system @cmdExtract;
        system "ffmpeg", "-i", $outFile, "-map", "0", @attachments, "-c", "copy", @parameters, $newOutFile;
        my $oldSize= -s $outFile;
        my $newSize= -s $newOutFile;
        $oldSize < $newSize ? system("mv", $newOutFile, $outFile) : system("rm", $newOutFile);
        unlink @files;
    ' << EOT
$infile
$outfile
EOT
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

function pcmdetect {
    local file="$1"

    # Lossless LPCM -> FLAC, returns "-c:a:[audio index] flac" for every integer
    # PCM track. The index counts audio streams only, so it still matches once
    # cover art is left out of the mapping. Float PCM is skipped, FLAC cannot
    # hold it losslessly.
    ffmpeg -i "file:$file" -c:none /dev/null 2>&1 | perl -e '
        use strict;
        use warnings;
        my @result= ();
        my $audio= 0;
        while (<>) {
            next unless /^\s*Stream #0:(\d+)(?:\[0x\w+\])?(?:\(\w+\))?: Audio:\s+(\w+)/;
            my ($stream, $format)= ($1, $2);
            if ($format=~ /^pcm_(?:[su](?:8|16|24)(?:[lb]e)?|dvd|bluray)$/) {
                print STDERR "pcmdetect: audio track $audio (stream #0:$stream, $format) -> flac\n";
                push @result, "-c:a:$audio", "flac", "-compression_level:a:$audio", "8";
            }
            $audio++;
        }
        print join(" ", @result);
    '
}

function cleanFile {
    local file="$1"

    mkclean --remux "$file" "$file.clean"

    if [ ! -s "$file.clean" ]; then
        echo "mkclean produced no output, keeping '$file' as it is." >&2
        rm -f "$file.clean"
        return 1
    fi

    local newLength=`du -k "$file.clean" | cut -f 1`

    # only rename file if result is larger than 100k (mkclean does not always return an error)
    if [ "$newLength" -gt 100 ]; then
        mv "$file.clean" "$file"
    else
        echo "mkclean output was suspiciously small (${newLength}k), keeping '$file' as it is." >&2
        rm -f "$file.clean"
        return 1
    fi
}

function videoEnd {
    local file="$1"

    # Prints the last video timestamp in seconds. Only the final minute of the
    # container is read; in a truncated file the seek lands on the last video
    # keyframe instead, which is exactly where the video ends.
    local duration=`ffprobe -v error -show_entries format=duration -of csv=p=0 "file:$file"`
    [[ "$duration" =~ ^[0-9.]+$ ]] || return 1
    local start=`perl -e 'printf "%.3f", $ARGV[0] > 60 ? $ARGV[0] - 60 : 0' "$duration"`

    ffprobe -v error -read_intervals "$start%" -select_streams V:0 \
        -show_entries packet=pts_time -of csv=p=0 "file:$file" | perl -ne '
        use strict;
        use warnings;
        our $max;
        $max= $1 if /^([0-9.]+)/ && (!defined $max || $1 > $max);
        END { printf "%.3f", $max if defined $max; }
    '
}

function simpleEncode {
    local inName="$1"

    if [ ! -f "$inName" ]; then
        echo "Input file '$inName' does not exist." >&2
        return 1
    fi

    shift
    local videoOptions=(
        "-preset" "medium"
        "-tune" "film"
        "-b-pyramid" "normal"
        "-partitions" "p8x8,b8x8,i4x4"
        "$@"
    )

    local outDir="`dirname "$inName"`/.out"
    # not local: encodeDvd.sh's optional remux step reads $outName after the call
    outName="$outDir/`basename "$inName" ".mkv"`.mkv"
    test -d "$outDir" || mkdir -p "$outDir"

    # detecting interlace
    local interlaced=`ffmpeg -filter:v idet -frames:v 1000 -an -f rawvideo -y /dev/null -i "file:$inName" 2>&1 | perl -e '
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

    # extract filter and look for some options (-crf, -delogo, -noflac, -bw)
    local crfFound=0
    local flac=1
    local bw=0
    local filter=""
    local delogo=""
    local newOptions=( )
    local lastOption=""
    local o
    for o in "${videoOptions[@]}"; do
        [ "$o" = '-crf' ]   && crfFound=1
        [ "$o" = '-noflac' ] && flac=0
        [ "$o" = '-bw' ]     && bw=1

        if [ "$lastOption" = "-vf" ]; then
            filter="$o"
        fi
        if [ "$lastOption" = "-delogo" ]; then
            delogo="$o"
        fi

        # skip '-vf'/'-delogo' and their values and '-noflac'/'-bw', they are not ffmpeg options here
        if [ "$o" != '-vf' -a "$lastOption" != '-vf' \
          -a "$o" != '-delogo' -a "$lastOption" != '-delogo' \
          -a "$o" != '-noflac' -a "$o" != '-bw' ]; then
            newOptions=( "${newOptions[@]}" "$o" )
        fi
        lastOption="$o"
    done
    videoOptions=( "${newOptions[@]}" )

    # -delogo takes "x:y:w:h" in *source* coordinates. It is kept aside until the
    # whole chain is assembled, because it has to run before the crop: cropping
    # shifts the frame under it, and it would blur a band of picture instead of
    # the logo.
    if [ "$delogo" ]; then
        if [[ "$delogo" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]]; then
            local dx dy dw dh
            IFS=: read -r dx dy dw dh <<< "$delogo"
            delogo="delogo=x=$dx:y=$dy:w=$dw:h=$dh"
        else
            echo "-delogo expects <x>:<y>:<width>:<height> in source pixels, got '$delogo'." >&2
            return 1
        fi
    fi

    # Audio is deliberately left untouched here: audiodetect's AAC/PCM -> AC3
    # conversion is lossy-to-lossy, so run convertAudio.sh separately when wanted.
#    audioOptions=( `audiodetect "$inName"` )
    # LPCM -> FLAC is the exception: it is lossless and only saves space, so it
    # is on by default; -noflac keeps LPCM for players that cannot play FLAC.
    local audioOptions=( )
    if [ "$flac" -eq 1 ]; then
        audioOptions=( `pcmdetect "$inName"` )
    fi

    # if there is no crf options, add -crf 20
    test "$crfFound" -eq 0 && videoOptions=( "${videoOptions[@]}" '-crf' '20' )

    # Black and white: neutralise the chroma planes. The picture lives in luma
    # alone, so chroma only carries noise and tint that x264 would spend bits
    # on. Stays yuv420p on purpose - format=gray ends up as full-range yuvj420p
    # (bigger, and it shifts levels), and true 4:0:0 is poorly supported by
    # hardware players.
    if [ "$bw" -eq 1 ]; then
        test "$filter" && filter=",$filter"
        filter="hue=s=0${filter}"
    fi

    # if no crop is given, try detecting and prepend
    if [[ "$filter" != *crop=* ]]; then
        echo "Detecting crop...."
        local crop
        if ! crop="`cropdetect "$inName"`"; then
            echo "Crop detection was ambiguous: the samples do not agree." >&2
            echo "Candidates (width:height:left:top): $crop" >&2
            echo "Pick one and re-run with: -vf crop=<width>:<height>:<left>:<top>" >&2
            return 1
        fi
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

    # delogo goes in front of everything: its coordinates are source pixels
    if [ "$delogo" ]; then
        test "$filter" && filter=",$filter"
        filter="${delogo}${filter}"
    fi

    # append filter if needed
    if [ "$filter" ]; then
        videoOptions=( "${videoOptions[@]}" '-filter:V:0' "$filter" )
    fi

    if [ -e "$outName" ]; then
        echo "Output file '$outName' already exists, refusing to overwrite it." >&2
        return 1
    fi

    # Subtitles come from a second demuxer of the same file. ffmpeg 9.0.1 sends
    # the video decoder EOF when a sparse subtitle track (e.g. forced subs with
    # a gap of an hour) goes quiet in the shared demuxer - the encode then ends
    # minutes into the film with exit code 0. A separate input is not affected.
    local cmd=(
        ffmpeg -n -i "file:$inName" -i "file:$inName"
        -f matroska
        -map 0:V:0 -map 0:a -map 1:s? -map 0:d? -map 0:t?
        -c:v libx264 -c:a copy -c:s copy -c:d copy -c:t copy
        "${videoOptions[@]}"
        "${audioOptions[@]}"
        "file:$outName"
    )
#        -c:s copy -c:d copy -c:t copy

    echo "Running: ${cmd[@]}"
    read -t 10 -p "Press Enter to start now, Ctrl-C to abort (starts automatically in 10s)... " || true
    echo
    if ! "${cmd[@]}"; then
        echo "ffmpeg failed, leaving '$outName' untouched." >&2
        return 1
    fi

    # ffmpeg can stop encoding early and still exit 0, so compare where the
    # video ends in the output with where it ends in the input
    local inEnd outEnd
    inEnd=`videoEnd "$inName"`
    outEnd=`videoEnd "$outName"`
    if [ -z "$inEnd" -o -z "$outEnd" ]; then
        echo "Could not determine the video length, skipping the truncation check." >&2
    elif perl -e 'exit($ARGV[1] < $ARGV[0] - 5 ? 0 : 1)' "$inEnd" "$outEnd"; then
        echo "Output video ends at ${outEnd}s but the input runs to ${inEnd}s - the encode is truncated." >&2
        echo "Delete '$outName' before re-encoding." >&2
        return 1
    fi

    copyAttachments "$inName" "$outName"

    cleanFile "$outName"
}
