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

$SIG{TERM} = sub {
   &post({ command => 'update_job', token => $token, id => $id, ended => time, state => 'killed', exit_code => 1 });
   exit 1;
};

my $pid = fork();

if ( $pid == 0 ) {    # child

#   # Become session leader
#   setsid() or die "Can't start a new session: $!";

   # Fork again to avoid reacquiring a terminal
   $pid = fork();
   die "Cannot fork: $!" unless defined $pid;
   exit 0 if $pid;

   # Become session leader
   setsid() or die "Can't start a new session: $!";

   # Change working directory
   chdir '/' or die "Can't chdir to /: $!";
   umask 0;

   # Close file descriptors
   close STDIN;
   close STDOUT;
   close STDERR;

   &post( { command => 'update_job', token => $token, id => $id, state => 'starting', ppid => $$ } );

   my $command_pid = open3( undef, undef, undef, $command );
   waitpid( $command_pid, 0 );

   my $exit_code = $? >> 8;
   &post( { command => 'update_job', token => $token, id => $id, ended => time, state => 'complete', exit_code => $exit_code } );
}

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
