#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Shell::SQP' ) || print "Bail out!\n";
}

diag( "Testing Shell::SQP $Shell::SQP::VERSION, Perl $], $^X" );
