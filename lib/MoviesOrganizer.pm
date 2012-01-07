package MoviesOrganizer;

# ABSTRACT: Organize your movie using imdb

use strict;
use warnings;

# VERSION

use Moo;
use MooX::Options;
use File::Path 'make_path';
use Carp;
use 5.014;
use Data::Dumper;
use File::Glob ':globally';
use File::Spec;
use File::Copy;

option 'from' => (
    doc => 'Source directory to organize',
    is => 'ro',
    isa => sub {
        my ($dest) = @_;
        croak "Source directory is missing !" unless -d $dest;
    },
    required => 1,
    format => 's',
);

option 'to' => (
    doc => 'Destination of the organized movies',
    is => 'ro',
    isa => sub {
        my ($dest) = @_;
        if (! -d $dest) {
            make_path($dest, {error => \my $err});
            if (@$err) {
                for my $diag(@$err) {
                    my ($file, $message) = %$diag;
                    croak "Error : $message\n";
                }
            }
        }
    },
    required => 1,
    format => 's',
);

option 'min_size' => (
    is => 'ro',
    default => sub {100*1024**2},
    doc => 'minimum size of file to handle it has movies',
    format => 'i',
);

has '_filter_words' => (
    is => 'ro',
    default => sub {[qw/
            french
            x264
            720p
            1080p
            bluray
            avi
            mkv
            divx
            bdrip
            xvid
    /]},
);

sub find_movies {
    my ($self) = @_;

    my @dir_to_scan = ($self->from);
    my @movies;
    while(my $dir = shift @dir_to_scan) {
        $dir =~ s/ /\\ /g;
        while(my $cur = glob "$dir/*") {
            push(@dir_to_scan, $cur) and next if -d $cur;
            push @movies, $cur if -s $cur >= $self->min_size;
        }
    }
    return @movies;
}

sub filter_title {
    my ($self, $file) = @_;
    my ($volume, $dir, $movie) = File::Spec->splitpath($file);
    my @words_ok;
    for my $word(split(/\W+/, $movie)) {
        for my $filter(@{$self->_filter_words}) {
            $word =~ m/^$filter$/i
                and goto SKIP_WORD;
        }
        push @words_ok, $word;
        SKIP_WORD:
    }
    return join(' ',@words_ok);
}

sub fetch_movie {
    my ($self, $search) = @_;

    IMDB::Film->new(crit => $search);
}

sub move_movie {
    my ($self, $file, $imdb, $title) = @_;
    my ($volume, $dir, $movie) = File::Spec->splitpath($file);

    #extract ext
    my ($ext) = $movie =~ m/\.([^\.+])$/;
    $ext = "avi" unless defined $ext;

    #fix title space
    $title =~ s/\s(\w)/.\u$1/g; #replace space by dot

    #create destination
    my $dest = File::Spec->catfile($self->to, ucfirst($imdb->kind));
    make_path($dest, {error => \my $err});
    if (@$err) {
        for my $diag(@$err) {
            my ($file, $message) = %$diag;
            croak "Error : $message\n";
        }
    }

    #build final filename
    my $fdest = File::Spec->catfile($dest, join('.', $title, "(".$imdb->year.")", $ext));

    say "Moving  : ";
    say "   From : ", $file;
    say "   To   : ", $fdest;
    
    move($file, $fdest);
    croak "Error occur !" if -e $file || ! -e $fdest;
}

1;
