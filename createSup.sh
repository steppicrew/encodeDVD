#!/bin/bash

# inspired by https://code.google.com/archive/p/srt2vob/

if [ $# -lt 2 ]
then
 echo
 echo Usage: 2dsub filename.srt format [fontsize]
 echo Example: 2dsub mymovie.srt 1080p 72
 echo
 exit 1
fi

caption2Png="`dirname "$0"`/caption2Png.pl"

forced_fontsize="$3"

case "$2" in
    "720p" )
        ysize=720
        xsize=1280
        fontsize=48
        ;;
    "1080p" )
        ysize=1080
        xsize=1920
        fontsize=72
        ;;
    "576p" )
        ysize=576
        xsize=720
        fontsize=27
        ;;
    "480p" )
        ysize=480
        xsize=640
        fontsize=26
        ;;
    "360p" )
        ysize=320
        xsize=240
        fontsize=9
        ;;
    "240p" )
        ysize=240
        xsize=352
        fontsize=13
        ;;
    * )
        echo "Unsupported Format \"$2\". Supported formats are: 1080p, 720p, 567p, 480p, 320p, 240p"
        exit 1
        ;;
esac

test "$forced_fontsize" && fontsize="$forced_fontsize"

dname="/tmp/2dsub"$RANDOM"/"
echo "Creating temporary directory $dname"
mkdir $dname

cleanup() {
    echo "Removing temporary directory $dname"
    rm -rf $dname
}
trap cleanup 0

tr -d '\r' < "$1" > "$dname"tmpsrttmp.tmp
echo >> "$dname"tmpsrttmp.tmp
echo >> "$dname"tmpsrttmp.tmp
mv "$dname"tmpsrttmp.tmp "$1"

filename=`echo "$1" | sed 's/.srt//'`
a=0
state=0
caption=""
firstTC=""
lastTC=""
frate=24

maxwidth=0
largesubs=""

while read line
do
    if [ "$state" = "0" ] && [ "$line" != "" ]
    then
        state=1
        continue
    fi
    if [ "$state" = "1" ]
    then
        timeline=$line
        state=2
        continue
    fi
    if [ "$state" = "2" ] && [ "$line" != "" ]
    then
        if [ "$caption" != "" ]
        then
        caption=$caption"\n"$line
        else
        caption=$line
        fi
        continue
    fi
    if [ "$state" = "2" ] && [ "$line" = "" ]
    then
        state=0
        str=""
        a=$(($a+1))
        if [ $a -lt 10 ] 
        then
            str="0"
        fi
        if [ $a -lt 100 ] 
        then
            str=$str"0"
        fi
        if [ $a -lt 1000 ] 
        then
            str=$str"0"
        fi
        str=$str$a
        start=`echo $timeline | sed 's/ --.*//' | sed 's/,.*//'`
        end=`echo $timeline | sed 's/.*--> //' | sed 's/,.*//'`
        ffstart=`echo $timeline | sed 's/ --.*//' | sed 's/.*,//'`
        ffend=`echo $timeline | sed 's/.*--> //' | sed 's/.*,//'`
        ffstart=`echo "scale=2; $ffstart / 1000 * $frate" | bc | xargs printf "%1.0f"`
        ffend=`echo "scale=2; $ffend / 1000 * $frate" | bc | xargs printf "%1.0f"`
        sz=` "$caption2Png" "$caption" "${dname}${filename}_${str}.png" $fontsize`
        width=`echo $sz | sed 's/ x.*//'`
        height=`echo $sz | sed 's/.*x //'`
        if [ "$width" -gt "$maxwidth" ]
        then
            maxwidth="$width"
        fi
        if [ "$width" -gt "$xsize" ]
        then
            echo "SubTitle $a is wider than screen ($width > $xsize)"
            echo "Choose another font size (current is $fontsize)"
            largesubs="$largesubs $a"
        fi
        x=`echo $xsize / 2 - $width / 2 | bc`
        y=$((ysize-40-$height))
        if [ $ffend -lt 10 ]
        then
            ffend="0"$ffend
        fi
        if [ $ffstart -lt 10 ]
        then
            ffstart="0"$ffstart
        fi
        echo "<Event InTC="\"$start":$ffstart"\"" OutTC="\"$end":$ffend"\"" Forced=\"False\">" >> "$dname"tmp.xml
        echo "<Graphic Width=\"$width\" Height=\"$height\" X=\"$x\" Y=\"$y\">"$filename""_"$str.png</Graphic>" >> "$dname"tmp.xml
        echo "</Event>" >> "$dname"tmp.xml
        lastTC=$end:$ffend
        echo "Added subtitle number: "$a
        if [ "$firstTC" = "" ]
        then
            firstTC=$start:$ffstart
        fi
        caption=""
    fi
done < "$1"

if [ "$maxwidth" -gt "$xsize" ]
then
    echo "Subtitles's max width was $maxwidth (screen width: $xsize)."
    echo "Try using font size $(( $fontsize * $xsize / $maxwidth ))"
    echo "Folowing subtitles have exeeded the max width:$largesubs"
    exit
fi

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > "$dname"sub.xml
echo "<BDN Version=\"0.93\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"BD-03-006-0093b BDN File Format.xsd\">" >> "$dname"sub.xml
echo "<Description>" >> "$dname"sub.xml
echo "<Name Title=\""$filename"\" Content=\"\"/>" >> "$dname"sub.xml
echo "<Language Code=\"ell\"/>" >> "$dname"sub.xml
echo "<Format VideoFormat=\"$2\" FrameRate=\"$frate\" DropFrame=\"False\"/>" >> "$dname"sub.xml
echo "<Events Type=\"Graphic\" FirstEventInTC=\"$firstTC\" LastEventOutTC=\"$lastTC\" NumberofEvents=\"$a\"/>" >> "$dname"sub.xml
echo "</Description>" >> "$dname"sub.xml
echo "<Events>" >> "$dname"sub.xml
cat "$dname"tmp.xml >> "$dname"sub.xml
echo "</Events>" >> "$dname"sub.xml
echo "</BDN>" >> "$dname"sub.xml
rm "$dname"tmp.xml

bdsup2sub "$dname"sub.xml -o "$filename".sup
