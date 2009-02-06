package WGDev::Command::Package;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.2.0';

use WGDev::Command::Base;
BEGIN { our @ISA = qw(WGDev::Command::Base) }

use Carp qw(croak);

sub option_config { qw(
    import|i=s@
    parent=s

    upgrade|u
    output-dir|out-dir=s
)}

sub process {
    my $self = shift;
    my $wgd = $self->wgd;
    require File::Copy;
    if ($self->arguments) {
        my $package_dir = $self->option('output-dir') || '.';
        if ($self->option('upgrade')) {
            $package_dir = File::Spec->catdir($wgd->root, 'docs', 'upgrades', 'packages-' . $wgd->version->module);
            if (! -d $package_dir) {
                mkdir $package_dir;
            }
        }
        if (! -d $package_dir) {
            croak "$package_dir does not exist!\n";
        }
        for my $asset_spec ($self->arguments) {
            my $asset = eval { $wgd->asset->find($asset_spec) } || do {
                warn "Unable to find asset $asset_spec!\n";
                next;
            };

            my $storage = $asset->exportPackage;
            my $filename = $storage->getFiles->[0];
            my $filepath = $storage->getPath($filename);
            File::Copy::copy($filepath, File::Spec->catfile($package_dir, $filename));
            printf "Building package %27s for %27s.\n", $filename, $asset->get('title');
        }
    }
    if ($self->option('import')) {
        require WebGUI::Storage;
        my $parent 
            = $self->option('parent')   ? eval { $wgd->asset->find($self->option('parent')) }
            : $wgd->asset->import_node
            ;
        if (! $parent) {
            warn "Unable to find parent node!\n";
            return 0;
        }
        my $versionTag = WebGUI::VersionTag->getWorking($wgd->session);
        $versionTag->set({name => 'WGDev package import'});
        for my $package (@{ $self->option('import')}) {
            my $storage = WebGUI::Storage->createTemp($wgd->session);
            $storage->addFileFromFilesystem($package);
            my $asset = $parent->importPackage($storage);
            print "Imported '$package' to " . $asset->get('url') . "\n";
        }
        $versionTag->commit;
    }
    return 1;
}

1;

__END__

=head1 NAME

WGDev::Command::Package - Export assets for upgrade

=head1 SYNOPSIS

    wgd package [--output-dir=<dir>] [--upgrade] [<asset> ...]
    wgd package [--parent=<asset>] [--import=<package file>]

=head1 DESCRIPTION

Exports or imports assets as packages, optionally placing them in the current
upgrade path.

=head1 OPTIONS

Assets specified as standalong arguments are exported as packages.

=over 8

=item B<--import -i>

Package file (or files) to import.  Will be imported to the import node if no
other parent is specified.

=item B<--parent>

Specify the parent asset to import packages into.

=item B<--upgrade -u>

If specified, packages will be exported to the directory for the upgrade to
the current local version.

=item B<--output-dir --out-dir>

Specify a directory to output the package files to.  If neither --upgrade or
--output-dir is specified, packages will be output to the current directory.

=item B<E<lt>assetE<gt>>

Either an asset ID or an asset URL to specify an asset.

=back

=head1 AUTHOR

Graham Knop <graham@plainblack.com>

=head1 LICENSE

Copyright (c) Graham Knop.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

