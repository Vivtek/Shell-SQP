use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Shell::SQP',
    AUTHOR              => q{Michael Roberts <michael@vivtek.com>},
    VERSION_FROM        => 'lib/Shell/SQP.pm',
    ABSTRACT_FROM       => 'lib/Shell/SQP.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    EXE_FILES           => [ qw(script/sqp) ],
    PREREQ_PM => {
        'Test::More' => 0,
        'Term::ShellUI' => 0,
        'DBI' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Shell-SQP-*' },
);
