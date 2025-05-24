#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(sleep);
use Config;

sub get_network_stats {
    if ($^O eq 'linux') {
        return parse_linux_net_dev();
    } elsif ($^O eq 'darwin') {
        return parse_bsd_netstat();
    } elsif ($^O eq 'MSWin32') {
        return parse_windows_netstat();
    } else {
        die "Unsupported OS: $^O\n";
    }
}

sub parse_linux_net_dev {
    my %stats;
    open my $fh, '<', '/proc/net/dev' or die "Can't open /proc/net/dev: $!";
    while (<$fh>) {
        next unless /:/;
        my ($iface, $data) = split /:/;
        my @fields = split /\s+/, $data;
        $stats{$iface}{rx} = $fields[0];
        $stats{$iface}{tx} = $fields[8];
    }
    close $fh;
    return \%stats;
}

sub parse_bsd_netstat {
    my %stats;
    my @lines = qx(netstat -ib);
    shift @lines; shift @lines; # Remove headers
    for (@lines) {
        my @fields = split;
        my ($iface, $ibytes, $obytes) = @fields[0,6,9];
        next unless $iface && $ibytes =~ /^\d+$/;
        $stats{$iface}{rx} += $ibytes;
        $stats{$iface}{tx} += $obytes;
    }
    return \%stats;
}

sub parse_windows_netstat {
    my %stats;
    my @lines = qx(netstat -e);
    for (@lines) {
        if (/^\s*Bytes\s+(\d+)\s+(\d+)/) {
            $stats{'Ethernet'}{rx} = $1;
            $stats{'Ethernet'}{tx} = $2;
            last;
        }
    }
    return \%stats;
}

sub calculate_load {
    my ($before, $after) = @_;
    my %delta;

    foreach my $iface (keys %$after) {
        next unless exists $before->{$iface};
        $delta{$iface}{rx} = $after->{$iface}{rx} - $before->{$iface}{rx};
        $delta{$iface}{tx} = $after->{$iface}{tx} - $before->{$iface}{tx};
    }

    return \%delta;
}

# Main execution
print "Checking network load...\n";
my $start = get_network_stats();
sleep(1.0); # Adjust the interval as needed
my $end = get_network_stats();
my $load = calculate_load($start, $end);

foreach my $iface (keys %$load) {
    print "Interface: $iface\n";
    print "  RX: $load->{$iface}{rx} bytes/sec\n";
    print "  TX: $load->{$iface}{tx} bytes/sec\n";
}

