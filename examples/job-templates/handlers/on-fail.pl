#!/usr/bin/perl
# @id on-fail
# @label On Fail Handler
# @desc Runs when a cluster fails — alert, fallback, or cleanup
use strict;
use warnings;

# ==================== ON FAIL HANDLER ====================
# Purpose: Runs when a cluster fails. Use this to send alerts,
#          start fallback workflows, or perform cleanup.

print "=== On Fail Handler ===\n";
print "Failed cluster: $ENV{ORDO_FAILED_CLUSTER_ID}\n";

# Example: Send alert
# system("email_team.pl", "Cluster $ENV{ORDO_FAILED_CLUSTER_ID} has failed!");
