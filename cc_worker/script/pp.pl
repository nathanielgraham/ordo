#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

# Get all PIDs
my @pids = grep { /^\d+$/ } readdir(DIRHANDLE('proc'));

print "PID\tProcess\t\tReceive (Bytes)\tTransmit (Bytes)\n";

foreach my $pid (@pids) {
    next unless -d "/proc/$pid";
    my $cmdline = read_cmdline($pid);
    next unless $cmdline;

    my ($rx, $tx) = get_net_bytes($pid);
    next unless defined $rx;

    printf "%d\t%-15s\t%d\t\t%d\n", $pid, $cmdline, $rx, $tx;
}

# Read process name
sub read_cmdline {
    my ($pid) = @_;
    my $file = "/proc/$pid/comm";
    open my $fh, '<', $file or return;
    my $cmd = <$fh>;
    chomp $cmd;
    return $cmd;
}

# Read network usage (if any)
sub get_net_bytes {
    my ($pid) = @_;
    my $path = "/proc/$pid/net/dev";
    return unless -e $path;
    open my $fh, '<', $path or return;
    my ($rx, $tx) = (0, 0);
    while (<$fh>) {
        next unless /:/;
        my @f = split /[:\s]+/;
        $rx += $f[1] || 0;
        $tx += $f[9] || 0;
    }
    close $fh;
    return ($rx, $tx);
}

# Open /proc safely
sub DIRHANDLE {
    my $dir = shift;
    opendir(my $dh, "/$dir") or die "Can't open /$dir: $!";
    return $dh;
}
