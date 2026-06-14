#!/usr/bin/perl
use warnings;
use strict;
use File::Spec;
use File::Temp qw(tempfile);
use LWP::UserAgent;
use JSON::PP;
use FindBin qw($Bin);
use Cwd 'abs_path';
use POSIX qw(:sys_wait_h setsid);
use Sys::Hostname;

my $hex  = pop @ARGV or die "missing hex argument";
my $json = pack( 'H*', $hex );
my $job  = decode_json($json) or die "Failed to decode job JSON";

my $api        = $job->{api};
my $id         = $job->{id};
my $cluster_id = $job->{cluster_id};
my $command    = $job->{script};
my $token      = $job->{token};
my $origin     = $job->{origin} || '';
my $delay      = $job->{delay}  || 0;

die "Missing required parameters" unless ( $id && $command && $token && $api );

my $log_bar  = "========================================";
my $hostname = hostname() || 'unknown';

# ==================== DAEMONIZE ====================
sub daemonize {
   my $pid = fork();
   die "Fork failed: $!" unless defined $pid;
   exit(0) if $pid != 0;

   die "Can't create new session: $!" if setsid() < 0;

   $pid = fork();
   die "Fork failed: $!" unless defined $pid;
   exit(0) if $pid != 0;

   chdir("/") or die "Can't chdir to /: $!";
}

daemonize();

my $ppid    = $$;
my $time    = time;
my $out_log = abs_path("$Bin/../logs/out.$id.$ppid.$time.log");

$| = 1;
open STDOUT, '>', $out_log or die "Cannot open log: $!";
open STDERR, '>&STDOUT' or die "Cannot redirect STDERR: $!";
close STDIN;

# ==================== LOG HEADER ====================
print STDOUT "$log_bar\n";
print STDOUT " LOG FILE     : $out_log\n";
print STDOUT " START TIME   : " . scalar( localtime($time) ) . "\n";
print STDOUT " JOB ID       : $id\n";
print STDOUT " HOSTNAME     : $hostname\n";

# Determine execution mode
my $exec_mode =
  ( $command =~ /^#!/ ) ? "Shebang (temp file)" : "Shell wrapper (no shebang)";
print STDOUT " EXEC MODE    : $exec_mode\n";
print STDOUT " SCRIPT       :\n";

# Pretty-print the script
my $script_display = $command;
$script_display =~ s/^/                /gm;
print STDOUT $script_display . "\n";

print STDOUT "$log_bar\n\n";

# ==================== ENVIRONMENT ====================
$ENV{ORDO_JOB_ID}     = $id;
$ENV{ORDO_EMAIL}      = $job->{email} || '';
$ENV{ORDO_TEAM}       = encode_json( $job->{team} || [] );
$ENV{ORDO_SERVER_ID}  = $job->{server_id} || '';
$ENV{ORDO_CLUSTER_ID} = $cluster_id;
$ENV{ORDO_TOKEN}      = $token;
$ENV{ORDO_API}        = $api;
$ENV{ORDO_JSON}       = encode_json( $job->{json} || {} ) if $job->{json};

&add_to_path("$ENV{HOME}/ordo_node/bin");
&add_to_path("$ENV{HOME}/ordo_node/scripts");

if ( $delay && $delay <= 86400 ) {
   &post(
      {
         command => 'update_job_state',
         token   => $token,
         id      => $id,
         log_id  => $time,
         state   => 'sleeping',
         ppid    => $ppid
      }
   );
   sleep $delay;
}

my $start_state =
  $origin eq 'retry' ? 'retrying' : $origin eq 'loop' ? 'looping' : 'running';

# ==================== INITIAL STATE ====================
&post(
   {
      command => 'update_job_state',
      token   => $token,
      id      => $id,
      started => time,
      state   => $start_state,
      pid     => $$,
      ppid    => $ppid,
      log_id  => $time
   }
);

# ==================== SMART EXECUTION ====================
my $child_pid;

if ( $command =~ /^#!/ ) {

   # Shebang detected → write to temp file and execute DIRECTLY
   my ( $fh, $tempfile ) = tempfile(
      "ordo_job_${id}_XXXXXX",
      DIR    => "/tmp",
      SUFFIX => '.sh',
      UNLINK => 1
   );

   print $fh $command;
   close $fh;
   chmod 0700, $tempfile;

   # Execute the file DIRECTLY so kernel respects shebang
   $child_pid = fork();
   if ( $child_pid == 0 ) {
      exec($tempfile) or die "Failed to exec $tempfile: $!";
   }
}
else {
   $child_pid = fork();
   if ( $child_pid == 0 ) {
      exec( '/bin/sh', '-c', $command ) or die "Exec failed: $!";
   }
}

# ==================== PARENT SUPERVISOR ====================
if ( $child_pid > 0 ) {
   $0 = "supervisor_$child_pid";

   while (1) {
      my $exited = waitpid( $child_pid, WNOHANG );
      if ( $exited == $child_pid ) {
         my $exit_code = $? >> 8;
         my $signal    = $? & 127;
         my $state = $signal ? 'killed' : $exit_code ? 'failed' : 'complete';

         &post(
            {
               command   => 'update_job_state',
               token     => $token,
               id        => $id,
               ended     => time,
               ppid      => $$,
               log_id    => $time,
               state     => $state,
               signal    => $signal,
               exit_code => $exit_code
            }
         );

         my $ended = scalar localtime(time);
         print STDOUT "\n$log_bar\n";
         print STDOUT " END TIME     : $ended\n";
         print STDOUT " SIGNAL       : $signal\n";
         print STDOUT " EXIT CODE    : $exit_code\n";
         print STDOUT "$log_bar\n";

         exit 0;
      }
      sleep 1;
   }
}
else {
   &post(
      {
         command => 'update_job_state',
         token   => $token,
         id      => $id,
         state   => 'failed',
         pid     => $$,
         ppid    => $ppid,
         log_id  => $time
      }
   );
   die "Fork failed: $!";
}

# ==================== HELPERS ====================
sub post {
   my $data = shift;
   my $ua   = LWP::UserAgent->new( timeout => 10 );
   $ua->post(
      $api,
      Content_Type => 'application/json',
      Content      => encode_json($data)
   );
}

sub add_to_path {
   my $new_path = shift;
   my $sep      = $^O =~ /MSWin32/i ? ';' : ':';
   $ENV{PATH} = $new_path . $sep . ( $ENV{PATH} || '' );
}
