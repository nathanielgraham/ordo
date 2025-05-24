#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(sleep time);
use POSIX qw(uname);

# Interval in seconds for measuring network load
my $interval = 1;

# Detect operating system
my ($sysname) = uname();
my $is_windows = ($sysname =~ /Win/i) ? 1 : 0;
my $is_linux = ($sysname =~ /Linux/i) ? 1 : 0;

# Store initial and final network stats
my %initial_stats;
my %final_stats;

sub get_network_stats {
    my %stats;
    if ($is_linux) {
        open(my $fh, '<', '/proc/net/dev') or die "Cannot open /proc/net/dev: $!";
        while (<$fh>) {
            next unless /^\s*(\w+):/;
            my $interface = $1;
            my @fields = split;
            next unless $fields[0] =~ /:/; # Ensure valid interface line
            $stats{$interface} = {
                rx_bytes => $fields[1],
                tx_bytes => $fields[9]
            };
        }
        close($fh);
    } elsif ($is_windows) {
        my @lines = `netstat -e`;
        for my $line (@lines) {
            if ($line =~ /Bytes\s+(\d+)\s+(\d+)/) {
                $stats{'total'} = {
                    rx_bytes => $1,
                    tx_bytes => $2
                };
                last;
            }
        }
    } else {
        # Assume macOS or BSD-like system
        my @lines = `netstat -ib`;
        for my $line (@lines) {
            next unless $line =~ /^\w+/;
            my @fields = split;
            my $interface = $fields[0];
            next unless defined $fields[6] && defined $fields[9]; # Input/Output bytes
            $stats{$interface} = {
                rx_bytes => $fields[6],
                tx_bytes => $fields[9]
            };
        }
    }
    return %stats;
}

sub print_network_load {
    my ($initial, $final, $interval) = @_;
    print "Network Load (KB/s):\n";
    print "Interface  |  RX (KB/s)  |  TX (KB/s)\n";
    print "-" x 35, "\n";
    for my $interface (keys %$final) {
        next unless exists $initial->{$interface};
        my $rx_diff = ($final->{$interface}{rx_bytes} - $initial->{$interface}{rx_bytes}) / 1024 / $interval;
        my $tx_diff = ($final->{$interface}{tx_bytes} - $initial->{$interface}{tx_bytes}) / 1024 / $interval;
        printf "%-10s | %10.2f | %10.2f\n", $interface, $rx_diff, $tx_diff;
    }
}

# Main loop
while (1) {
    %initial_stats = get_network_stats();
    sleep($interval);
    %final_stats = get_network_stats();
    print "\033[2J"; # Clear screen (works on Unix-like systems)
    print_network_load(\%initial_stats, \%final_stats, $interval);
}
