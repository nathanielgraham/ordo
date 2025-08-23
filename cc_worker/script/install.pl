#!/usr/bin/env perl
use strict;
use warnings;
use CPAN;

use lib ("$ENV{HOME}/perl5/lib/perl5/lib/perl5", "$ENV{HOME}/perl5/lib/perl5");

# Install from CPAN with defaults
$ENV{PERL_MM_USE_DEFAULT} = 1;

# Bootstrap local::lib for local install
my $mod = CPAN::Shell->expand(Module => "local::lib");
$mod->get;
my $dir = CPAN::Shell->expand(Distribution => $mod->cpan_file)->dir;
chdir($dir);
my $make = $CPAN::Config->{make};
system($^X, 'Makefile.PL', '--bootstrap') && exit 1;
#system($make, 'test') && exit 1;
system($make, 'install') && exit 1;

require local::lib;
local::lib->import;

CPAN::Shell->install(qw(install Sys::Hostname));
CPAN::Shell->install(qw(install Proc::ProcessTable));
CPAN::Shell->install(qw(install File::HomeDir));
exit 0;
