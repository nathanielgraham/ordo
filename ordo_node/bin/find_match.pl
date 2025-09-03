#!/usr/bin/perl

use strict;
use warnings;

my $match = shift;
exit unless $match;

my $process_name_pattern = qr/$match/;

# Determine the operating system
my $os = $^O;

my @pids;

if ($os eq 'linux' || $os eq 'darwin') {  # Linux or macOS
    # Use 'ps' command to list processes
    my @processes = `ps -eo pid,comm`;  # Get PID and command name
    foreach my $line (@processes) {
        if ($line =~ /(\d+)\s+($process_name_pattern)/) {
            push @pids, $1;  # Capture the PID
        }
    }
} elsif ($os eq 'MSWin32') {  # Windows
    # Use 'tasklist' command to list processes
    my @processes = `tasklist`;
    foreach my $line (@processes) {
        if ($line =~ /(\d+)\s+($process_name_pattern)/) {
            push @pids, $1;  # Capture the PID
        }
    }
} 

my $first_pid = shift @pids;
print $first_pid if $first_pid;
