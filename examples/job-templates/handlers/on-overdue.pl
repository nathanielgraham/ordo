#!/usr/bin/perl
# @id on-overdue
# @label On Overdue Handler
# @desc Clone and start a fresh copy when a calendar finds the cluster not ready
use strict;
use warnings;
use OrdoAgent qw(ordo_post);

# ==================== ON OVERDUE HANDLER ====================
# Purpose: Runs when a calendar tries to start a cluster that is not ready.
#          Most common use: clone and start a fresh copy.
# Needs: core Perl + curl (OrdoAgent). launcher sets PERL5LIB to
#        ~/ordo_node/modules after upgrade_monitor.

my $overdue_id = $ENV{ORDO_OVERDUE_CLUSTER_ID}
  or die "ORDO_OVERDUE_CLUSTER_ID not set\n";
my $api_url = $ENV{ORDO_API}   or die "ORDO_API not set\n";
my $token   = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN not set\n";

sub api {
    my ( $cmd, $id ) = @_;
    return ordo_post(
        $api_url,
        { command => $cmd, id => $id, token => $token },
        decode          => 1,
        require_success => 1,
    );
}

my $clone = api( 'clone_cluster', $overdue_id );
my $clone_id = $clone->{clone_id} or die "No clone_id returned\n";

print "Cloned $overdue_id -> $clone_id\n";
api( 'start_cluster', $clone_id );
print "Started cloned cluster $clone_id\n";
