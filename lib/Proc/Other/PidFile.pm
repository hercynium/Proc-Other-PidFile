package Proc::Other::PidFile;

use strict;
use warnings;

# Doing this 'cause all the alternatives on the cpan are made to
#  deal with the pid file for the *current* process and make
#  handling the pid files from *other* processes a PITA.
#
# This module will (hopefully):
#  * not create the pidfile unless you tell it to
#  * not populate the pidfile unless you tell it to
#  * actually have a method to return the fucking pid within
#     the pidfile (yes, the alternatives are issing this!)
#  * verify that the pid belongs to the program you specify
#  * get in the kitchen and make you a pie (not really)

our $VERSION = 0.001;

use Carp;
use autodie qw( :all );
use File::Temp qw( tempdir );
use File::Basename qw( basename );
use File::Spec::Functions qw( catfile tmpdir );


sub new {
    my ( $class, %args ) = @_;

    my $self = {
        dir  => undef,  # dir under which to locate pidfile
        file => undef,  # path under $dir to the pidfile
        prog => undef,  # program pidfile belongs to
        %args,
    };

    # DWIM if we're not root. I could prolly make this more portable...
    my $default_dir = -w '/var/run' ? '/var/run' : tmpdir();

    # I guess empty str or 0 are *technically* valid :-/
    $self->{dir} ||= $default_dir unless defined $self->{dir};

    # if the user didn't specify a progname, or specified undef or false...
    $self->{prog} ||= basename $0 unless exists $args{prog};

    # if a file was not specified, well, we need one no matter what...
    # ('' is not OK, and if they specified 0, fu*k 'em)
    if ( !$self->{file} ) {

        # generate the filename from the prog name...
        # if *that* is not set, give up.
        $self->{file}
            = $self->{prog}
            ? "$self->{prog}.pid"
            : croak( "Could not set PID filename! "
                . "Pass a valid value to either 'file' or 'prog'\n" );
    }

    $self->{fullpath} = catfile( $self->{dir}, $self->{file} );

    return bless $self, $class;
}


# Write the pidfile with the given pid. creates it if missing
#  and clobbers any existing pidfile.
#   return true on success
#   die on error
sub write {
    my ( $self, $pid ) = @_;

    my $pid_fh;  # oh, the things I do for good error messages :-/
    eval { open $pid_fh, '>', $self->{fullpath} };
    croak "Can't open '$self->{fullpath}' for writing: '$!'" if $@;

    return print $pid_fh $pid;
}


# Creates a new pidfile.
#   return true on success
#   die if the pidfile already exists, unless $clobber is true
#   die on any other failure
sub create {
    my ( $self, $pid, $clobber ) = @_;

    if ( !$clobber ) {
        croak "Can't create pidfile '$self->{fullpath}': already exists."
            if -x $self->{fullpath};
    }

    return $self->write( $pid );
}


# Updates an existing pidfile
#   return true on success
#   die if the pidfile does not exist, unless $autocreate is true
#   die on any other failure
sub update {
    my ( $self, $pid, $autocreate ) = @_;

    if ( !$autocreate ) {
        croak "Can't update pidfile '$self->{fullpath}': doesn't exist."
            unless -x $self->{fullpath};
    }

    return $self->write( $pid );
}


# Delete the pidfile
#   return true on success
#   return false if there is no pidfile
#   die if any other error
sub destroy {
    my ( $self ) = @_;

    $self->{fullpath} or return;

    -e $self->{fullpath} or return;

    return unlink $self->{fullpath}
        || croak "Can't unlink '$self->{fullpath}': $!";
}


# Synonym for destroy...
{
    no strict 'refs';
    *{"delete"} = \&destroy;
}


# Verify the pid is running and matches prog, if set.
#   return the pid if running
#   return false if not running
#   die if pid is not the expected proc && verify is true
#   die if pidfile is bad (does not exist, access denied, 
#    invalid format, etc)
sub running {
    my ( $self, %args ) = @_;

    my $verify = exists $args{verify} ? $args{verify} : $self->{verify};
    my $prog   = $args{prog}          ? $args{prog}   : $self->{prog};

    my $pid = $self->pid;

    return unless kill 0, $pid;
    return $self->_verify( $pid, $prog ) if $verify;
    return $pid;
}


# Verify that $pid is a running instance of $prog.
#   return $pid if true
#   return false if false
sub _verify {
    my ( $self, $pid, $prog ) = @_;

    croak "A pid must be specified.\n"           unless $pid;
    croak "Can't verify if 'prog' is not set.\n" unless $prog;

    # TODO: somehow check that $pid is a running instance of $prog

    return $pid if 1;
    return;
}


# Return the pid read from the file (should be an integer)
#   die if the file doesn't exist, is empty, unreadable,
#    or formatted wrong
sub pid {
    my ( $self ) = @_;

    # I'm just going to go with the standard, "single ASCII integer" format
    # even though my delusional brain tells me there are some other weird
    # formats used out there... I'll add support for those if anybody asks.

    my $pid_fh;  # oh, the things I do for good error messages :-/
    eval { open $pid_fh, '<', $self->{fullpath} };
    croak "Can't open '$self->{fullpath}' for reading: '$!'" if $@;

    my $pid_txt = do { local ( $/ ); <$pid_fh> };

    my ( $pid ) = $pid_txt =~ m/^ \s* (\d+) \s* $/msx;
    croak "Could not read valid pid from '$self->{fullpath}'\n"
        unless defined $pid;

    return $pid;
}


# the full path to the pidfile
sub path { return shift->{fullpath}; }


1;
__END__
