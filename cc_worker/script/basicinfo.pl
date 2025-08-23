#!/usr/bin/perl

use strict;
use warnings;

use lib ("$ENV{HOME}/perl5/lib/perl5/lib/perl5", "$ENV{HOME}/perl5/lib/perl5");
use local::lib;

use File::Spec;
use Sys::Hostname;
use Cwd;
use JSON::PP;
use File::HomeDir;

my $json = JSON::PP->new->ascii->pretty->allow_nonref;

# system info

my ($os) =
    $^O =~ /MSWin32/i ? 'windows'
  : $^O =~ /darwin/i  ? 'darwin'
  :                     'linux';

my $basic_info = &basic_info;
print $json->encode($basic_info);

sub basic_info {
   my $tmpdir   = File::Spec->tmpdir();
   my $host = hostname();
   my $user = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
   my $cwd   = cwd;
   my $cores = get_cores();
   my $home = File::HomeDir->my_home;
   return { cores => $cores, os => $os, home => $home, cwd => $cwd, tempdir => $tmpdir, user => $user, host => $host };
}

sub get_cores {
   my $cores =
       $os eq 'linux'   ? get_linux_cores()
     : $os eq 'darwin'  ? get_macos_cores()
     : $os eq 'windows' ? get_windows_cores()
     :                    1;

   return $cores;
}

# -------------------------
# Linux: parse /proc/cpuinfo
sub get_linux_cores {
   my $count = 0;
   open( my $fh, '<', '/proc/cpuinfo' ) or die "Can't open /proc/cpuinfo: $!";
   while (<$fh>) {
      $count++ if /^processor\s+:/;

   }
   close $fh;
   return $count;
}

# -------------------------
# macOS: sysctl
sub get_macos_cores {
   my $output = `sysctl -n hw.ncpu`;
   chomp $output;
   return $output;
}

# -------------------------
# Windows: WMIC or fallback to ENV
sub get_windows_cores {
   my $output = `wmic cpu get NumberOfLogicalProcessors /value 2>NUL`;
   if ( $output =~ /NumberOfLogicalProcessors=(\d+)/ ) {
      return $1;
   }
   else {
      # Fallback (not always reliable)
      return $ENV{'NUMBER_OF_PROCESSORS'} || 'Unknown';
   }
}
