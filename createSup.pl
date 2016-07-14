#!/usr/bin/perl

use strict;
use warnings;
use File::Temp qw/ tempdir /;

my $debug= 1;

my ( $fontSize, $srtFile, $movieFile );
my ( $langCode, $fontColor, $shadowColor )= ( 'eng', 'white', 'black' );

#my ( $stroke, $strokeWidth );

sub usage {
    print "Usage: $0 [options] <srt file> <movie file>\n";
    print "\toptions:\n";
    print "\t\t-l <lang>:\tsubtitle\'s language code (default: eng)\n";
    print "\t\t-f <font size>: font size to use (default: auto)\n";
    print "\tsrt file:\tfile name of SRT file\n";
    print "\tmovie file:\tfile name of movie to extract dimensions from\n";
    die;
}

while ( my $p= shift @ARGV ) {
    if ( $p eq '-l' ) {
        $langCode= shift @ARGV;
        next;
    }
    if ( $p eq '-f' ) {
        $fontSize= shift @ARGV;
        next;
    }
    unless ( $srtFile ) {
        $srtFile= $p;
        next;
    }
    unless ( $movieFile ) {
        $movieFile= $p;
        next;
    }
    usage;
}

usage unless -f $srtFile && -f $movieFile;

##############################################################
## Builds a PNG from given captions (default font size is 72)
## usage: caption2Png.pl <caption> <out file> [<font size>]
##############################################################
sub buildPng {
    my $caption= shift;
    my $file= shift;

    my $buildFontArial= sub {
        my $style= shift;
        my $font= 'Arial';
        $font.= '-Bold' if $style->{b};
        $font.= '-Italic' if $style->{i};
        return $font;
    };

    my $buildFontDejavu= sub {
        my $style= shift;
        my $font= 'DejaVu-Sans';
        $font.= '-Book' unless $style->{b} || $style->{i};
        $font.= '-Bold' if $style->{b};
        $font.= '-Oblique' if $style->{i};
        return $font;
    };

    my $buildFontHelvetica= sub {
        my $style= shift;
        my $font= 'Helvetica';
        $font.= '-Bold' if $style->{b};
        $font.= '-Oblique' if $style->{i};
        return $font;
    };

    my $buildFont= $buildFontArial;
    my $style= {};
    my @styles=();

    my @cmd= (
        'convert',
        '-background', 'none',
        '-gravity', 'center',
        '-pointsize', $fontSize,
        '-fill', $fontColor,
#        ( $strokeWidth ? (
#            '-stroke', 'black',
#            '-strokewidth', $strokeWidth,
#        ) : ()),
        '(',
    );
    chomp $caption;
    my @parts= split /(<\/?\w>|\\n)/, $caption;
    foreach my $part (@parts) {
        if ( $part=~ /<(\/)?(\w)>/ ) {
            if ( $1 ) {
                $style= pop @styles;
                next;
            }
            push @styles, $style;
            $style= { %$style };
            $style->{b}= 1 if lc $2 eq 'b';
            $style->{i}= 1 if lc $2 eq 'i';
            next;
        }
        if ( $part eq '\\n' ) {
            push @cmd, ')', '-append', '(';
            next;
        }
        next unless $part;
        my $font= $buildFont->($style);
        $part=~ s/ /\\ /g;

        push @cmd, '(',
            '-stroke', $shadowColor, '-strokewidth', 5,
            '-font', $font, 'label:' . $part,
            '-stroke', 'none',
            '-font', $font, 'label:' . $part,
            '-layers', 'merge',# '+repage',
            ')'
        ;


#        push @cmd, '-font', $font, 'label:' . $part;
        push @cmd, '+append';
    }
    push @cmd, ')', '-append';
#    push @cmd, '(', '+clone';
#        push @cmd, '-alpha', 'extract', '-threshold', 0, '-negate', '-transparent', 'white'; # change all non-transparent colors to black
#        push @cmd, '-background', $shadowColor, '-shadow', '100x3+0+0', '-channel', 'A', '-level', '0,50%', '+channel';
#    push @cmd, ')', '+swap', '+repage', '-gravity', 'center', '-composite';
    push @cmd, $file;

    system @cmd;

    my $dimensions= `file "$file"`;

    return ( $1, $2 ) if $dimensions=~ /(\d+) ?x ?(\d+)/;
    die "Creating image '$file' filed";
}

my $ffmpegOut= `ffmpeg -i "$movieFile" -c:none /dev/null 2>&1`;

die 'Could not get movie\'s dimension' unless $ffmpegOut=~ /Stream #\d:\d\b.+ Video:.+ (\d+)x(\d+)\b.+, (\d+\.?\d*) fps/;

my ( $xSize, $ySize, $fps )= ( $1, $2, $3 );

# fixing width with DAR does not work (sutitles are moved to the right)
#if ( $ffmpegOut=~ /Stream #\d:\d\b.+ Video:.+ \d+x\d+ .+\bDAR (\d+):(\d+)\b/ ) {
#    my ( $xDar, $yDar )= ( $1, $2 );
#    $xSize= sprintf '%1.0f', $ySize / $2 * $1;
#    print "Correcting width to $xSize\n";
#}

