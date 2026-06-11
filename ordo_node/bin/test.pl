#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use Data::Dumper;

# Basic system info
my $info = system_info();
print "system_info() returned:\n";
print Dumper($info);

# Individual calls
print "\nCPU Cores      : " . get_cores() . "\n";

my $ip = get_local_ip_address();
print "Local IP       : " . ($ip || "N/A") . "\n";

if ($^O eq 'linux') {
    my %load = get_loadavg();
    print "Load Average   : $load{load_1} / $load{load_5} / $load{load_15}\n";
}

print "\n=== Test Complete ===\n";
