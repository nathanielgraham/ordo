#!/usr/bin/perl
use warnings;
use strict;
use File::Temp qw(tempfile);
use JSON::PP;
use HTTP::Tiny;
use FindBin qw($Bin);
use Cwd 'abs_path';
use POSIX qw(:sys_wait_h setsid);
use Sys::Hostname;
use lib "$Bin/../modules";
use OrdoAgent qw(ordo_post);

my $hex = pop @ARGV or die "missing hex argument";
my $json = pack( 'H*', $hex );
my $job = decode_json($json) or die "Failed to decode job JSON";

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

my $ppid                  = $$;
my $start_time            = time;
my $max_runtime_triggered = 0;
my $out_log = abs_path("$Bin/../logs/out.$id.$ppid.$start_time.log");

$| = 1;
open STDOUT, '>',  $out_log or die "Cannot open log: $!";
open STDERR, '>&', STDOUT   or die "Cannot redirect STDERR: $!";
close STDIN;

# ==================== LOG HEADER ====================
print STDOUT "$log_bar\n";
print STDOUT " LOG FILE   : $out_log\n";
print STDOUT " START TIME : " . scalar( localtime($start_time) ) . "\n";
print STDOUT " JOB ID     : $id\n";
print STDOUT " HOSTNAME   : $hostname\n";
my $exec_mode =
  ( $command =~ /^#!/ )
  ? "Shebang (temp file)"
  : "Shell wrapper (no shebang)";
print STDOUT " EXEC MODE  : $exec_mode\n";
print STDOUT "$log_bar\n\n";

# ==================== ENVIRONMENT ====================
$ENV{ORDO_JOB_ID}     = $id;
$ENV{ORDO_EMAIL}      = $job->{email} || '';
$ENV{ORDO_TEAM}       = encode_json( $job->{team} || [] );
$ENV{ORDO_SERVER_ID}  = $job->{server_id} || '';
$ENV{ORDO_CLUSTER_ID} = $cluster_id;
$ENV{ORDO_TOKEN}      = $token;
$ENV{ORDO_API}        = $api;
$ENV{ORDO_DELAY}      = $delay;

# Attached JSON bags (durable job/cluster config). Only set when truthy.
$ENV{ORDO_JOB_JSON} = $job->{job_json}
  if defined $job->{job_json} && length $job->{job_json};
$ENV{ORDO_CLUSTER_JSON} = $job->{cluster_json}
  if defined $job->{cluster_json} && length $job->{cluster_json};

if ( $job->{handler_context} && ref( $job->{handler_context} ) eq 'HASH' ) {
    $ENV{ORDO_HANDLER_CONTEXT} = encode_json( $job->{handler_context} );
    $ENV{ORDO_FAILED_CLUSTER_ID} =
      $job->{handler_context}->{fail}->{origin_cluster_id};
    $ENV{ORDO_FAILED_CLUSTER_NAME} =
      $job->{handler_context}->{fail}->{origin_cluster_name};
    $ENV{ORDO_MAX_RUNTIME_JOB_ID} =
      $job->{handler_context}->{max_runtime}->{origin_job_id};
    $ENV{ORDO_MAX_RUNTIME_CLUSTER_ID} =
      $job->{handler_context}->{max_runtime}->{origin_cluster_id};
    $ENV{ORDO_MAX_RUNTIME_SECONDS} =
      $job->{handler_context}->{max_runtime}->{max_runtime_seconds};
    $ENV{ORDO_OVERDUE_CLUSTER_ID} =
      $job->{handler_context}->{overdue}->{origin_cluster_id};
    $ENV{ORDO_OVERDUE_CLUSTER_NAME} =
      $job->{handler_context}->{overdue}->{origin_cluster_name};
}

for my $key ( keys %ENV ) {
    next unless $key =~ /ORDO/;
    delete $ENV{$key} unless defined $ENV{$key};
}

add_to_path("$ENV{HOME}/ordo_node/bin");
add_to_path("$ENV{HOME}/ordo_node/scripts");
add_to_perl5lib("$ENV{HOME}/ordo_node/modules");

if ( $delay && $delay <= 86400 ) {
    post(
        {
            command => 'update_job_state',
            token   => $token,
            id      => $id,
            log_id  => $start_time,
            state   => 'sleeping',
            ppid    => $ppid
        }
    );
    sleep $delay;
}

my $start_state =
    $origin eq 'retry' ? 'retrying'
  : $origin eq 'loop'  ? 'looping'
  :                      'running';

# ==================== SMART EXECUTION ====================
my $child_pid;
if ( $command =~ /^#!/ ) {
    my ( $fh, $tempfile ) = tempfile(
        "ordo_job_${id}_XXXXXX",
        DIR    => "/tmp",
        SUFFIX => '.sh',
        UNLINK => 1
    );
    print $fh $command;
    close $fh;
    chmod 0700, $tempfile;
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

# ==================== INITIAL STATE ====================
post(
    {
        command => 'update_job_state',
        token   => $token,
        id      => $id,
        started => time,
        state   => $start_state,
        pid     => $child_pid,
        ppid    => $ppid,
        log_id  => $start_time
    }
);

# ==================== PARENT SUPERVISOR ====================
if ( $child_pid > 0 ) {
    $0 = "supervisor_$child_pid";
    while (1) {
        my $exited = waitpid( $child_pid, WNOHANG );
        if ( $exited == $child_pid ) {
            my $exit_code = $? >> 8;
            my $signal    = $? & 127;
            my $state = $signal ? 'killed' : $exit_code ? 'failed' : 'complete';
            post(
                {
                    command   => 'update_job_state',
                    token     => $token,
                    id        => $id,
                    ended     => time,
                    ppid      => $$,
                    log_id    => $start_time,
                    state     => $state,
                    signal    => $signal,
                    exit_code => $exit_code
                }
            );
            my $ended = scalar localtime(time);
            print STDOUT "\n$log_bar\n";
            print STDOUT " END TIME  : $ended\n";
            print STDOUT " SIGNAL    : $signal\n";
            print STDOUT " EXIT CODE : $exit_code\n";
            print STDOUT "$log_bar\n";
            exit 0;
        }

        # === Max Runtime Enforcement ===
        if (  $job->{max_runtime_seconds}
            && $job->{max_runtime_seconds} > 0
            && !$max_runtime_triggered )
        {
            my $elapsed = time() - $start_time;
            if ( $elapsed > $job->{max_runtime_seconds} ) {
                print STDOUT
"MAX RUNTIME EXCEEDED ($elapsed seconds > $job->{max_runtime_seconds} seconds)\n";
                if ( $job->{max_runtime_cluster_id} ) {
                    post(
                        {
                            command               => 'handle_max_runtime',
                            job_id                => $id,
                            cluster_id            => $cluster_id,
                            token                 => $token,
                            elapsed_seconds       => $elapsed,
                            max_runtime_cluster_id =>
                              $job->{max_runtime_cluster_id},
                            max_runtime_seconds => $job->{max_runtime_seconds},
                        }
                    );
                    print STDOUT
"Triggered max_runtime handler cluster $job->{max_runtime_cluster_id}\n";
                    $max_runtime_triggered = 1;
                }
            }
        }
        sleep 1;
    }
}
else {
    post(
        {
            command => 'update_job_state',
            token   => $token,
            id      => $id,
            state   => 'failed',
            pid     => $$,
            ppid    => $ppid,
            log_id  => $start_time
        }
    );
    die "Fork failed: $!";
}

# ==================== HELPERS ====================
sub post {
    my ($data) = @_;
    ordo_post(
        $api, $data,
        soft_fail => 1,
        on_error  => sub { print STDOUT "$_[0]\n" },
    );
}

sub add_to_path {
    my $new_path = shift;
    my $sep = $^O =~ /MSWin32/i ? ';' : ':';
    $ENV{PATH} = $new_path . $sep . ( $ENV{PATH} || '' );
}

# Job bodies run from /tmp; they need this to `use OrdoAgent`.
sub add_to_perl5lib {
    my $dir = shift;
    return unless $dir && -d $dir;
    my $sep = $^O =~ /MSWin32/i ? ';' : ':';
    $ENV{PERL5LIB} =
      $ENV{PERL5LIB} ? $dir . $sep . $ENV{PERL5LIB} : $dir;
}
