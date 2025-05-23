#!/usr/bin/env perl

use strict;
use warnings;
use local::lib;
use JSON::PP;
use Proc::ProcessTable;
use AnyEvent;
use AnyEvent::HTTP;
use FindBin       qw($Bin);
use Log::Log4perl qw(:levels);
use App::Daemon   qw( daemonize );
$App::Daemon::logfile  = "$Bin/../logs/sysinfo.log";
$App::Daemon::pidfile  = "$Bin/../logs/sysinfo.pid";
$App::Daemon::loglevel = $DEBUG;

#daemonize();

my $config;

eval {
   open( my $fh, "<", "$Bin/../cc.json" ) or die $!;
   $config = decode_json( do { local $/; <$fh> } );
   close($fh);
};

die "Unable to open config file: $@\n" if $@;

my $api   = $config->{api} || "http://127.0.0.1:3000/api";
my $json  = JSON::PP->new->ascii->pretty->allow_nonref;
my $jarg  = pop @ARGV;
my $args  = $json->decode($jarg) or die "unable to parse json: $!";
my $token = $args->{token}       or die "missing token";
my $id    = $args->{id}          or die "missing server id";
my $pids  = [];

# system info

my ($os) =
    $^O =~ /MSWin32/i ? 'windows'
  : $^O =~ /darwin/i  ? 'darwin'
  :                     'linux';

my $update_payload = sub {

   my $sysinfo =
       $os eq 'windows' ? &windows_info
     : $os eq 'darwin'  ? &darwin_info
     :                    &linux_info;

   my $pid_info = &pid_info($pids);
   return $json->encode( { token => $token, id => $id, command => 'update_sysinfo', %$sysinfo, pids => $pid_info } );
};

# Create event loop
my $cv = AnyEvent->condvar;

# Set up timer for periodic requests
my $timer;
$timer = AnyEvent->timer(
   after    => 0,      # Start immediately
   interval => 4,
   cb       => sub {
      print "Making request to $api at ", scalar(localtime), "\n";

      my $encoded = &$update_payload;
      print "$encoded\n";

      # Make non-blocking HTTP request
      http_post $api, $encoded, sub {
         my ( $body, $hdr ) = @_;
         print "$body\n";
         my $args = decode_json($body) or die "unable to parse json: $!";
         if ( $args->{exit} ) {
            undef $timer;
            exit;
         }
         $pids = $args->{pids};

         if ( $hdr->{Status} =~ /^2/ ) {
            print "Success: $hdr->{Status} $hdr->{Reason}\n";
         }
         else {
            print "Failed: $hdr->{Status} $hdr->{Reason}\n";
         }
      };
   }
);

# Start the event loop
print "Starting event loop...\n";
$cv->recv;

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

   return \%sysinfo;
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

sub pid_info {

   my $pids = shift || [];
   my %pid;
   my $t = Proc::ProcessTable->new;

   foreach my $p ( @{ $t->table } ) {
      $pid{ $p->pid } = {
         pid      => $p->pid,
         tty_dev  => $p->ttydev,
         state    => $p->state,
         start    => $p->start,
         ppid     => $p->ppid,
         priority => $p->priority,
         time     => $p->time,
         ctime    => $p->ctime,
         size     => $p->size,
         rss      => $p->rss,
         wchan    => $p->wchan,
         fname    => $p->fname,
         start    => $p->start,
         pctcpu   => $p->pctcpu,
         pctmem   => $p->pctmem,
      };
   }

   my @p = map { $pid{$_} } grep { exists $pid{$_} } @$pids;
   return \@p;
}

