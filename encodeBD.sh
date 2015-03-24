#!/bin/bash

realpath=`realpath "$0"`
source "`dirname "$realpath"`/functions.sh"

simpleEncode "$@" -crf 25
