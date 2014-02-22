#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;
use Data::Dumper;

my $handbrake= "/usr/bin/HandBrakeCLI";
my $dvdDev= "/dev/sr0";
my $defaultFormat= "mkv";
my $defaultProfile= "Android High";
my $defaultVerbosity= 1;

my @languageOrder= ( "eng", "deu", "ger");

my @options= (
    {
        'option' => 'i',
        'synopsis' => '<dir|iso-file>',
        'comment' => 'dvd-directory or dvd-image file to read from',
        'default' => $dvdDev,
    },
    {
        'option' => 'o',
        'synopsis' => '<out-file name>',
        'comment' => 'file name to write to',
        'default' => '<infile with format extension>',
    },
    {
        'option' => 't',
        'synopsis' => '<number>',
        'comment' => 'title number to be ripped',
        'default' => '<title with longest duration>',
    },
    {
        'option' => 'a',
        'synopsis' => '[<title:]<number>[,[title:]number]',
        'comment' => 'audio channel to encode',
        'default' => '<english, german>',
    },
    {
        'option' => 's',
        'synopsis' => '<number>[,number]',
        'comment' => 'sub title to encode',
        'default' => '<english, german>',
    },
    {
        'option' => 'd',
        'comment' => 'deinterlace',
        'default' => 'no',
    },
    {
        'option' => 'f',
        'synopsis' => '<mp4|mkv>',
        'comment' => 'format to encode to',
        'default' => $defaultFormat,
    },
    {
        'option' => 'v',
        'synopsis' => '<number>',
        'comment' => 'verbosity',
        'default' => $defaultVerbosity,
    },
    {
        'option' => 'Z',
        'synopsis' => '<profile name>',
        'comment' => 'encoding profile name (see ' . $handbrake . ' --preset-list)',
        'default' => $defaultProfile,
    },
);

my %opts;
getopts(join('', map {$_->{option} . ($_->{synopsis} ? ':' : '')} @options), \%opts);

my @args= @ARGV;

my $inFile= $opts{i} || $dvdDev;

my $outFile= $opts{o};

my $format= $opts{f} || $defaultFormat;
my $ext= ".$format";

my $profile= $opts{Z} || $defaultProfile;

if (!$outFile) {
    if ($opts{i}) {
        $outFile= $inFile;
        $outFile=~ s/\....?$//;
        $outFile.= $ext;
    }
    else {
        $outFile= "video$ext";
    }
}

my $title= $opts{t};

my $verbosity= $opts{v} || $defaultVerbosity;

sub p {
    my $level= shift;
    return if $level > $verbosity;
    print @_, "\n";
}

sub HELP_MESSAGE {
    my $tabLength= 20;
    print "Usage:\n";
    for my $opt (@options) {
        my $o= "-$opt->{option} $opt->{synopsis}";
        $o.= " " x ($tabLength - length($o)) if length($o) < $tabLength;
        print "\t$o$opt->{comment}\n";
        print "\t" . " " x $tabLength . "default: $opt->{default}\n" if $opt->{default};
    }
    exit;
}

my %allTitles= ();
my $curTitle;
my $curSection;
open(my $fh, "-|", "$handbrake -i '$inFile' -t 0 2>&1") || die "Could not scan device $inFile";
while (<$fh>) {
    chomp;
    next unless /^\s*\+/;

    if (/^\+ title (\d+)\:/) {
        $curTitle= $allTitles{$1}= {};
        next;
    }
    if (/^  \+ (.+?)\:/) {
        $curSection= $curTitle->{$1}= [];
        my $remain= $';
        $remain=~ s/^\s*(.+)\s*$/$1/;
        push @{$curSection}, $remain if $remain;
        next;
    }
    if (/^    \+ /) {
        push @{$curSection}, $';
        next;
    }
}

