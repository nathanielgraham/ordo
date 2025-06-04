use POSIX qw(:sys_wait_h :errno_h);

# Set the priority of the current process group to a lower value
setpriority(PRIO_PROCESS, 51712, shift @ARGV);

# Check for errors
if ($! != 0) {
    my $error_message = strerror($!);
    die "Error setting priority: $error_message";
}
