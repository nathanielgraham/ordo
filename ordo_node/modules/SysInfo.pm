package SysInfo;
use strict;
use warnings;
use Exporter 'import';
use IO::Socket::INET;

our @EXPORT = qw(get_local_ip_address get_cores pid_info find_pids system_info get_loadavg);

my $OS = $^O =~ /MSWin32/i ? 'windows'
       : $^O =~ /darwin/i  ? 'darwin'
       : 'linux';

# ===================================================================
# Stable / Cheap metrics
# ===================================================================

sub get_cores {
    return $OS eq 'linux'  ? get_linux_cores()
         : $OS eq 'darwin' ? get_macos_cores()
         : $OS eq 'windows'? get_windows_cores()
         : 1;
}

sub get_local_ip_address {
    my $socket = IO::Socket::INET->new(
        Proto    => 'udp',
        PeerAddr => '198.41.0.4',
        PeerPort => '53',
        Timeout  => 2,
    );
    return $socket ? $socket->sockhost : undef;
}

# ===================================================================
# Linux
# ===================================================================

sub get_linux_cores {
    my $count = 0;
    if (open my $fh, '<', '/proc/cpuinfo') {
        while (<$fh>) {
            $count++ if /^processor\s*:/;
        }
        close $fh;
    }

    # Fallback using cpu cores + siblings
    if ($count == 0 || $count == 1) {
        if (open my $fh, '<', '/proc/cpuinfo') {
            my $cores = 0;
            my $siblings = 0;
            while (<$fh>) {
                $cores = $1 if /^cpu cores\s*:\s*(\d+)/;
                $siblings = $1 if /^siblings\s*:\s*(\d+)/;
            }
            close $fh;
            $count = $siblings || $cores * 2 || 1;
        }
    }
    return $count;
}

sub get_loadavg {
    my %load = (load_1 => undef, load_5 => undef, load_15 => undef);
    open my $fh, '<', '/proc/loadavg' or return %load;
    my $line = <$fh>;
    close $fh;
    return %load unless $line;

    chomp $line;
    my @f = split /\s+/, $line;
    $load{load_1}  = $f[0] if $f[0] =~ /^[\d\.]+$/;
    $load{load_5}  = $f[1] if $f[1] =~ /^[\d\.]+$/;
    $load{load_15} = $f[2] if $f[2] =~ /^[\d\.]+$/;

    return %load;
}

sub get_memory_swap {
    my %mem = (
        total_memory => undef, used_memory => undef, free_memory => undef,
        total_swap   => undef, used_swap   => undef, free_swap   => undef
    );
    open my $fh, '<', '/proc/meminfo' or return %mem;
    while (<$fh>) {
        $mem{total_memory} = $1 * 1024 if /^MemTotal:\s+(\d+)/;
        $mem{free_memory}  = $1 * 1024 if /^MemFree:\s+(\d+)/;
        $mem{total_swap}   = $1 * 1024 if /^SwapTotal:\s+(\d+)/;
        $mem{free_swap}    = $1 * 1024 if /^SwapFree:\s+(\d+)/;
    }
    close $fh;

    $mem{used_memory} = $mem{total_memory} - $mem{free_memory}
        if defined $mem{total_memory} && defined $mem{free_memory};

    $mem{used_swap} = $mem{total_swap} - $mem{free_swap}
        if defined $mem{total_swap} && defined $mem{free_swap};

    return %mem;
}

sub get_disk {
    my %disk = (
        total_disk => undef, used_disk => undef, free_disk => undef,
        root_total_disk => undef, root_used_disk => undef, root_free_disk => undef
    );

    my @df = `df -lP --total 2>/dev/null`;
    foreach (@df) {
        next unless /^total/;
        my @f = split /\s+/;
        $disk{total_disk} = $f[1];
        $disk{used_disk}  = $f[2];
        $disk{free_disk}  = $f[3];
        last;
    }

    my $root = `df -B1 / 2>/dev/null | tail -1`;
    if ($root =~ /\s+(\d+)\s+(\d+)\s+(\d+)/) {
        $disk{root_total_disk} = $1;
        $disk{root_used_disk}  = $2;
        $disk{root_free_disk}  = $3;
    }

    return %disk;
}

