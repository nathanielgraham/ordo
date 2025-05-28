#!/usr/bin/env perl

use warnings;
use strict;
use LWP::UserAgent;
use JSON::PP;
use IPC::Open3;
use POSIX qw(setsid);

$SIG{HUP}  = sub { exec( $^X, $0, @ARGV ) && exit 0 };

my $json = pop @ARGV;

my $job     = decode_json($json) or die $!;
my $id      = $job->{id};
my $command = $job->{shell};
my $token   = $job->{token};
my $api     = 'http://127.0.0.1:3000/api';

die "params missing" unless ( $id && $command && $token );

my $pid = fork();

if ( $pid == 0 ) {    # child

   # Become session leader
   setsid() or die "Can't start a new session: $!";

   # Fork again to avoid reacquiring a terminal
   $pid = fork();
   die "Cannot fork: $!" unless defined $pid;
   exit 0 if $pid;

   # Change working directory
   chdir '/' or die "Can't chdir to /: $!";
   umask 0;

   # Close file descriptors
   close STDIN;
   close STDOUT;
   close STDERR;

   my ( $stdin, $stdout, $stderr );
   my $command_pid = eval { open3( $stdin, $stdout, $stderr, $command ) };

   if ($@) {
      &post( { command => 'update_job', token => $token, id => $id, state => 'failed', ppid => $$ } );
      exit 1;
   }

   # Close stdin
   close($stdin);

   # Capture output and errors
   my $output = do { local $/; <$stdout> };
   my $errors = do { local $/; <$stderr> };

   &post( { command => 'update_job', token => $token, id => $id, state => 'running', started => time, ppid => $$ } );

   waitpid( $command_pid, 0 );

   my $exit_code = $? >> 8;
   my $signal    = $? & 127;

   my $state = $signal ? 'killed' : $exit_code ? 'failed' : 'complete';
   &post( { command => 'update_job', token => $token, id => $id, ended => time, state => $state, exit_code => $exit_code } );
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

elsif ($pid) {    # parent
   exit 0;
}

sub post {
   my $data = shift;
   my $ua   = LWP::UserAgent->new;
   $ua->timeout(10);
   $ua->agent('cc');
   my $json     = encode_json($data);
   my $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => $json
   );
#   if ( $response->is_success ) {
#      print $response->decoded_content;
#   }
#   else {
#      die $response->status_line;
#   }
}
