package WGDev;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.2.0';

use File::Spec ();
use Cwd        ();
use Carp qw(croak);

sub new {
    my ( $class, $root, $config ) = @_;
    my $self = bless {}, $class;
    if ( $config && -e $config ) {

        # file exists as is, save absolute path
        $self->{config_file} = $config = File::Spec->rel2abs($config);
    }
    if ($root) {
        $self->{root} = $root;
    }
    elsif ( $config && -e $config ) {
        my $config_dir = File::Spec->catpath(
            ( File::Spec->splitpath($config) )[ 0, 1 ] );
        $self->{root} = Cwd::realpath(
            File::Spec->catdir( $config_dir, File::Spec->updir ) );
    }
    else {
        my $dir = Cwd::getcwd();
        while (1) {
            if ( -e File::Spec->catfile( $dir, 'etc', 'WebGUI.conf.original' )
                )
            {
                $self->{root} = $dir;
                last;
            }
            my $parent = Cwd::realpath(
                File::Spec->catdir( $dir, File::Spec->updir ) );
            last
                if $dir eq $parent;
            $dir = $parent;
        }
    }
    if ( $self->{root} ) {
        if ( !$config ) {
            if ( opendir my $dh, File::Spec->catdir( $self->{root}, 'etc' ) )
            {
                my @configs = readdir $dh;
                closedir $dh
                    or croak "Unable to close directory handle: $!";
                @configs = grep {
                    /\Q.conf\E$/msx
                        && !/^(?:spectre|log)\Q.conf\E$/msx
                } @configs;
                if ( @configs == 1 ) {
                    $config = $configs[0];
                }
            }
        }
        if ($config) {
            $self->{config_file}
                ||= File::Spec->catfile( $self->{root}, 'etc', $config );
        }
        $self->{lib} = File::Spec->catdir( $self->{root}, 'lib' );
    }
    else {
        croak 'Unable to determine webgui root!';
    }

    $self->set_environment;

    return $self;
}

sub set_environment {
    my $self = shift;
    $ENV{WEBGUI_ROOT}   = $self->root;
    $ENV{WEBGUI_CONFIG} = $self->config_file;
    unshift @INC, $self->lib;
    $ENV{PERL5LIB} = $ENV{PERL5LIB}
        ? do {
        require Config;
        $self->lib . $Config::Config{path_sep} . $ENV{PERL5LIB};
        }
        : $self->lib;
    return 1;
}

sub root        { return shift->{root} }
sub config_file { return shift->{config_file} }
sub lib         { return shift->{lib} }

sub config {
    my $self = shift;
    croak 'no config file available'
        if !$self->{config_file};
    return $self->{config} ||= do {
        require Config::JSON;
        Config::JSON->new( $self->config_file );
    };
}

sub close_config {
    my $self = shift;
    delete $self->{config};

    # if we're closing the config, we probably want new sessions to pick up
    # changes to the file
    ## no critic (Modules::RequireExplicitInclusion)
    if ( WebGUI::Config->can('clearCache') ) {
        WebGUI::Config->clearCache;
    }
    return 1;
}

sub config_file_relative {
    my $self = shift;
    return $self->{config_file_relative} ||= do {
        my $config_dir
            = Cwd::realpath( File::Spec->catdir( $self->root, 'etc' ) );
        File::Spec->abs2rel( Cwd::realpath( $self->config_file ),
            $config_dir );
    };
}

sub db {
    my $self = shift;
    require WGDev::Database;
    return $self->{db} ||= WGDev::Database->new( $self->config );
}

sub session {
    my $self = shift;
    require WebGUI::Session;
    if ( $self->{session} ) {
        my $dbh = $self->{session}->db->dbh;

        # if the database handle died, close the session
        if ( !$dbh->ping ) {
            delete $self->{asset};
            ( delete $self->{session} )->close;
        }
    }
    return $self->{session} ||= do {
        my $session
            = WebGUI::Session->open( $self->root, $self->config_file_relative,
            undef, undef, $self->{session_id} );
        $self->{session_id} = $session->getId;
        $session;
    };
}

sub close_session {
    my $self = shift;
    if ( $self->{session} ) {    # if we have a cached session
        my $session = $self->session;  # get the session, recreating if needed
        $session->var->end;            # close the session
        $session->close;
        delete $self->{asset};
        delete $self->{session};
    }
    return 1;
}

sub asset {
    my $self = shift;
    require WGDev::Asset;
    return $self->{asset} ||= WGDev::Asset->new( $self->session );
}

sub version {
    my $self = shift;
    require WGDev::Version;
    return $self->{version} ||= WGDev::Version->new( $self->root );
}

sub wgd_config {
    my ( $self, @keys ) = @_;
    my $config = $self->{wgd_config};
    if ( !$config ) {
        for my $config_file ( '.wgdevcfg', $ENV{HOME} . '/.wgdevcfg' ) {
            if ( -e $config_file ) {
                open my $fh, '<', $config_file or next;
                my $content = do { local $/ = undef; <$fh> };
                close $fh or next;
                $self->{wgd_config} = $config = yaml_decode($content);
            }
        }
    }
    if ( !$config ) {
        return;
    }
    for my $key (@keys) {
        if ( !exists $config->{$key} ) {
            return;
        }
        $config = $config->{$key};
    }
    return $config;
}

sub my_config {    ## no critic (RequireArgUnpacking)
    my ($self)   = shift;
    my ($caller) = caller;
    return $self->wgd_config( $caller, @_ );
}

sub yaml_decode {
    _load_yaml_lib();
    goto &yaml_decode;
}

sub yaml_encode {
    _load_yaml_lib();
    goto &yaml_encode;
}

sub _load_yaml_lib {
    ## no critic (RequireFinalReturn ProhibitCascadingIfElse ProhibitNoWarnings)
    no warnings 'redefine';
    if ( eval { require YAML::XS } ) {
        *yaml_encode = \&YAML::XS::Dump;
        *yaml_decode = \&YAML::XS::Load;
    }
    elsif ( eval { require YAML::Syck } ) {
        *yaml_encode = \&YAML::Syck::Dump;
        *yaml_decode = \&YAML::Syck::Load;
    }
    elsif ( eval { require YAML } ) {
        *yaml_encode = \&YAML::Dump;
        *yaml_decode = \&YAML::Load;
    }
    elsif ( eval { require YAML::Tiny } ) {
        *yaml_encode = \&YAML::Tiny::Dump;
        *yaml_decode = \&YAML::Tiny::Load;
    }
    else {
        *yaml_encode = *yaml_decode = sub {
            die "No YAML library available!\n";
        };
    }
    return;
}

sub DESTROY {
    my $self = shift;
    $self->close_session;
    return;
}

1;

__END__

=head1 NAME

WGDev - WebGUI Developer Utilities

=head1 SYNOPSIS

    use WGDev;

    my $wgd = WGDev->new( $webgui_root, $config_file );

    my $webgui_session = $wgd->session;
    my $webgui_version = $wgd->version->module;

=head1 DESCRIPTION

Performs common actions needed by WebGUI developers, such as recreating their
site from defaults, checking version numbers, exporting packages, and more.

=head1 AUTHOR

Graham Knop <graham@plainblack.com>

=head1 LICENSE

Copyright (c) Graham Knop.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