if (!$title) {
    my $maxDuration= '';
    p 1, "Found titles:";
    for my $t (sort keys %allTitles) {
        my $dur= $allTitles{$t}{duration}[0];
        my $chaps= $allTitles{$t}{chapters};
        p 1, "  Title $t: " . ($#{$chaps} + 1) . " chapters, $dur duration";
        if ($dur gt $maxDuration) {
            $title= $t;
            $maxDuration= $dur;
        }
    }
}

p 0, "Selected title: $title";

$curTitle= $allTitles{$title};

if (!$curTitle) {
    print "Title $title not found!\n";
    p 1, "Found titles:";
    for my $t (sort keys %allTitles) {
        my $dur= $allTitles{$t}{duration}[0];
        my $chaps= $allTitles{$t}{chapters};
        p 1, "  Title $t: " . ($#{$chaps} + 1) . " chapters, $dur duration";
    }
    exit;
}

my @cmd= ( $handbrake, "--preset", $profile, "--input", $inFile, "--output", $outFile, "--format", $format, "--title", $title, "--markers", "--decomb", "--optimize" );

my $audio= $opts{a};

if ($curTitle->{"audio tracks"} || $audio) {
    my @langs= ();
    my @names= ();
    my @encoders= ();
    if ($audio) {
        for my $a (split /\,/, $audio) {
            my @parts= split /\:/, $a;
            if ($#parts == 0) {
                @parts= ('Unknown', $parts[0]);
            }
            push @langs, $parts[1];
            push @names, $parts[0];
            push @encoders, 'copy';
        }
    }
    else {
        my $ats= {};

        for my $at (@{$curTitle->{"audio tracks"}}) {
            my ($num, $name, $lang, $bps)= ($1, $2, $3, $5 || 0) if $at=~ /^(\d+)\,\s+(\S+?)\s+.+\s+\(iso639\-2\: (...)\)(.+?(\d+)bps)?/;
#            next if $ats->{$lang} && $ats->{$lang}{bps} > $bps;

            $ats->{$lang}= {'num' => [], 'name' => [], 'encoder' => []} if !$ats->{$lang};

            push @{$ats->{$lang}{num}}, $num;
            push @{$ats->{$lang}{name}}, $name || $lang;
            push @{$ats->{$lang}{encoder}}, 'copy';

#            $ats->{$lang}= {'num' => $num, 'name' => $name || $lang, 'bps' => $bps};
        }
        for my $lang (@languageOrder) {
            next unless $ats->{$lang};
            push @langs, join(',', @{$ats->{$lang}{num}});
            push @names, join(',', @{$ats->{$lang}{name}});
            push @encoders, join(',', @{$ats->{$lang}{encoder}});
            p 1, "Found audio $lang (" . join(', ', @{$ats->{$lang}{num}}) . ")";
        }
    }
    if (@langs) {
        push @cmd, "--audio", join(',', @langs);
        push @cmd, "--aname", join(',', @names);
        push @cmd, "--aencoder", join(',', @encoders);
#        push @cmd, "--aencoder", join(',', @encoders);
#        push @cmd, "--audio-fallback", "faac";
    }
}

my $subtitles= $opts{s};

if ($curTitle->{"subtitle tracks"} || $subtitles) {
    my @langs= ();
    if ($subtitles) {
        @langs= split /\,/, $subtitles
    }
    else {
        my $sts= {};

        for my $st (@{$curTitle->{"subtitle tracks"}}) {
            my ($num, $name, $lang)= ($1, $2, $3) if $st=~ /^(\d+)\,\s+(.+?)\s+\(iso639\-2\: (...)\)/;
            p 0, "Duplicate subtitle $lang ($num)" if $sts->{$lang};

            $sts->{$lang}= {'num' => [], 'name' => [],} if !$sts->{$lang};

            push @{$sts->{$lang}{num}}, $num;
            push @{$sts->{$lang}{name}}, $name || $lang;
        }
        for my $lang (@languageOrder) {
            next unless $sts->{$lang};
            push @langs, join(',', @{$sts->{$lang}{num}});
            p 1, "Found subtitle $lang (" . join(', ', @{$sts->{$lang}{num}}) . ")";
        }
    }
    if (@langs) {
        push @cmd, "--subtitle", join(',', @langs)
    }
}

push @args, "--deinterlace" if $opts{d};

push @cmd, @args;

p 0;
p 0, join(" ", @cmd);
p 0;
sleep 5;

system @cmd;
