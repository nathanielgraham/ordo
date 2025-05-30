#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use CPAN;


#my $json = pop @ARGV;
#die "missing token" unless $json;

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
CPAN::Shell->install(qw(install AnyEvent));
CPAN::Shell->install(qw(install AnyEvent::HTTP));
CPAN::Shell->install(qw(install App::Daemon));
CPAN::Shell->install(qw(install File::HomeDir));
exit 0;