sub get_network_total {
    my %net = (net_rx_bytes => 0, net_tx_bytes => 0);
    open my $fh, '<', '/proc/net/dev' or return %net;
    while (<$fh>) {
        next if /^Inter|^ face/;
        my @f = split /\s+/;
        $net{net_rx_bytes} += $f[1] if $f[1] =~ /^\d+$/;
        $net{net_tx_bytes} += $f[9] if $f[9] =~ /^\d+$/;
    }
    close $fh;
    return %net;
}

sub get_open_files {
    my %files = (open_files => undef, max_files => undef);
    open my $fh, '<', '/proc/sys/fs/file-nr' or return %files;
    my $line = <$fh>;
    close $fh;
    my ($allocated, $unused, $max) = split /\s+/, $line;
    $files{open_files} = $allocated;
    $files{max_files}  = $max;
    return %files;
}

sub get_processes {
    my %proc = (total_processes => 0, zombie_processes => 0);
    return %proc unless $OS eq 'linux';

    my $total = `ps -e | wc -l 2>/dev/null`;
    chomp $total;
    $proc{total_processes} = $total > 0 ? $total - 1 : 0;

    my $zombies = `ps -eo stat | grep -c '^Z' 2>/dev/null`;
    chomp $zombies;
    $proc{zombie_processes} = $zombies || 0;

    return %proc;
}

sub get_cpu_percent {
    return undef unless $OS eq 'linux';

    my $stat1 = _read_proc_stat();
    return undef unless $stat1;

    select(undef, undef, undef, 0.2);   # 200ms — good balance

    my $stat2 = _read_proc_stat();
    return undef unless $stat2;

    my $diff_user   = $stat2->{user}   - $stat1->{user};
    my $diff_nice   = $stat2->{nice}   - $stat1->{nice};
    my $diff_system = $stat2->{system} - $stat1->{system};
    my $diff_idle   = $stat2->{idle}   - $stat1->{idle};
    my $diff_iowait = $stat2->{iowait} - $stat1->{iowait};

    my $total = $diff_user + $diff_nice + $diff_system + $diff_idle + $diff_iowait;

    return $total > 0 
        ? sprintf("%.1f", 100 * ($diff_user + $diff_nice + $diff_system) / $total) 
        : 0;
}

sub _read_proc_stat {
    open my $fh, '<', '/proc/stat' or return undef;
    my $line = <$fh>;   # first line = aggregate "cpu "
    close $fh;
    return undef unless $line;

    my @fields = split /\s+/, $line;
    return {
        user    => $fields[1] || 0,
        nice    => $fields[2] || 0,
        system  => $fields[3] || 0,
        idle    => $fields[4] || 0,
        iowait  => $fields[5] || 0,
    };
}

sub linux_info {
    my %info;

    %info = (%info, get_memory_swap());
    %info = (%info, get_loadavg());
    %info = (%info, get_disk());
    %info = (%info, get_network_total());
    %info = (%info, get_open_files());
    %info = (%info, get_processes());

    $info{cpu_percent} = get_cpu_percent() // 0;

    if (open my $fh, '<', '/proc/uptime') {
        ($info{uptime}) = split ' ', <$fh>;
        close $fh;
    }

    return \%info;
}

# ===================================================================
# macOS & Windows fallbacks
# ===================================================================

sub darwin_info { return linux_info(); }
sub windows_info { return linux_info(); }

# ===================================================================
# Main Entry Point
# ===================================================================

sub system_info {
    my $coderef = $OS eq 'windows' ? \&windows_info
                : $OS eq 'darwin'  ? \&darwin_info
                : \&linux_info;
    return &{$coderef}();
}

sub pid_info {
   my $pid = shift;
   return $OS eq 'windows' ? windows_pid_info($pid) : linux_pid_info($pid);
}

sub find_pids {
   my $pids = shift || [];
   my (@found, @zombies);

   for my $p (@$pids) {
      my $data = pid_info($p);
      if ($data) {
         push @found, $data;
      } else {
         push @zombies, $p;
      }
   }
   return (\@found, \@zombies);
}

