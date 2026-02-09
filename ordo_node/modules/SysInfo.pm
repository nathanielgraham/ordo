package SysInfo;
use strict;
use warnings;
use Exporter 'import';
use IO::Socket::INET;

our @EXPORT = qw(get_local_ip_address get_cores pid_info find_pids system_info);

my ($os) =
    $^O =~ /MSWin32/i ? 'windows'
  : $^O =~ /darwin/i ? 'darwin'
  : 'linux';

sub get_cores {
   my $cores =
       $os eq 'linux' ? get_linux_cores()
     : $os eq 'darwin' ? get_macos_cores()
     : $os eq 'windows' ? get_windows_cores()
     : 1;
   return $cores;
}

sub get_local_ip_address {
    my $socket = IO::Socket::INET->new(
        Proto => 'udp',
        PeerAddr => '198.41.0.4', # a.root-servers.net
        PeerPort => '53',
    );
    return unless $socket;
    my $local_ip = $socket->sockhost;
    $socket->close;
    return $local_ip;
}

# Linux: parse /proc/cpuinfo
sub get_linux_cores {
   my $count = 0;
   open( my $fh, '<', '/proc/cpuinfo' ) or return 1;
   while (<$fh>) {
      $count++ if /^processor\s+:/;
   }
   close $fh;
   return $count || 1;
}

# macOS: sysctl
sub get_macos_cores {
   my $output = `sysctl -n hw.ncpu 2>/dev/null`;
   chomp $output;
   return $output || 1;
}

# Windows: WMIC or fallback
sub get_windows_cores {
   my $output = `wmic cpu get NumberOfLogicalProcessors /value 2>NUL`;
   if ( $output =~ /NumberOfLogicalProcessors=(\d+)/ ) {
      return $1;
   }
   return $ENV{'NUMBER_OF_PROCESSORS'} || 1;
}

# CPU % via top snapshot (internal delta, no state file)
sub get_cpu_percent {
  return undef unless $os eq 'linux';

  my $top = `top -bn1 2>/dev/null`;
  if ($top =~ /%Cpu\(s\):\s*([\d\.]+) us,\s*([\d\.]+) sy/) {
    my $percent = $1 + $2;  # user + system
    return sprintf("%.1f", $percent);
  }
  return undef; # fallback to loadavg
}

# Load averages 1/5/15 min

sub get_loadavg {
  my %load = (load_1 => undef, load_5 => undef, load_15 => undef);

  return %load unless $os eq 'linux';

  open my $fh, '<', '/proc/loadavg' or return %load;
  my $line = <$fh>;
  close $fh;

  return %load unless defined $line && $line =~ /\S/;

  # Trim trailing newline/spaces
  chomp $line;
  $line =~ s/\s+$//;

  # Split on whitespace, take first 3 fields only
  my @fields = split(/\s+/, $line);

  # Validate and assign only if numeric
  $load{load_1}  = $fields[0] =~ /^[\d\.]+$/ ? $fields[0] : undef;
  $load{load_5}  = $fields[1] =~ /^[\d\.]+$/ ? $fields[1] : undef;
  $load{load_15} = $fields[2] =~ /^[\d\.]+$/ ? $fields[2] : undef;

  # Debug (remove later)
  warn "[get_loadavg] Raw line: '$line'" if $ENV{ORDO_DEBUG};
  warn "[get_loadavg] Parsed: load_1=$load{load_1}, load_5=$load{load_5}, load_15=$load{load_15}" if $ENV{ORDO_DEBUG};

  return %load;
}


# Memory + Swap
sub get_memory_swap {
  my %mem = (
    total_memory => undef, used_memory => undef, free_memory => undef,
    total_swap => undef, used_swap => undef, free_swap => undef
  );

  return %mem unless $os eq 'linux';

  open my $fh, '<', '/proc/meminfo' or return %mem;
  while (<$fh>) {
    $mem{total_memory} = $1 * 1024 if /^MemTotal:\s+(\d+)/;
    $mem{free_memory} = $1 * 1024 if /^MemFree:\s+(\d+)/;
    $mem{total_swap} = $1 * 1024 if /^SwapTotal:\s+(\d+)/;
    $mem{free_swap} = $1 * 1024 if /^SwapFree:\s+(\d+)/;
  }
  close $fh;

  $mem{used_memory} = $mem{total_memory} - $mem{free_memory} if $mem{total_memory} && $mem{free_memory};
  $mem{used_swap} = $mem{total_swap} - $mem{free_swap} if $mem{total_swap} && $mem{free_swap};

  return %mem;
}

