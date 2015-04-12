#!/bin/bash

dir="`dirname "$1"`"

for file in "$dir/"*.mkv; do
    title=`basename "$file" .mkv`
    mkvpropedit "$file" --edit info --set "title=$title"
done
