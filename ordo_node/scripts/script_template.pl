#!/usr/bin/perl

use warnings;
use strict;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $api = $ENV{ORDO_API} or die "API missing";
my $token = $ENV{ORDO_TOKEN} or die "TOKEN missing";
my $job_id = $ENV{ORDO_JOB_ID} or die "JOB_ID missing";
my $server_id = $ENV{ORDO_SERVER_ID} or die "SERVER_ID missing";
my $cluster_id = $ENV{ORDO_CLUSTER_ID} or die "CLUSTER_ID missing";

my $json = JSON::PP->new->ascii->pretty->allow_nonref;

my $request = {
   token => $token,
   command => "find_cluster",
   id => $cluster_id
};

my $response = &post($request);
my $decoded = decode_json($response);
print $json->encode( $decoded );

exit 0;

sub post {
   my $data = shift;
   my $ua   = LWP::UserAgent->new;
   $ua->timeout(10);
   my $json = encode_json($data);
   my $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => $json
   );

   if ( $response->is_success ) {
      return $response->decoded_content;
   }
   else {
      die $response->status_line;
   }
}

