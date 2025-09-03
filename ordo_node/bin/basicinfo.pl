#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use LWP::UserAgent;
use File::Spec;
use Cwd;
use JSON::PP;

my $json = JSON::PP->new->ascii->pretty->allow_nonref;

my ($os) =
    $^O =~ /MSWin32/i ? 'windows'
  : $^O =~ /darwin/i  ? 'darwin'
  :                     'linux';

my $basic_info = &basic_info;
print $json->encode($basic_info);

sub basic_info {
   my $tmpdir     = File::Spec->tmpdir();
   my $username   = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
   my $cwd        = cwd;
   my $cores      = get_cores();
   my $home       = $ENV{HOME};
   my $ip_address = get_local_ip_address();
   return { cores => $cores, os => $os, home => $home, cwd => $cwd, tempdir => $tmpdir, ip_address => $ip_address };
}

