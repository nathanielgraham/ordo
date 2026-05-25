#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $sysinfo = system_info();

my $api = $ENV{ORDO_API} or die "ORDO_API missing";

print Dumper($sysinfo);
print "API\n";
print Dumper($api);
print Dumper(\%ENV);

