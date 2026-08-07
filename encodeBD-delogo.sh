#!/bin/bash

# Blu-ray encode that blanks out a station logo.
#
# The position is given in *source* pixels, as read off an unencoded frame -
# simpleEncode puts the delogo filter ahead of the crop, so autocrop does not
# shift the coordinates under it.
#
# To find the values, grab a frame and measure the logo in an image viewer:
#     ffmpeg -ss 600 -i "file:movie.mkv" -frames:v 1 frame.png
# Take a box a few pixels larger than the logo on every side, delogo
# interpolates from the surrounding edge.

logo="$1"
shift

if ! [[ "$logo" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]]; then
    echo "Usage: `basename "$0"` <x>:<y>:<width>:<height> <file.mkv> [ffmpeg options]"
    echo "Example: `basename "$0"` 1640:70:150:50 movie.mkv"
    exit 2
fi

realpath=`realpath "$0"`
"`dirname "$realpath"`/encodeBD.sh" "$@" -delogo "$logo"