# Disk (aggregate + root separate)
sub get_disk {
  my %disk = (
    total_disk => undef, used_disk => undef, free_disk => undef,
    root_total_disk => undef, root_used_disk => undef, root_free_disk => undef
  );

  return %disk unless $os eq 'linux';

  # Aggregate
  my @df = `df -lP --total 2>/dev/null`;
  foreach (@df) {
    next unless /^total/;
    my @f = split(/\s+/);
    $disk{total_disk} = $f[1];
    $disk{used_disk} = $f[2];
    $disk{free_disk} = $f[3];
    last;
  }

  # Root only
  my $root = `df -B1 / 2>/dev/null | tail -1`;
  if ($root =~ /\s+(\d+)\s+(\d+)\s+(\d+)/) {
    $disk{root_total_disk} = $1;
    $disk{root_used_disk} = $2;
    $disk{root_free_disk} = $3;
  }

  return %disk;
}

# Network I/O (cumulative total bytes since boot — no delta)
sub get_network_total {
  my %net = (net_rx_bytes => 0, net_tx_bytes => 0);

  return %net unless $os eq 'linux';

  open my $fh, '<', '/proc/net/dev' or return %net;
  while (<$fh>) {
    next if /^Inter|^ face/;
    my @f = split(/\s+/);
    $net{net_rx_bytes} += $f[1] if $f[1] =~ /^\d+$/; # bytes received
    $net{net_tx_bytes} += $f[9] if $f[9] =~ /^\d+$/; # bytes transmitted
  }
  close $fh;

  return %net;
}

# Open file handles / max
sub get_open_files {
  my %files = (open_files => undef, max_files => undef);

  return %files unless $os eq 'linux';

  open my $fh, '<', '/proc/sys/fs/file-nr' or return %files;
  my $line = <$fh>;
  close $fh;

  my ($allocated, $unused, $max) = split(/\s+/, $line);
  $files{open_files} = $allocated;
  $files{max_files} = $max;

  return %files;
}

# Process count (total / zombies)
sub get_processes {
  my %proc = (total_processes => undef, zombie_processes => undef);

  return %proc unless $os eq 'linux';

  # Total
  my $total = `ps -e | wc -l`;
  chomp $total;
  $proc{total_processes} = $total - 1; # subtract header

  # Zombies
  my $zombies = `ps -eo stat | grep -c '^Z'`;
  chomp $zombies;
  $proc{zombie_processes} = $zombies;

  return %proc;
}

# Enhanced linux_info (combines all)
sub linux_info {
  my %sysinfo;

  # Memory + Swap
  %sysinfo = (%sysinfo, get_memory_swap());

  # CPU %
  $sysinfo{cpu_percent} = get_cpu_percent() // 0;

  # Loadavg
  my %load = get_loadavg();
  %sysinfo = (%sysinfo, %load);

  # Disk
  %sysinfo = (%sysinfo, get_disk());

  # Network (cumulative)
  %sysinfo = (%sysinfo, get_network_total());

  # Open files
  %sysinfo = (%sysinfo, get_open_files());

  # Processes
  %sysinfo = (%sysinfo, get_processes());

  # Uptime
  open my $fh, '<', '/proc/uptime' or return \%sysinfo;
  ($sysinfo{uptime}) = split ' ', <$fh>;
  close $fh;

  return \%sysinfo;
}

# Stubs for macOS/Windows (minimal)
sub darwin_info { return linux_info(); } # fallback
sub windows_info { return linux_info(); } # fallback

sub system_info {
  my $coderef = $os eq 'windows' ? \&windows_info
              : $os eq 'darwin' ? \&darwin_info
              : \&linux_info;
  return &{$coderef};
}

sub pid_info {
   my $pid = shift;
   my $coderef = $os eq 'windows'  ? \&windows_pid_info : \&linux_pid_info;
   return &{ $coderef }($pid);
}

sub find_pids {
   my $pids = shift;
   my %pid;
   my (@found, @zombies);

   for my $p (@{ $pids }) {
      my $pid_data = &pid_info($p);
      if ($pid_data) {
         push @found, $pid_data;
      }
      else {
         push @zombies, $p;
      }
   }
   return ( \@found, \@zombies );
}