my $format;
#$strokeWidth= 0;
if ( $xSize > 1900 ) {
    $format= '1080p';
    $ySize= 1080;
    $fontSize= 72 unless $fontSize;
#    $strokeWidth= 1;
}
elsif ( $xSize > 1250 ) {
    $format= '720p';
    $ySize= 720;
    $fontSize= 48 unless $fontSize;
#    $strokeWidth= 1;
}
elsif ( $xSize > 700 ) {
    $format= '576p';
    $ySize= 576;
    $fontSize= 27 unless $fontSize;
}
elsif ( $xSize > 620 ) {
    $format= '480p';
    $ySize= 480;
    $fontSize= 26 unless $fontSize;
}
elsif ( $xSize > 340 ) {
    $format= '240p';
    $ySize= 240;
    $fontSize= 13 unless $fontSize;
}
else {
    $format= '360p';
    $ySize= 360;
    $fontSize= 9 unless $fontSize;
}

print "Assuming screen dimensions ${xSize}x${ySize} \@$fps and font size $fontSize\n";

# $stroke= $strokeWidth ? $shadowColor : 'none';

my $dir= tempdir( 'createSub-XXXXX', TMPDIR => 1, CLEANUP => $debug );

open my $fh, '<', $srtFile;
chomp(my @lines = <$fh>);
close $fh;

my $outFile= $srtFile;
$outFile=~ s/\.srt//;
my $baseFileName= $outFile;
$outFile.= '.sup';
$baseFileName=~ s/^.*\///;

my ( $a, $state, $firstTC, $lastTC )= ( 0, 0, '', '' );
my ( $timeline );

my $maxWidth= 0;
my @largeSubs= ();
my @caption= ();
my ( $start, $end );

my @xml= ();

$fps= 24;

foreach my $line (@lines) {
    if ( $line && !$state ) {
        $state= 1;
        next;
    }
    if ( $state == 1 ) {
        die "Could not parse line '$line'\n" unless $line=~ /^(\d\d:\d\d:\d\d),(\d\d\d) \-\-> (\d\d:\d\d:\d\d),(\d\d\d)/;
        ( $start, $end )= ( sprintf('%s:%02.0f', $1, int($2 / 10) / 100 * $fps), sprintf('%s:%02.0f', $3, int($4 / 10) / 100 * $fps) ); 
        $state= 2;
        next;
    }
    if ( $state == 2 ) {
        if ( $line ) {
            push @caption, $line;
            next;
        }

        my $caption= join '\n', @caption;
        my $pngFile= sprintf("%s_%04d.png", $baseFileName, ++$a);
        my ( $width, $height )= buildPng $caption, $dir . '/' . $pngFile;

        $maxWidth= $width if $width > $maxWidth;
        if ( $width > $xSize ) {
            warn "subtitle $a is wider than screen ($width > $xSize)";
            push @largeSubs, $a;
        }
        my $x= int($xSize / 2 - $width / 2);
        my $y= $ySize - 40 - $height;

        push @xml, "<Event InTC=\"$start\" OutTC=\"$end\" Forced=\"False\">";
        push @xml, "<Graphic Width=\"$width\" Height=\"$height\" X=\"$x\" Y=\"$y\">$pngFile</Graphic>";
        push @xml, "</Event>";

        print "Added subtitle no $a $pngFile\n";

        $firstTC= $start unless $firstTC;
        $lastTC= $end;
        @caption= ();
        $state= 0;
    }
}

if ( $maxWidth > $xSize ) {
    warn "Subtitles's max width was $maxWidth (screen width: $xSize).";
    warn sprintf('Try using font size %d', int($fontSize * $xSize / $maxWidth));
    warn 'Folowing subtitles have exeeded the max width: ' . join(', ', @largeSubs);
    die;
}

my $xmlFile= "$dir/sub.xml";
open my $fn, '>', $xmlFile or die "Could not open file '$xmlFile'";
print $fn "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print $fn "<BDN Version=\"0.93\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"BD-03-006-0093b BDN File Format.xsd\">\n";
print $fn "<Description>\n";
print $fn "<Name Title=\"$baseFileName\" Content=\"\"/>\n";
print $fn "<Language Code=\"$langCode\"/>\n";
print $fn "<Format VideoFormat=\"$format\" FrameRate=\"$fps\" DropFrame=\"False\"/>\n";
print $fn "<Events Type=\"Graphic\" FirstEventInTC=\"$firstTC\" LastEventOutTC=\"$lastTC\" NumberofEvents=\"$a\"/>\n";
print $fn "</Description>\n";
print $fn "<Events>\n";
print $fn join("\n", @xml), "\n";
print $fn "</Events>\n";
print $fn "</BDN>\n";
close $fn;

system 'bdsup2sub', $xmlFile, '-o', $outFile;

