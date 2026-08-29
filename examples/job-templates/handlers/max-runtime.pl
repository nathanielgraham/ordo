#!/usr/bin/perl
# @id max-runtime
# @label Max Runtime Handler
# @desc Kill the long-running job when it exceeds max_runtime_seconds
use strict;
use warnings;
use LWP::UserAgent;
use JSON::MaybeXS;

# ==================== MAX RUNTIME HANDLER ====================
# Purpose: Runs when a cluster exceeds its configured maximum runtime.
#          Most common use: kill the long-running job and/or send an alert.

print "=== Max Runtime Handler ===\n";
print "Cluster: $ENV{ORDO_MAX_RUNTIME_CLUSTER_ID}\n";
print "Job: $ENV{ORDO_MAX_RUNTIME_JOB_ID}\n";

my $api_url = $ENV{ORDO_API} or die "ORDO_API not set\n";
my $token   = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN not set\n";

my $ua = LWP::UserAgent->new(timeout => 15);

sub post {
  my ($cmd, $payload) = @_;
  my $res = $ua->post($api_url, Content_Type => 'application/json',
    Content => encode_json({ command => $cmd, id => $payload, token => $token }));
  die "$cmd failed: " . $res->status_line unless $res->is_success;
  return decode_json($res->decoded_content);
}

my $job_info = post("read_job", $ENV{ORDO_MAX_RUNTIME_JOB_ID});
my $pid = $job_info->{pid} or die "Could not find PID for job";

print "Killing job $ENV{ORDO_MAX_RUNTIME_JOB_ID} (PID: $pid)\n";
kill(9, $pid) or warn "Failed to kill PID $pid: $!";