sub linux_pid_info {
   my $pid = shift;

   my ( $process_id, $process_name, $start_time, $cpu_percent, $mem_percent, $parent_pid, $priority);

   # Unix-like: Use ps command
   my $ps_cmd = "ps -p $pid -o pid,comm,etime,%cpu,%mem,ppid,priority";
   #my $ps_cmd = "ps -p $pid -o pid,comm,etime,%cpu,%mem,ppid";
   my @output = `$ps_cmd 2>/dev/null`;
   my $found  = 0;

   foreach my $line (@output) {
      chomp $line;

      # Skip header line
      next if $line =~ /^\s*PID/;

      # Example output: " 1234 firefox 1-02:34:56  2.5  3.2  789"
      #if ( $line =~ /^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+)/ ) {
      if ($line =~ /^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+)\s+(-?\d+)/) {

         $process_id   = $1;
         $process_name = $2;
         my $elapsed_time = $3;
         $cpu_percent = $4;
         $mem_percent = $5;
         $parent_pid  = $6;
         $priority = $7;

         # Calculate start time in epoch seconds
         my $current_time    = time;
         my $seconds_elapsed = 0;

         # Parse etime: DD-HH:MM:SS, HH:MM:SS, or MM:SS
         if ( $elapsed_time =~ /^(\d+)-(\d{2}):(\d{2}):(\d{2})$/ ) {
            my ( $days, $hours, $minutes, $seconds ) = ( $1, $2, $3, $4 );
            $seconds_elapsed = $days * 86400 + $hours * 3600 + $minutes * 60 + $seconds;
         }
         elsif ( $elapsed_time =~ /^(\d{2}):(\d{2}):(\d{2})$/ ) {
            my ( $hours, $minutes, $seconds ) = ( $1, $2, $3 );
            $seconds_elapsed = $hours * 3600 + $minutes * 60 + $seconds;
         }
         elsif ( $elapsed_time =~ /^(\d+):(\d{2})$/ ) {
            my ( $minutes, $seconds ) = ( $1, $2 );
            $seconds_elapsed = $minutes * 60 + $seconds;
         }
         else {
            $start_time = "N/A";
         }

         if ( $seconds_elapsed > 0 ) {
            $start_time = $current_time - $seconds_elapsed;
         }
         else {
            $start_time = "N/A";
         }
         $found = 1;
         last;
      }
   }
   return unless defined $process_id;
   return { pid => $process_id, ppid => $parent_pid, priority => $priority, fname => $process_name, start => $start_time, pctcpu => $cpu_percent, pctmem => $mem_percent };
}

sub windows_pid_info {
   my $pid = shift;

   #my ( $process_id, $process_name, $start_time, $cpu_percent, $mem_percent, $parent_pid );
   my ($process_id, $process_name, $start_time, $cpu_percent, $mem_percent, $parent_pid, $priority);


   my $total_mem;

   my $mem_cmd = "wmic os get TotalVisibleMemorySize /value";
   my @mem_output = `$mem_cmd 2>nul`;
   foreach my $mem_line (@mem_output) {
       chomp $mem_line;
       if ($mem_line =~ /TotalVisibleMemorySize=(\d+)/) {
           $total_mem = $1 * 1024; # Convert KB to bytes
           last;
       }
   }
   $total_mem ||= 1; # Avoid division by zero

   # Windows: Use wmic to get process info
   my $wmic_cmd = "wmic process where ProcessId=$pid get Name,CreationDate,UserModeTime,WorkingSetSize,ParentProcessId,Priority /format:csv";
   #my $wmic_cmd = "wmic process where ProcessId=$pid get Name,CreationDate,UserModeTime,WorkingSetSize,ParentProcessId /format:csv";
   my @output   = `$wmic_cmd 2>nul`;
   my $found    = 0;

   foreach my $line (@output) {
      chomp $line;

      # Skip header or empty lines
      next if $line =~ /^Node,/ || $line =~ /^\s*$/;


      # Example output: "Node,Name,CreationDate,UserModeTime,WorkingSetSize,ParentProcessId"
      # "DESKTOP-XYZ,notepad.exe,20250825140723.123456-300,156250,5432000,789"

      if ($line =~ /[^,]+,([^,]+),(\d{14}\.\d+-\d+),(\d+),(\d+),(\d+),(\d+)/) {
         $process_name = $1;
         $process_id = $pid;
         my $creation_date = $2;
         my $user_time = $3 / 10000000; # Convert 100-nanosecond intervals to seconds
         my $working_set = $4; # Memory in bytes
         $parent_pid = $5;
         $priority = $6;

         # Convert CreationDate (YYYYMMDDHHMMSS.ssssss-TZ) to epoch seconds
         if ( $creation_date =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.\d+-(\d+)/ ) {
            my ( $year, $month, $day, $hour, $min, $sec, $tz_offset ) = ( $1, $2, $3, $4, $5, $6, $7 );
            my $time_str = "$year-$month-$day $hour:$min:$sec";
            my $time     = Time::Piece->strptime( $time_str, "%Y-%m-%d %H:%M:%S" );
            $start_time = $time->epoch - ( $tz_offset * 60 );    # Adjust for timezone offset
         }
         else {
            $start_time = "N/A";
         }

         # Calculate memory usage percentage
         $mem_percent = sprintf( "%.2f", ( $working_set / $total_mem ) * 100 );

         # Estimate CPU usage (user time / elapsed time)
         if ( $start_time ne "N/A" ) {
            my $elapsed = time - $start_time;
            $cpu_percent = $elapsed > 0 ? sprintf( "%.2f", ( $user_time / $elapsed ) * 100 ) : "N/A";
         }
         else {
            $cpu_percent = "N/A";
         }

         $found = 1;
         last;
      }
   }

   return unless $process_id;
   return { pid => $process_id, ppid => $parent_pid, fname => $process_name, start => $start_time, pctcpu => $cpu_percent, pctmem => $mem_percent };
}

1;
