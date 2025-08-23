#!/usr/bin/perl

use strict;
use warnings;

#use lib ("$ENV{HOME}/perl5/lib/perl5/lib/perl5", "$ENV{HOME}/perl5/lib/perl5");

# Set environment to use default answers for any prompts (non-interactive mode)
$ENV{PERL_MM_USE_DEFAULT} = 1;

# Load the core CPAN module
use CPAN;

# Install local::lib if not already installed
#unless (eval { require local::lib; 1; }) {
#    CPAN::Shell->install('local::lib');
    #CPAN::Shell->notest('install', 'local::lib');
#}

# Load local::lib and set up local library path (defaults to ~/perl5)
#use local::lib;

my @modules = (qw(File::Which File::HomeDir Sys::Hostname));

# Install each module provided as command-line arguments, skipping tests
foreach my $module (@modules) {
    #CPAN::Shell->notest('install', $module);
    CPAN::Shell->install($module);
}