sub linux_pid_info {
   my $pid = shift;
   return unless $pid && $pid =~ /^\d+$/;

   my $ps_cmd = "ps -p $pid -o pid,comm,etime,%cpu,%mem,ppid,priority 2>/dev/null";
   my @output = `$ps_cmd`;
   return unless @output > 1;   # at least header + one line

   # Skip header and find the data line
   foreach my $line (@output) {
      chomp $line;
      next if $line =~ /^\s*PID/ || $line =~ /^\s*$/;

      # More robust regex
      if ($line =~ /^\s*(\d+)\s+(\S+)\s+(\S+)\s+([\d\.]+)\s+([\d\.]+)\s+(\d+)\s+(-?\d+)/) {
         my ($process_id, $process_name, $elapsed_time, $cpu_percent, $mem_percent, $parent_pid, $priority) =
            ($1, $2, $3, $4, $5, $6, $7);

         # Better etime parsing
         my $seconds_elapsed = 0;
         if ($elapsed_time =~ /^(\d+)-(\d{2}):(\d{2}):(\d{2})$/) {
            $seconds_elapsed = $1 * 86400 + $2 * 3600 + $3 * 60 + $4;
         } elsif ($elapsed_time =~ /^(\d{2}):(\d{2}):(\d{2})$/) {
            $seconds_elapsed = $1 * 3600 + $2 * 60 + $3;
         } elsif ($elapsed_time =~ /^(\d+):(\d{2})$/) {
            $seconds_elapsed = $1 * 60 + $2;
         }

         my $start_time = $seconds_elapsed > 0 ? (time - $seconds_elapsed) : "N/A";

         return {
            pid      => $process_id,
            ppid     => $parent_pid,
            priority => $priority,
            fname    => $process_name,
            start    => $start_time,
            pctcpu   => $cpu_percent,
            pctmem   => $mem_percent,
         };
      }
   }

   return;   # not found or parse failed
}


sub windows_pid_info {
   my $pid = shift;
   return unless $pid && $pid =~ /^\d+$/;

   my ($process_id, $process_name, $start_time, $cpu_percent, $mem_percent, $parent_pid, $priority);

   # Get total memory once
   my $total_mem = 0;
   my $mem_cmd = "wmic os get TotalVisibleMemorySize /value 2>nul";
   my @mem_output = `$mem_cmd`;
   foreach my $line (@mem_output) {
      chomp $line;
      if ($line =~ /TotalVisibleMemorySize=(\d+)/) {
         $total_mem = $1 * 1024;
         last;
      }
   }
   $total_mem ||= 1;   # avoid division by zero

   # Get process info
   my $wmic_cmd = "wmic process where ProcessId=$pid get Name,CreationDate,UserModeTime,WorkingSetSize,ParentProcessId,Priority /format:csv 2>nul";
   my @output = `$wmic_cmd`;

   foreach my $line (@output) {
      chomp $line;
      next if $line =~ /^Node,/ || $line =~ /^\s*$/;

      if ($line =~ /[^,]+,([^,]+),(\d{14}\.\d+-\d+),(\d+),(\d+),(\d+),(\d+)/) {
         $process_name = $1;
         $process_id   = $pid;
         my $creation_date = $2;
         my $user_time     = $3 / 10000000;     # 100-nanosecond intervals -> seconds
         my $working_set   = $4;                 # bytes
         $parent_pid       = $5;
         $priority         = $6;

         # Parse CreationDate
         if ($creation_date =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/) {
            my $time_str = "$1-$2-$3 $4:$5:$6";
            eval {
               require Time::Piece;
               my $t = Time::Piece->strptime($time_str, "%Y-%m-%d %H:%M:%S");
               $start_time = $t->epoch;
            };
         }
         $start_time ||= "N/A";

         # Memory %
         $mem_percent = sprintf("%.2f", ($working_set / $total_mem) * 100);

         # CPU % estimate
         if ($start_time ne "N/A") {
            my $elapsed = time - $start_time;
            $cpu_percent = $elapsed > 0 ? sprintf("%.2f", ($user_time / $elapsed) * 100) : "N/A";
         } else {
            $cpu_percent = "N/A";
         }

         return {
            pid      => $process_id,
            ppid     => $parent_pid,
            fname    => $process_name,
            start    => $start_time,
            pctcpu   => $cpu_percent,
            pctmem   => $mem_percent,
         };
      }
   }

   return;   # process not found or parse failed
}

1;
