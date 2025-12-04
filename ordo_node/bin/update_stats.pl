#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $api   = $ENV{ORDO_API}       or die "API missing";
my $token = $ENV{ORDO_TOKEN}     or die "TOKEN missing";
my $id    = $ENV{ORDO_SERVER_ID} or die "SERVER_ID missing";
my $json  = JSON::PP->new->ascii->pretty->allow_nonref;

my $sysinfo = &system_info;

#my $request = $json->encode( { token => $token, id => $id, command => 'update_sysinfo', %$sysinfo, pids => $found, zombies => $zombies } );
my $update_stats = $json->encode( { token => $token, id => $id, command => 'update_sysinfo', %$sysinfo, pids => [], zombies => [] } );

# update stats and request active pids from scheduler

my $ua = LWP::UserAgent->new;
my $pids = &post($update_stats);

if ( scalar @{$pids} ) {
   my ( $found, $zombies ) = &find_pids($pids);
   my $update_pids = $json->encode( { token => $token, id => $id, command => 'update_sysinfo', %$sysinfo, pids => $found, zombies => $zombies } );
   #my $update_pids = $json->encode( { token => $token, id => $id, command => 'update_sysinfo', pids => $found, zombies => $zombies } );
   &post($update_pids);
}

sub post {
   my $request  = shift;
   my $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => $request
   );
   if ( $response->is_success ) {
      my $body = $response->decoded_content;
      my $args = decode_json($body) or die "unable to parse json: $!";
      if ( $args->{exit} || $args->{success} == 0 ) {
         while ( my ( $k, $v ) = each %$args ) {
            print STDERR "$k: $v\n";
         }
         die "exit signal received from scheduler";
      }
      $pids = $args->{pids} if $args->{pids};
      return $args->{pids};
   }
   else {
      die $response->status_line . "\n";
   }
}
