package Movies::Organizer;

# ABSTRACT: Organize your movies using imdb

=head1 SYNOPSIS

    movies_organizer -h
    movies_organizer --from /movies/to/rename --to /movies_well_named

=cut

use strict;
use warnings;

# VERSION

use Moo;
use MooX::Options;
use File::Path 'make_path';
use Carp;
use Data::Dumper;
use File::Glob ':globally';
use File::Spec;
use File::Copy;
use Term::ReadLine;
use IMDB::Film;
use 5.010;

option 'from' => (
    doc => 'Source directory to organize',
    is  => 'ro',
    isa => sub {
        my ($dest) = @_;
        croak "Source directory is missing !" unless -d $dest;
    },
    required => 1,
    format   => 's',
);

option 'to' => (
    doc => 'Destination of the organized movies',
    is  => 'ro',
    isa => sub {
        my ($dest) = @_;
        if ( !-d $dest ) {
            make_path( $dest, { error => \my $err } );
            if (@$err) {
                for my $diag (@$err) {
                    my ( $file, $message ) = %$diag;
                    croak "Error : $message\n";
                }
            }
        }
    },
    required => 1,
    format   => 's',
);

option 'min_size' => (
    is      => 'ro',
    default => sub { 100 * 1024**2 },
    doc     => 'minimum size of file to handle it has movies',
    format  => 'i',
);

has '_filter_words' => (
    is      => 'ro',
    default => sub {
        [
            qw/
              french
              english
              x264
              720p
              1080p
              bluray
              avi
              mkv
              divx
              bdrip
              xvid
              brrip
              ac3
              multi
              truefrench
              dts
              hdma
              hdtv
              hdrip
              m2ts
              /
        ];
    },
);

=method find_movies

pass thought 'from' directory, and get all movies files. It will take file bigger than 'min_size'

=cut

sub find_movies {
    my ($self) = @_;

    my @dir_to_scan = ( $self->from );
    my @movies;
    while ( my $dir = shift @dir_to_scan ) {
        $dir =~ s/ /\\ /g;
        while ( my $cur = glob "$dir/*" ) {
            push( @dir_to_scan, $cur ) and next if -d $cur;
            push @movies, $cur if -s $cur >= $self->min_size;
        }
    }
    return @movies;
}

=method filter_title

Extract words from the file name, filter any common bad one, and return filtered title.

=cut

sub filter_title {
    my ( $self, $file ) = @_;
    my ( undef, undef, $movie ) = File::Spec->splitpath($file);
    my @words_ok;
  SKIP_WORD: for my $word ( split( /\W+/x, $movie ) ) {
        for my $filter ( @{ $self->_filter_words } ) {
            next SKIP_WORD if $word =~ m/^$filter$/ix;
        }
        push @words_ok, $word;
    }
    return join( ' ', @words_ok );
}

=method fetch_movie

Return IMDB search of your movie

=cut

sub fetch_movie {
    my ( $self, $search ) = @_;

    return IMDB::Film->new( crit => $search );
}

=method move_movie

move the movie to the destination with the right name, that wil ease your classment with XMDB tools type.

=cut

sub move_movie {
    my ( $self, %options ) = @_;
    my ( $term, $file, $imdb, $title, $season, $episode ) =
      @options{qw/term file imdb title season episode/};
    my ( undef, undef, $movie ) = File::Spec->splitpath($file);
    my ( $season_part, $episode_part );
    my $is_series = $imdb->kind =~ /series/;

    if ($is_series) {
        $season_part  = sprintf( "S%02d", $season );
        $episode_part = sprintf( "E%02d", $episode );
    }

    #extract ext
    my ($ext) = $movie =~ m/\.([^\.]+)$/x;
    $ext = "avi" unless defined $ext;

    #fix title space
    $title =~ s/\W+/ /gx;
    $title =~ s/^\s+|\s+$//gx;
    $title =~ s/\s+(\w)/.\u$1/gx;    #replace space by dot

    #create destination
    my $dest = File::Spec->catfile( $self->to, ucfirst( $imdb->kind ) );
    if ($is_series) {
        $dest = File::Spec->catfile( $dest, $title, $season_part );
    }
    make_path( $dest, { error => \my $err } );
    if (@$err) {
        for my $diag (@$err) {
            my ( undef, $message ) = %$diag;
            croak "Error : $message\n";
        }
    }

    #build final filename
    if ($is_series) {
        $ext = join( '.', $season_part . $episode_part, $ext );
    }
    else {
        $ext = join( '.', "(" . $imdb->year . ")", $ext );
    }
    my $fdest = File::Spec->catfile( $dest, join( '.', $title, $ext ) );

    say "Moving  : ";
    say "   From : ", $file;
    say "   To   : ", $fdest;

    exit unless $term->readline( 'Continue (Y/n) ? > ', 'y' ) eq 'y';

    move( $file, $fdest );
    croak "Error occur !" if -e $file || !-e $fdest;

    $file  =~ s/\.[^\.]+$/.srt/x;
    $fdest =~ s/\.[^\.]+$/.srt/x;

    if ( -e $file ) {

        say "Moving  : ";
        say "   From : ", $file;
        say "   To   : ", $fdest;

        exit unless $term->readline( 'Continue (Y/n) ? > ', 'y' ) eq 'y';

        move( $file, $fdest );
        croak "Error occur !" if -e $file || !-e $fdest;

    }
    return;
}

