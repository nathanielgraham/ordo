#!/usr/bin/perl
# @id perl
# @label Perl Script
# @desc Perl starter that prints every ORDO_* environment variable
use strict;
use warnings;

# ==================== ORDO ENVIRONMENT VARIABLES ====================
foreach my $key (sort grep { /^ORDO_/ } keys %ENV) {
    print "$key=$ENV{$key}\n";
}
