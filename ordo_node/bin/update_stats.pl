#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use OrdoAgent qw(ordo_post);

my $api   = $ENV{ORDO_API}       or die "ORDO_API missing";
my $token = $ENV{ORDO_TOKEN}     or die "ORDO_TOKEN missing";
my $id    = $ENV{ORDO_SERVER_ID} or die "ORDO_SERVER_ID missing";

$ENV{ORDO_DEBUG} //= 1;

my $sysinfo = system_info();

# First post: basic sysinfo (no PIDs)
my $args = ordo_post(
    $api,
    {
        token   => $token,
        id      => $id,
        command => 'update_sysinfo',
        %$sysinfo,
        pids    => [],
        zombies => [],
    },
    retries         => 3,
    decode          => 1,
    require_success => 1,
    on_error        => sub { warn "[update_stats] $_[0]\n" },
);

my $pids = $args->{pids} || [];

# Second post if the scheduler is watching PIDs
if (@$pids) {
    my ( $found, $zombies ) = find_pids($pids);
    ordo_post(
        $api,
        {
            token   => $token,
            id      => $id,
            command => 'update_sysinfo',
            %$sysinfo,
            pids    => $found,
            zombies => $zombies,
        },
        retries         => 3,
        decode          => 1,
        require_success => 1,
        on_error        => sub { warn "[update_stats] $_[0]\n" },
    );
}

print "[update_stats] Success - sent basic and PID info\n" if $ENV{ORDO_DEBUG};
