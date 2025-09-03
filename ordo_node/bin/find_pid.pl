#!/usr/bin/env perl

use strict;
use warnings;
use FindBin     qw($Bin);
use lib "$Bin/../modules";
use SysInfo;

my $pid = shift;

exit unless $pid && $pid =~ /^\d+$/;

my $found = &pid_info($pid);

print $found->{pid} if $found;

