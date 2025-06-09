#!/usr/bin/env perl

use warnings;
use strict;
use LWP::UserAgent;
use JSON::PP;
use FindBin qw($Bin);
use POSIX   qw(:sys_wait_h setsid);
use feature qw(say);

my $hex  = pop @ARGV or die "missing arg";
my $json = pack( 'H*', $hex );

my $api = 'http://127.0.0.1:3000/api';

my $job = decode_json($json) or die $!;
my $id  = $job->{id};

my $command = $job->{shell};
my $token   = $job->{token};

die "params missing" unless ( $id && $command && $token );

# logging
my $time    = time;
my $out_log = "$Bin/../logs/out.$id.$time.log";
my $err_log = "$Bin/../logs/err.$id.$time.log";

open STDOUT, '>', $out_log or die $!;
open STDERR, '>', $err_log or die $!;
close STDIN;

sub daemonize {

   my $pid = fork();
   if ( !defined $pid ) {
      die "Fork failed: $!";
   }
   elsif ( $pid != 0 ) {
      exit(0);
   }

   # Create a new session
   if ( setsid() < 0 ) {
      die "Can't create a new session: $!";
   }

   # Fork again to ensure the daemon is not a session leader
   $pid = fork();
   if ( !defined $pid ) {
      die "Fork failed: $!";
   }
   elsif ( $pid != 0 ) {
      exit(0);
   }

   # Change the working directory to root
   chdir("/") or die "Can't change directory to /: $!";
}

daemonize();

my $ppid = $$;
my $pid  = fork();

if ( !defined $pid ) {
   &post( { command => 'update_job', token => $token, id => $id, state => 'failed', ppid => $ppid } );
   die "First fork failed: $!";
}
elsif ( $pid == 0 ) {

   # child
   my @cmd = $command =~ /"([^"]*)"|(\S+)/g;
   @cmd = grep { defined $_ } @cmd;
   eval { exec { $cmd[0] } @cmd or die "Exec failed: $!" };

   if ($@) {
      &post( { command => 'update_job', token => $token, id => $id, state => 'failed', pid => $$, ppid => $ppid } );
      die "Second fork failed: $@";
   }
}
else {
   # parent
   $0 = "supervisor_$pid";
   say "Started child process with PID $pid";
   &post( { command => 'update_job', token => $token, id => $id, state => 'running', pid => $pid, ppid => $$ } );

   while (1) {    # stain' alive
      sleep(1);
      my $child_pid = waitpid( -1, WNOHANG );
      if ( $child_pid == $pid ) {
         my $exit_code = $? >> 8;
         my $signal    = $? & 127;
         my $state     = $signal ? 'killed' : $exit_code ? 'failed' : 'complete';
         &post( { command => 'update_job', token => $token, id => $id, state => $state, exit_code => $exit_code } );
         exit 0;
      }
   }
}

#Common Exit Codes:
#0: Success.
#1: General error (common in many programs, e.g., grep when no matches are found).
#2: Common for misuse of shell built-ins or incorrect command-line arguments (e.g., in bash or grep).
#126: Command found but not executable (permission issue or not a binary).
#127: Command not found.
#128 + n: Process terminated by signal n (e.g., 128 + 9 = 137 for SIGKILL).
#255: Exit code out of range (some systems use this for invalid exit codes).
# SIGNALS: 15 = TERM, 9 = KILLED

sub post {
   my $data = shift;
   my $ua   = LWP::UserAgent->new;
   $ua->timeout(10);
   $ua->agent('cc');
   my $json = encode_json($data);
   say $json;
   my $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => $json
   );

   if ( $response->is_success ) {
      say STDOUT $response->decoded_content;
   }
   else {
      say STDERR $response->status_line;
   }
}
