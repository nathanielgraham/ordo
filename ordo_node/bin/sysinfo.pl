#!/usr/bin/perl

use strict;
use warnings;
use FindBin     qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $api = $ENV{ORDO_API} or die "API missing";
my $json = JSON::PP->new->ascii->pretty->allow_nonref;
my $token = $ENV{ORDO_TOKEN} or die "TOKEN missing";
my $id = $ENV{ORDO_SERVER_ID} or die "SERVER_ID missing";
my $pids  = [];

my $update_payload = sub {
   my $sysinfo = &system_info;
   my ( $found, $zombies ) = &find_pids($pids);
   return $json->encode( { token => $token, id => $id, command => 'update_sysinfo', %$sysinfo, pids => $found, zombies => $zombies } );
};

# Create a user agent object
my $ua = LWP::UserAgent->new;

while (1) {
   my $request  = &$update_payload;
   my $response = &post($request);
   if ( $response->is_success ) {
      my $body = $response->decoded_content;
      my $args = decode_json($body) or die "unable to parse json: $!";
      if ( $args->{exit} || $args->{success} == 0 ) {
         while ( my ( $k, $v ) = each %$args ) {
            print STDERR "$k: $v\n";
         }
         die "exit signal received from scheduler";
      }
      $pids = $args->{pids};
   }
   else {
      die $response->status_line . "\n";
   }
   sleep(3);
}

sub post {
   my $payload  = shift;
   my $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => $payload
   );
   return $response;
}
