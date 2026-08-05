#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use HTTP::Tiny;
use JSON::PP;

my $api   = $ENV{ORDO_API}        or die "ORDO_API missing";
my $token = $ENV{ORDO_TOKEN}      or die "ORDO_TOKEN missing";
my $id    = $ENV{ORDO_SERVER_ID}  or die "ORDO_SERVER_ID missing";

$ENV{ORDO_DEBUG} //= 0;

my $json = JSON::PP->new->ascii->pretty->allow_nonref;
my $http = HTTP::Tiny->new( timeout => 10 );

sub post {
    my ( $payload, $retries ) = ( @_, 3 );
    my $res;
    while ( $retries-- ) {
        $res = $http->post(
            $api,
            {
                headers => { 'Content-Type' => 'application/json' },
                content => $payload,
            }
        );
        last if $res->{success};
        warn "[update_stats] Post failed: $res->{status} $res->{reason} - retrying...\n";
        sleep 1;
    }
    die "[update_stats] Post failed after retries: $res->{status} $res->{reason}"
      unless $res->{success};

    my $args = decode_json( $res->{content} // '{}' );
    if ( $args->{exit} || !$args->{success} ) {
        die "[update_stats] Scheduler error: " . $json->encode($args);
    }
    return $args->{pids} || [];
}

# Collect all system info
my $sysinfo = system_info();

# First post: basic sysinfo (no PIDs)
my $basic_payload = $json->encode(
    {
        token   => $token,
        id      => $id,
        command => 'update_sysinfo',
        %$sysinfo,
        pids    => [],
        zombies => []
    }
);
my $pids = post($basic_payload);

# Second post if there are watched PIDs
if (@$pids) {
    my ( $found, $zombies ) = find_pids($pids);
    my $pid_payload = $json->encode(
        {
            token   => $token,
            id      => $id,
            command => 'update_sysinfo',
            %$sysinfo,
            pids    => $found,
            zombies => $zombies
        }
    );
    post($pid_payload);
}

print "[update_stats] Success - sent basic and PID info\n" if $ENV{ORDO_DEBUG};
