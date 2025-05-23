#!/usr/bin/env perl
use strict;
use warnings;
use CPAN;

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
local::lib->import();
CPAN::Shell->notest(qw(install App::Daemon));
require App::Daemon;
App::Daemon->import( qw(daemonize) );

# Install everything else in the background
daemonize() unless  $^O =~ /MSWin32/i;
CPAN::Shell->install(qw(install Sys::Hostname));
CPAN::Shell->install(qw(install Proc::ProcessTable));
CPAN::Shell->install(qw(install AnyEvent));
CPAN::Shell->install(qw(install AnyEvent::HTTP));
CPAN::Shell->install(qw(install File::HomeDir;));
