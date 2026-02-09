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

print Dumper($sysinfo);
