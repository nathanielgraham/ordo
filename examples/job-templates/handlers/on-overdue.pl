#!/usr/bin/env perl
# @id on-overdue
# @label On Overdue Handler
# @desc Clone and start a fresh copy when a calendar finds the cluster not ready
use strict;
use warnings;
use LWP::UserAgent;
use JSON::MaybeXS;

# ==================== ON OVERDUE HANDLER ====================
# Purpose: Runs when a calendar tries to start a cluster that is not ready (overdue).
#          Most common use: automatically clone and start a fresh copy of the overdue cluster.

my $overdue_id = $ENV{ORDO_OVERDUE_CLUSTER_ID} or die "ORDO_OVERDUE_CLUSTER_ID not set\n";
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

my $clone_data = post("clone_cluster", $overdue_id);
my $clone_id = $clone_data->{clone_id} or die "No clone_id returned";

print "Cloned $overdue_id -> $clone_id\n";
post("start_cluster", $clone_id);
print "Started cloned cluster $clone_id\n";
