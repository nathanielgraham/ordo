#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $api = $ENV{ORDO_API} or die "ORDO_API missing";
my $token = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN missing";
my $id = $ENV{ORDO_SERVER_ID} or die "ORDO_SERVER_ID missing";
$ENV{ORDO_DEBUG} = 1;

my $json = JSON::PP->new->ascii->pretty->allow_nonref;
my $ua = LWP::UserAgent->new(timeout => 10);

# Helper to post with retry
sub post {
  my ($payload, $retries) = (@_, 3);
  my $response;

  while ($retries--) {
    $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content => $payload
    );
    last if $response->is_success;
    warn "[update_stats] Post failed: " . $response->status_line . " - retrying...\n";
    sleep 1;
  }

  die "[update_stats] Post failed after retries: " . $response->status_line unless $response->is_success;

  my $args = decode_json($response->decoded_content);
  die "[update_stats] Scheduler error: " . Dumper($args) if $args->{exit} || !$args->{success};

  return $args->{pids} || [];
}

# Collect all system info
my $sysinfo = system_info();

# First post: basic sysinfo (no PIDs)
my $basic_payload = $json->encode({
  token => $token,
  id => $id,
  command => 'update_sysinfo',
  %$sysinfo,
  pids => [],
  zombies => []
});

my $pids = post($basic_payload);

# Second post if there are watched PIDs
if (@$pids) {
  my ($found, $zombies) = find_pids($pids);
  my $pid_payload = $json->encode({
    token => $token,
    id => $id,
    command => 'update_sysinfo',
    %$sysinfo,
    pids => $found,
    zombies => $zombies
  });
  post($pid_payload);
}

print "[update_stats] Success - sent basic and PID info\n" if $ENV{ORDO_DEBUG};
