#!/bin/bash

infile="$1"

if test -z "$infile"; then
    echo "usage `basename "$1"` <infile> [<outfile>]"
    exit
fi

test "$outfile" || outfile="`dirname "$1"`/`basename "$1" ".mkv"`2.mkv"

ffmpeg -i "$infile" -map 0 -c copy "$outfile"

# swap audio channels
# ffmpeg -i "$infile" -map 0:0 -map 0:2 -map 0:1 -map 0:3 -vcodec copy -acodec copy -scodec copy "$outfile"
# alternativ:
# mkvpropedit -v "$outfile" -v --edit track:2 --set track-number=3 --edit track:3 --set track-number=2

# change default flag
# mkvpropedit -v "$outfile" -v --edit track:a1 --set flag-default=1 --edit track:a2 --set flag-default=0

# change aspect ratio (DVD 16:9)
# mkvpropedit "$oufile" --edit track:v1 --set pixel-width=720 --set pixel-height=576 --set display-width=1024 --set display-height=576


# convert srt-File to PGS
# in WINDOWS (or tsMuxeR 2.6.12+ supports italic on/off)
# if srt contains any utf-8 chars: open file in notepad and save unicode file
# open srt in tsMuxerGui, select "Demux", in Subtitle Tab select font size (28 for 720x520, 48 for 1280x720, 72 for 1920x1080)
# save meta file
# edit meta file and fix video's dimensions
# run 'tsMuxeR <meta file> <outdir>'
