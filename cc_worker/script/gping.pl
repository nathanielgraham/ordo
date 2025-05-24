#!/usr/bin/perl
use strict;
use warnings;
use Net::Ping;
use Time::HiRes qw(time);

# Configuration
my $host = "kay.com";  # Host to ping
my $count = 5;            # Number of pings
my $timeout = 2;          # Timeout in seconds per ping

# Create ping object
my $ping = Net::Ping->new("tcp");

# Set high resolution timing
$ping->hires();

my @latencies;
my $success_count = 0;

print "Pinging $host $count times...\n";

for (1..$count) {
    my $start_time = time();
    if ($ping->ping($host, $timeout)) {
        my $duration = (time() - $start_time) * 1000;  # Convert to milliseconds
        push @latencies, $duration;
        printf("Reply from $host: time=%.2f ms\n", $duration);
        $success_count++;
    } else {
        print "Request to $host timed out\n";
    }
    sleep(1);  # Wait between pings
}

$ping->close();

# Calculate statistics
if ($success_count > 0) {
    my $avg = 0;
    my $min = $latencies[0];
    my $max = $latencies[0];
    my $sum = 0;

    foreach my $latency (@latencies) {
        $sum += $latency;
        $min = $latency if $latency < $min;
        $max = $latency if $latency > $max;
    }
    $avg = $sum / $success_count;

    print "\nPing statistics for $host:\n";
    print "  Packets: Sent = $count, Received = $success_count, Lost = ", $count - $success_count, "\n";
    printf("  Approximate round trip times in milli-seconds:\n");
    printf("    Minimum = %.2fms, Maximum = %.2fms, Average = %.2fms\n", $min, $max, $avg);
} else {
    print "\nNo successful pings to $host\n";
}

