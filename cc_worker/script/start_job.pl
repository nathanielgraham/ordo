#!/usr/bin/env perl

use warnings;
use strict;
use feature qw( say );
use JSON;
use Mojo::UserAgent;
use EV;
use IPC::Open3;
use Data::Dumper;
use IO::Handle;

my $time = time;

# User Agent
my $ua = Mojo::UserAgent->new( inactivity_timeout => 0 );

my $job     = decode_json(shift) or die $!;
my $job_id  = $job->{job_id};
my $command = $job->{command};
my $token   = $job->{bookmark};
my $ws      = $job->{websocket} || "ws://0.0.0.0:3000/websocket";
my $looper  = $job->{looper}    || 1;
my $outlog  = $job->{outlog}    || "$job_id.$time.out.log";
my $errlog  = $job->{errlog}    || "$job_id.$time.err.log";

die "params missing" unless ( $job_id && $command && $token );

say Dumper($job);

my $pid = fork();

if ( $pid == 0 ) {    # child

   open OUT, '>', $outlog or die "open failed: $!";
   open ERR, '>', $errlog or die "open failed: $!";

   my $oid = open3( undef, ">&OUT", ">&ERR", $command );

   &reply(
      encode_json(
         {
            command => 'job_started',
            job_id  => $job_id,
            pid     => $oid,
            outlog  => $outlog,
            errlog  => $errlog,
         }
      )
   );

   waitpid( $oid, 0 );
   my $exit_code = $? >> 8;

   my $job_status = $exit_code ? 'job_ended' : 'job_failed';

   &reply(
      encode_json(
         {
            command   => $job_status,
            job_id    => $job_id,
            pid       => $oid,
            exit_code => $exit_code,
            out_log   => $outlog,
            err_log   => $errlog,

         }
      )
   );

   close(OUT);
   close(ERR);
}
elsif ($pid) {    # parent
   exit 0;
}
else {    # fork failure
   &reply(
      encode_json(
         {
            command => 'fork_failure',
            job_id  => $job_id,
         }
      )
   );
   exit 0;
}

sub reply {
   my $json = shift;

   #say ($json);
   $ua->websocket(
      $ws => sub {
         my ( $ua, $tx ) = @_;

         $tx->on(
            finish => sub {
               my ( $tx, $code ) = @_;
               print("WebSocket closed with code $code.\n");
               exit 0;
            }
         );

         $tx->on(
            message => sub {
               my ( $tx, $msg ) = @_;
               my $decoded = decode_json($msg);
               say to_json( $decoded, { pretty => 1 } );
            }
         );

         $tx->send(qq({ "command":"login", "bookmark":"$token" }));
         $tx->send($json);
         $tx->finish;
      }
   );
}

EV::run;
