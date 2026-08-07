#!/bin/bash

# Blu-ray encode with denoising, for grainy sources: film grain is close to
# random noise, so x264 spends a lot of bitrate on it and the output can end up
# larger than the input. hqdn3d removes enough of it to keep the size sane.
# The filter is appended to the detected crop, it does not replace it.

realpath=`realpath "$0"`
"`dirname "$realpath"`/encodeBD.sh" "$@" -vf "hqdn3d=1.5:1.5:6:6"
