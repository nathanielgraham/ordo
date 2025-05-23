#!/usr/bin/env perl

use strict;
use warnings;
use File::Spec;
use Sys::Hostname;
use Cwd;
use JSON::PP;
#use File::HomeDir;

my $json  = JSON::PP->new->ascii->pretty->allow_nonref;

# system info

my ($os) =
    $^O =~ /MSWin32/i ? 'windows'
  : $^O =~ /darwin/i  ? 'darwin'
  :                     'linux';

my $basic_info = &basic_info;
print $json->encode($basic_info);

sub basic_info {
   my $tmpdir   = File::Spec->tmpdir();
   my $hostname = hostname();
   my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
   my $curdir   = cwd;
   #my $home = File::HomeDir->my_home;
   return { os => $os, curdir => $curdir, tempdir => $tmpdir, username => $username, hostname => $hostname };
}