=method run

Run the tools, and rename properly your movies.

=cut

## no critic qw(Subroutines::ProhibitExcessComplexity)
sub run {
    my $self = shift;

    my $term = Term::ReadLine->new;
    my ( $imdb, $movie_title, $season, $episode );
    for my $movie ( $self->find_movies() ) {
        say "";
        say "Organize : $movie";
        my $another_episode;
        if (
               defined $imdb
            && $imdb->kind =~ /series/
            && $term->readline(
                "is it another episode of " . $movie_title . " ? (Y/n) > ",
                "y" ) eq "y"
          )
        {
            $another_episode = 1;
            say "";
        }
        else {
            $imdb = undef;
        }
        if ( !$another_episode ) {
            while ( !defined $imdb ) {
                my $imdb_search = $term->readline( "IMDB Search > ",
                    $self->filter_title($movie) );
                $imdb = $self->fetch_movie($imdb_search);
                $imdb = undef if !$imdb->status;
                if ($imdb) {
                    say "Movie    : ", $imdb->title;
                    say "Aka      : ", join( ', ', @{ $imdb->also_known_as } );
                    say "Kind     : ", $imdb->kind;
                    say "Year     : ", $imdb->year;
                    say "Plot     : ", $imdb->plot;
                    say "Directory: ",
                      join( ', ', map { $_->{name} } @{ $imdb->directors } );
                    say "Cast     : ",
                      join( ', ',
                        map { $_->{name} . "(" . $_->{role} . ")" }
                          @{ $imdb->cast } );
                    say "Genre    : ", join( ', ', @{ $imdb->genres } );
                    say "Duration : ", $imdb->duration;
                    say "Language : ", join( ', ', @{ $imdb->language } );
                    say "";
                    my $correct =
                      $term->readline( "Is it correct ? (Y/n) > ", "y" );
                    $imdb = undef unless $correct eq 'y';
                }
            }
            $movie_title = $imdb->title;
            my @movie_titles = ( $imdb->title, @{ $imdb->also_known_as } );
            if ( @movie_titles > 1 ) {
                my $choice;
                say "Select best title : ";
                for ( my $i = 1 ; $i <= @movie_titles ; $i++ ) {
                    say sprintf( "    %d) %s", $i, $movie_titles[ $i - 1 ] );
                }
                while ( !defined $choice ) {
                    $choice = $term->readline( " > ", 1 );
                    $choice = undef
                      if $choice =~ /\D/x
                      || $choice < 1
                      || $choice > @movie_titles;
                }
                $movie_title = $movie_titles[ $choice - 1 ];
                say "";
            }
        }
        if ( $imdb->kind =~ /series/ ) {
            my $ok = 0;
            while ( !$ok || !defined $season || !defined $episode ) {
                $ok++;
                $season  = $term->readline( "Season ? > ",  $season );
                $episode = $term->readline( "Episode ? > ", $episode );
                if (   $season =~ /\D/x
                    || $episode =~ /\D/x
                    || $season  eq ''
                    || $episode eq '' )
                {
                    say "Please, use only numeric values !";
                    say "";
                    $ok = 0;
                    next;
                }
                if (
                    !(
                        $term->readline(
                            "is it season "
                              . $season
                              . " episode "
                              . $episode
                              . " ? (Y/n) > ",
                            "y"
                        ) eq "y"
                    )
                  )
                {
                    $ok = 0;
                }
            }
        }

        $self->move_movie(
            term        => $term,
            movie       => $movie,
            imdb        => $imdb,
            movie_title => $movie_title,
            season      => $season,
            episode     => $episode
        );
        $episode++ if defined $episode;
    }

    return;
}

1;
