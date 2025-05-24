#!/usr/bin/perl
use strict;
use warnings;

my $host = shift || '8.8.8.8';  # Default target is Google DNS
my $os = $^O;

print "Pinging $host from $os...\n";

if ($os eq 'linux' or $os eq 'darwin') {
    check_latency_unix($host);
} elsif ($os =~ /MSWin32/) {
    check_latency_windows($host);
} else {
    die "Unsupported OS: $os\n";
}

# -------------------------
# Linux/macOS
sub check_latency_unix {
    my $host = shift;
    my $output = `ping -c 1 $host 2>&1`;
    if ($output =~ /min\/avg\/max\/(mdev|stddev) = ([\d.]+)\/([\d.]+)\/([\d.]+)/) {
        print "Latency: Min=$2 ms, Avg=$3 ms, Max=$4 ms\n";
    } else {
        warn "Ping failed or unexpected format:\n$output";
    }
}

# -------------------------
# Windows
sub check_latency_windows {
    my $host = shift;
    my $output = `ping -n 4 $host`;
    if ($output =~ /Average = (\d+)ms/) {
        print "Latency: Avg=$1 ms\n";
    } else {
        warn "Ping failed or unexpected format:\n$output";
    }
}

