#!/usr/bin/perl
# @id perl
# @label Perl Script
# @desc Perl starter that prints every ORDO_* env (core Perl only)
use strict;
use warnings;

# ==================== ORDO ENVIRONMENT VARIABLES ====================
# HTTP to Ordo:  use OrdoAgent qw(ordo_post);
# launcher sets PERL5LIB=~/ordo_node/modules after upgrade_monitor.

foreach my $key (sort grep { /^ORDO_/ } keys %ENV) {
    print "$key=$ENV{$key}\n";
}
