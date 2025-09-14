package SysInfo;

use strict;
use warnings;
use Exporter 'import';
use IO::Socket::INET;

# Functions to export
our @EXPORT = qw(get_local_ip_address get_cores pid_info find_pids system_info);

my ($os) =
    $^O =~ /MSWin32/i ? 'windows'
  : $^O =~ /darwin/i  ? 'darwin'
  :                     'linux';

sub get_cores {
   my $cores =
       $os eq 'linux'   ? get_linux_cores()
     : $os eq 'darwin'  ? get_macos_cores()
     : $os eq 'windows' ? get_windows_cores()
     :                    1;

   return $cores;
}

sub get_local_ip_address {
    my $socket = IO::Socket::INET->new(
        Proto    => 'udp',
        PeerAddr => '198.41.0.4',  # a.root-servers.net
        PeerPort => '53',
    );

    return unless $socket;
    my $local_ip = $socket->sockhost;
    $socket->close;
    return $local_ip;
}

# -------------------------
# Linux: parse /proc/cpuinfo
sub get_linux_cores {
   my $count = 0;
   open( my $fh, '<', '/proc/cpuinfo' ) or die "Can't open /proc/cpuinfo: $!";
   while (<$fh>) {
      $count++ if /^processor\s+:/;

   }
   close $fh;
   return $count;
}

# -------------------------
# macOS: sysctl
sub get_macos_cores {
   my $output = `sysctl -n hw.ncpu`;
   chomp $output;
   return $output;
}

# -------------------------
# Windows: WMIC or fallback to ENV
sub get_windows_cores {
   my $output = `wmic cpu get NumberOfLogicalProcessors /value 2>NUL`;
   if ( $output =~ /NumberOfLogicalProcessors=(\d+)/ ) {
      return $1;
   }
   else {
      # Fallback (not always reliable)
      return $ENV{'NUMBER_OF_PROCESSORS'} || 'Unknown';
   }
}

sub windows_info {
   my %sysinfo;

   # Memory
   my $wmic = `wmic OS get TotalVisibleMemorySize,FreePhysicalMemory /Value`;
   if ( $wmic =~ /FreePhysicalMemory=(\d+)/ ) {
      $sysinfo{free_memory} = $1 / 1024;    # Convert KB to MB
   }
   if ( $wmic =~ /TotalVisibleMemorySize=(\d+)/ ) {
      $sysinfo{total_memory} = $1 / 1024;    # Convert KB to MB
   }
   if ( $sysinfo{total_memory} && $sysinfo{free_memory} ) {
      $sysinfo{used_memory} = $sysinfo{total_memory} - $sysinfo{free_memory};
   }

   # CPU
   #my @output = `wmic cpu get loadpercentage`;
   my $load = `wmic cpu get LoadPercentage /Value`;
   if ( $load =~ /LoadPercentage=(\d+)/ ) {
      $sysinfo{cpu} = $1;
   }

   # Uptime
   my $output = `wmic os get LastBootUpTime /value`;
   my ($boot_time_str) = $output =~ /LastBootUpTime=(\d{14})/;

   if ($boot_time_str) {
      my ( $year, $month, $day, $hour, $min, $sec ) = $boot_time_str =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/;
      use Time::Local;
      my $boot_epoch     = timegm( $sec, $min, $hour, $day, $month - 1, $year );
      my $uptime_seconds = time() - $boot_epoch;
      $sysinfo{uptime} = $uptime_seconds;
   }

   # Disk usage
   my @output = `wmic logicaldisk get size,freespace,caption`;
   shift @output;
   my @results;

   foreach my $line (@output) {
      next if $line =~ /^\s*$/;
      my ( $drive, $free, $total ) = $line =~ /([A-Z]:)\s+(\d+)\s+(\d+)/;
      next unless defined $drive;
      my $used = $total - $free;
      $sysinfo{total_disk} = $total;
      $sysinfo{used_disk}  = $used;
      $sysinfo{free_disk}  = $free;
      last;
   }
   return \%sysinfo;
}

sub darwin_info {    # Mac

   my %sysinfo;

   # Memory
   my $sysctl = `sysctl hw.memsize`;
   if ( $sysctl =~ /hw.memsize: (\d+)/ ) {
      $sysinfo{total_memory} = $1;
   }
   my $vm_stat    = `vm_stat`;
   my $pages_free = 0;
   if ( $vm_stat =~ /Pages free:\s+(\d+)/ ) {
      $pages_free = $1;
   }

   my $page_size = `sysctl vm.pagesize` =~ /vm.pagesize: (\d+)/ ? $1 : 4096;
   $sysinfo{free_memory} = ( $pages_free * $page_size );
   if ( $sysinfo{total_memory} && $sysinfo{free_memory} ) {
      $sysinfo{used_memory} = $sysinfo{total_memory} - $sysinfo{free_memory};
   }

   # CPU
   my $top = `top -l 1 | grep "CPU usage"`;
   if ( $top =~ /CPU usage: (\d+\.\d+)% user, (\d+\.\d+)% sys/ ) {
      $sysinfo{cpu} = $1 + $2;
   }

   # Uptime
   my $boot_time = `sysctl -n kern.boottime`;
   if ( $boot_time =~ /sec = (\d+)/ ) {
      my $boot_epoch     = $1;
      my $uptime_seconds = time() - $boot_epoch;
      $sysinfo{uptime} = $uptime_seconds;
   }

   # Disk
   my $disk_info = &linux_disk;
   return { %sysinfo, %$disk_info };

}

sub linux_info {    # Linux probably

   my %sysinfo;

   # Memory
   my $meminfo = `free -b 2>/dev/null`;    # use -b for bytes
   my @lines   = split "\n", $meminfo;

   foreach my $line (@lines) {
      if ( $line =~ /^Mem:\s+(\d+)\s+(\d+)\s+(\d+)/ ) {
         $sysinfo{total_memory} = $1;
         $sysinfo{used_memory}  = $2;
         $sysinfo{free_memory}  = $3;
         last;
      }
   }

   # CPU
   if ( open my $fh, '<', '/proc/loadavg' ) {
      my $line  = <$fh>;
      my @loads = split( /\s+/, $line );
      $sysinfo{cpu} = $loads[0];    # 1 minute load average
   }

   # Disk
   my $disk_info = &linux_disk;

   # Uptime
   open my $fh, '<', '/proc/uptime' or return "Cannot open /proc/uptime: $!";
   my $line = <$fh>;
   close $fh;
   my ($uptime_seconds) = split ' ', $line;
   $sysinfo{uptime} = $uptime_seconds;

   return { %sysinfo, %$disk_info };
}

sub linux_disk {
   my %sysinfo;
   my @output = `df -lP --total`;

   foreach my $line (@output) {
      next unless $line =~ /^\s*total/;
      my @fields = split( /\s+/, $line );
      $sysinfo{total_disk} = $fields[1];
      $sysinfo{used_disk}  = $fields[2];
      $sysinfo{free_disk}  = $fields[3];
   }
   return \%sysinfo;
}

sub system_info {
   my $coderef = $os eq 'windows' ? \&windows_info
               : $os eq 'darwin'  ? \&darwin_info
               : \&linux_info;

   return &{ $coderef };
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
