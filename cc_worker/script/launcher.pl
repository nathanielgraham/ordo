#!/usr/bin/perl

use warnings;
use strict;

use lib ("$ENV{HOME}/perl5/lib/perl5/lib/perl5", "$ENV{HOME}/perl5/lib/perl5");
#use local::lib;
#print Dumper(\@INC);
#print Dumper(\%ENV);

use LWP::UserAgent;
use JSON::PP;
use FindBin qw($Bin);
use POSIX   qw(:sys_wait_h setsid);
use Cwd 'abs_path';
use feature qw(say);
use Data::Dumper;

my $hex  = pop @ARGV or die "missing arg";
my $json = pack( 'H*', $hex );

my $api = 'http://192.168.68.56:3000/api';
#my $api = 'https://192.168.68.56/api';

my $job        = decode_json($json) or die $!;
my $id         = $job->{id};
my $cluster_id = $job->{cluster_id};
my $command    = $job->{script};
my $token      = $job->{token};
my $origin     = $job->{origin};
my $delay      = $job->{delay};
my $log_bar = "========================================";

die "params missing" unless ( $id && $command && $token );

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

# logging
my $time    = time;
my $out_log = abs_path("$Bin/../logs/out.$id.$ppid.$time.log");
#my $err_log = abs_path("$Bin/../logs/err.$id.$ppid.$time.log");

$| = 1;


open STDOUT, '>', $out_log or die $!;
open STDERR, '>&', \*STDOUT or die $!;
close STDIN;

if ($delay && $delay <= 3600) {
   my $state = $origin eq 'retry' ? 'retrying' : $origin eq 'loop' ? 'looping' : undef;
   if ($state) {
      &post( { command => 'update_job', token => $token, id => $id, log_id => $time, state => $state, ppid => $ppid } );
      sleep $delay;
   }
}

my $started = scalar localtime($time);

print STDOUT "\n$log_bar\n";
print STDOUT " LOG FILE    : $out_log\n";
print STDOUT " START TIME  : $started\n";

my $log_info = <<~"HEAD";
 JOB ID      : $id
 SCRIPT      : $command
HEAD

print STDOUT $log_info;

my $pid  = fork();

if ( !defined $pid ) {
   &post( { command => 'update_job', token => $token, id => $id, log_id => $time, state => 'failed', ppid => $ppid } );
   die "fork failed: $!";
}
elsif ( $pid == 0 ) {

   print STDOUT " PID         : $$\n";
   print STDOUT "$log_bar\n\n";

   # TODO: add cwd to PATH
   # child
   $ENV{JOB_ID} = $id;
   $ENV{TOKEN}  = $token;
   $ENV{PATH} = "$ENV{HOME}/cc_worker/script:$ENV{PATH}";
   print Dumper(\%ENV);
   my @cmd = &extract_command($command);
   eval { exec { $cmd[0] } @cmd or die "Exec failed: $!" };


   if ($@) {
      &post( { command => 'update_job', token => $token, id => $id, state => 'failed', pid => $$, ppid => $ppid, log_id => $time } );
      die "fork failed: $@";
   }
}
else {
   # parent
   $0 = "supervisor_$pid";
   &post( { command => 'update_job', token => $token, started => time, id => $id, state => 'running', pid => $pid, ppid => $$, log_id => $time } );

   while (1) {    # stain' alive
      sleep(1);
      my $child_pid = waitpid( -1, WNOHANG );
      if ( $child_pid == $pid ) {
         my $exit_code = $? >> 8;
         my $signal    = $? & 127;
         my $state     = $signal ? 'killed' : $exit_code ? 'failed' : 'complete';
         &post( { command => 'update_job', ended => time, token => $token, id => $id, log_id => $time, ppid => $$, state => $state, signal => $signal, exit_code => $exit_code } );

         my $ended = scalar localtime(time);
         my $log_tail = <<~"TAIL";

         $log_bar
          END TIME    : $ended
          SIGNAL      : $signal
          EXIT CODE   : $exit_code
         $log_bar

         TAIL

         print STDOUT $log_tail;

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
   my $response = $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => $json
   );

   if ( $response->is_success ) {
      #say $response->decoded_content);
   }
   else {
      #say STDERR $response->status_line;
   }
}

sub extract_command {
   my $string = shift;
   my @parts;
   my $current   = '';
   my $in_quotes = '';
   my $i         = 0;

   while ( $i < length($string) ) {
      my $char = substr( $string, $i, 1 );

      if ($in_quotes) {

         # Inside quotes, collect until matching quote
         $current .= $char;
         if ( $char eq $in_quotes && ( $i == 0 || substr( $string, $i - 1, 1 ) ne '\\' ) ) {
            $in_quotes = '';    # Exit quote mode
         }
      }
      elsif ( $char eq '"' || $char eq "'" ) {

         # Start of quoted string
         $in_quotes = $char;
         $current .= $char;
      }
      elsif ( $char =~ /\s/ ) {

         # Whitespace outside quotes: finalize current part
         if ( $current ne '' ) {
            push @parts, $current;
            $current = '';
         }
      }
      else {
         # Non-whitespace outside quotes
         $current .= $char;
      }
      $i++;
   }

   push @parts, $current if $current ne '';

   # Clean up quotes from the parts
   @parts = map { s/^['"]|['"]$//g; $_ } @parts;

   return @parts;
}
