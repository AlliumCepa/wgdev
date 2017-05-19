use 5.024001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'WGDev',
    # VERSION_FROM      => 'lib/WGDev.pm', # finds $VERSION, requires EU::MM from perl >= 5.5 ... lib/WGDev.pm has no VERSION
    VERSION           => '0.1203070',

    PREREQ_PM         => {
        'Sub::Name' => 0.1,
        'Config::JSON', 0.1,
        'Test::MockObject', 0.1,
    },

    EXE_FILES => ['bin/wgd'],

    ABSTRACT_FROM     => 'lib/WGDev.pm', # retrieve abstract from module
    AUTHOR            => 'Graham Knop <haarg@haarg.org>',
 
    #LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #http://search.cpan.org/perldoc?Module%3A%3ABuild%3A%3AAPI
);
