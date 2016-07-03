#!/usr/bin/perl

use strict;
use warnings;

##############################################################
## Builds a PNG from given captions (default font size is 72)
## usage: caption2Png.pl <caption> <out file> [<font size>]
##############################################################
my $caption= $ARGV[0];
my $file= $ARGV[1];
my $fontsize= $ARGV[2] || 72;

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
my ( $font_color, $shadow_color )= ( 'white', 'black' );

my $style= {};
my @styles=();

my $strokewidth= $fontsize > 60 ? 2 : ($fontsize > 40 ? 2 : 0);
my $stroke= $strokewidth ? $shadow_color : 'none';

my @cmd= (
    'convert',
    '-background', 'none',
    '-gravity', 'center',
    '-pointsize', $fontsize,
    '-fill', $font_color,
    ( $strokewidth ? (
        '-stroke', 'black',
        '-strokewidth', $strokewidth,
    ) : ()),
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
    push @cmd, '-font', $font, '-stroke', $stroke, '-strokewidth', $strokewidth, 'label:' . $part, '+append';
}
push @cmd, ')', '-append';
push @cmd, '(', '+clone', '-background', $shadow_color, '-shadow', '100x3+0+0', '-channel', 'A', '-level', '0,50%', '+channel', ')', '+swap', '+repage', '-gravity', 'center', '-composite';
push @cmd, $file;

system @cmd;

my $dimensions= `file "$file"`;

print "$1 x $2\n" if $dimensions=~ /(\d+) ?x ?(\d+)/;

