use strict;
use warnings;

sub get_uptime {
    my $os = $^O;

    if ($os eq 'linux') {
        return get_linux_uptime();
    } elsif ($os eq 'darwin') {
        return get_macos_uptime();
    } elsif ($os eq 'MSWin32') {
        return get_windows_uptime();
    } else {
        return "Unsupported OS: $os";
    }
}

# Linux uptime from /proc/uptime
sub get_linux_uptime {
    open my $fh, '<', '/proc/uptime' or return "Cannot open /proc/uptime: $!";
    my $line = <$fh>;
    close $fh;

    my ($uptime_seconds) = split ' ', $line;
    return format_uptime($uptime_seconds);
}

# macOS uptime from sysctl
sub get_macos_uptime {
    my $boot_time = `sysctl -n kern.boottime`;
    if ($boot_time =~ /sec = (\d+)/) {
        my $boot_epoch = $1;
        my $uptime_seconds = time() - $boot_epoch;
        return format_uptime($uptime_seconds);
    }
    return "Could not parse boot time.";
}

# Windows uptime from WMIC
sub get_windows_uptime {
    my $output = `wmic os get LastBootUpTime /value`;
    my ($boot_time_str) = $output =~ /LastBootUpTime=(\d{14})/;

    if ($boot_time_str) {
        my ($year, $month, $day, $hour, $min, $sec) = $boot_time_str =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/;
        use Time::Local;
        my $boot_epoch = timegm($sec, $min, $hour, $day, $month - 1, $year);
        my $uptime_seconds = time() - $boot_epoch;
        return format_uptime($uptime_seconds);
    }

    return "Could not determine uptime.";
}

# Format seconds into human-readable time
sub format_uptime {
    my ($secs) = @_;
    my $days = int($secs / 86400);
    $secs %= 86400;
    my $hours = int($secs / 3600);
    $secs %= 3600;
    my $minutes = int($secs / 60);
    $secs = int($secs % 60);

    return sprintf("Uptime: %d days, %02d:%02d:%02d", $days, $hours, $minutes, $secs);
}

# Run and print uptime
print get_uptime(), "\n";

