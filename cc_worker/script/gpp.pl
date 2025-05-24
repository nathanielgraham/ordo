#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(uname);

# Determine the operating system
my ($sysname) = uname();
my $is_windows = ($sysname =~ /Win/i) ? 1 : 0;

# Hash to store process information
my %processes;

sub parse_netstat_windows {
    my @netstat = `netstat -aon 2>&1`;
    return unless @netstat;

    foreach my $line (@netstat) {
        chomp $line;
        # Match lines with TCP or UDP connections and PID
        if ($line =~ /^\s*(TCP|UDP)\s+(\S+):(\d+)\s+(\S+):(\d+)\s+(\w+)\s+(\d+)/i) {
            my ($proto, $local_addr, $local_port, $remote_addr, $remote_port, $state, $pid) = ($1, $2, $3, $4, $5, $6, $7);
            # Skip if PID is 0 (system idle process)
            next if $pid == 0;
            # Get process name using tasklist
            my $proc_name = get_process_name_windows($pid);
            $processes{$pid}{name} = $proc_name || "Unknown";
            $processes{$pid}{connections}++;
            $processes{$pid}{proto}{$proto}++;
        }
    }
}

sub get_process_name_windows {
    my ($pid) = @_;
    my @tasklist = `tasklist /FI "PID eq $pid" /FO CSV 2>&1`;
    foreach my $line (@tasklist) {
        if ($line =~ /"([^"]+)","(\d+)"/) {
            return $1 if $2 == $pid;
        }
    }
    return undef;
}

sub parse_lsof_unix {
    my @lsof = `lsof -i -P -n 2>/dev/null`;
    return unless @lsof;

    foreach my $line (@lsof) {
        chomp $line;
        # Match lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        if ($line =~ /^(\S+)\s+(\d+)\s+\S+\s+\d+\w+\s+(\w+)\s+\S+\s+\S+\s+(TCP|UDP)\s+(\S+):(\d+)(?:->(\S+):(\d+))?/i) {
            my ($proc_name, $pid, $type, $proto, $local_addr, $local_port, $remote_addr, $remote_port) = ($1, $2, $3, $4, $5, $6, $7, $8);
            next if $pid == 0;
            $processes{$pid}{name} = $proc_name;
            $processes{$pid}{connections}++;
            $processes{$pid}{proto}{$proto}++;
        }
    }
}

sub parse_ss_unix {
    my @ss = `ss -tunp 2>/dev/null`;
    return unless @ss;

    foreach my $line (@ss) {
        chomp $line;
        # Match ss output with process info
        if ($line =~ /(tcp|udp)\s+\S+\s+\S+\s+(\S+):(\d+)\s+(\S+):(\d+).*\s+pid=(\d+),\s*comm=(\S+)/i) {
            my ($proto, $local_addr, $local_port, $remote_addr, $remote_port, $pid, $proc_name) = ($1, $2, $3, $4, $5, $6, $7);
            next if $pid == 0;
            $processes{$pid}{name} = $proc_name;
            $processes{$pid}{connections}++;
            $processes{$pid}{proto}{uc($proto)}++;
        }
    }
}

sub print_results {
    print "Network Load Per Process (Open Connections):\n";
    print "PID\tProcess Name\tConnections\tTCP\tUDP\n";
    print "-" x 50 . "\n";
    foreach my $pid (sort { $a <=> $b } keys %processes) {
        my $name = $processes{$pid}{name};
        my $conn = $processes{$pid}{connections} || 0;
        my $tcp = $processes{$pid}{proto}{TCP} || 0;
        my $udp = $processes{$pid}{proto}{UDP} || 0;
        print "$pid\t$name\t$conn\t\t$tcp\t$udp\n";
    }
}

sub main {
    if ($is_windows) {
        parse_netstat_windows();
    } else {
        # Try lsof first, fallback to ss if lsof is not available
        parse_lsof_unix();
        if (!%processes) {
            parse_ss_unix();
        }
    }

    if (!%processes) {
        print "No network connections found or tools (netstat/lsof/ss) not available.\n";
        print "Ensure you have administrative privileges and the required tools installed.\n";
        exit 1;
    }

    print_results();
}

main();
