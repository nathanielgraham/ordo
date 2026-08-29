#!/usr/bin/perl
# @id max-runtime
# @label Max Runtime Handler
# @desc Ask Ordo to stop the job that exceeded max_runtime_seconds
use strict;
use warnings;
use OrdoAgent qw(ordo_post);

# ==================== MAX RUNTIME HANDLER ====================
# Purpose: Runs when a job exceeds its configured maximum runtime.
#          Uses kill_job so it works even if this handler is on another server.
# Needs: core Perl + curl (OrdoAgent).

print "=== Max Runtime Handler ===\n";
print "Cluster: $ENV{ORDO_MAX_RUNTIME_CLUSTER_ID}\n";
print "Job: $ENV{ORDO_MAX_RUNTIME_JOB_ID}\n";

my $job_id  = $ENV{ORDO_MAX_RUNTIME_JOB_ID} or die "ORDO_MAX_RUNTIME_JOB_ID not set\n";
my $api_url = $ENV{ORDO_API}   or die "ORDO_API not set\n";
my $token   = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN not set\n";

my $rv = ordo_post(
    $api_url,
    { command => 'kill_job', id => $job_id, token => $token },
    decode          => 1,
    require_success => 1,
);

print "kill_job $job_id -> ", ( $rv->{message} || 'ok' ), "\n";
