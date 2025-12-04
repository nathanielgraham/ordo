#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use ordo;

# Initialize the application
my $app = ordo->new;

# Start the Minion worker
$app->log->info("Starting Minion worker with PID $$");
my $worker = $app->minion->worker;
$worker->run;

1;
