#!/usr/bin/env perl 

use strict;
use warnings;

use Term::ReadLine::Perl5;
use Mojo::UserAgent;
use POSIX qw(strftime);
use Term::ANSIColor;
use Data::Dumper;
use Getopt::Long qw(GetOptionsFromString);
use JSON;
use FindBin qw($Bin);
use Text::Table::Tiny 1.02 qw/ generate_table /;
use Date::Parse;
use Time::Local;
use DateTime::TimeZone;

use feature qw(say);

my $config = &read_config;

my $tz      = $config->{tz} || DateTime::TimeZone::Local->TimeZone->name;
my $token   = $config->{token};
my $aliases = $config->{aliases};
my $api     = $config->{api};
my $user    = 'offline';
my $cluster = '';

my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(10);
$ua->max_redirects(0)->connect_timeout(3)->request_timeout(5);

my $change_cluster = sub {
   my $json = shift;
   $cluster = $json->{path} || '';
};

my $read_user = sub {
   my $json = shift;
   $user    = $json->{hostname} || 'offline';
   $cluster = $json->{path}     || '';
};

my $update_token = sub {
   my $new_token = shift;
   return { success => 0, message => 'missing token' } unless $new_token;

   $token = $new_token;
   $config->{token} = $token;
   my $success = &write_config($config);

   if ($success) {
      say "Using new token: $token";
   }

   return { success => $success };
};

my $help = sub {
   say <<~'HELP';
      TODO
      cmd1
      cmd2
      cmd3
   HELP
   return { success => 1 };
};

my $top_jobs = sub {
   my $json = shift;
   my $rows = [ [qw(cmndline pid pctcpu pctmem state duration)] ];
   foreach my $j ( @{ $json->{jobs} } ) {
      my $cmd = substr( $j->{cmndline}, 0, 30 ) || $j->{fname} || '';
      my $duration;
      if ( $j->{start} ) {
         my $s       = time - $j->{start};
         my $hours   = int( $s / 3600 );
         my $minutes = int( ( $s % 3600 ) / 60 );
         my $seconds = $s % 60;
         $duration = sprintf( "%.2f h", ( time - $j->{start} ) / 3600 );
      }
      push @$rows, [ $cmd, $j->{pid}, $j->{pctcpu}, $j->{pctmem}, $j->{state}, $duration ];
   }
   say generate_table( rows => $rows, header_row => 1 );
};

my $read_monitor = sub {
   my $json = shift;
   return unless $json->{servers};
   my $rows    = [ [qw(ID ALIAS %MEMORY %DISK LOADAVG PING UPTIME OS UPDATED HOST)] ];
   my @servers = @{ $json->{servers} };
   for my $s (@servers) {
      my ( $cpu, $pmem, $pdisk, $uptime, $ping, $conn, $update );
      if ( $s->{total_memory} ) {
         $pmem = sprintf( "%.2f", ( $s->{used_memory} / $s->{total_memory} ) * 100 );
      }
      if ( $s->{total_disk} ) {
         $pdisk = sprintf( "%.2f", ( $s->{used_disk} / $s->{total_disk} ) * 100 );
      }
      if ( $s->{uptime} ) {
         $uptime = sprintf( "%.2f days", ( $s->{uptime} / 86000 ) );
      }
      if ( $s->{uptime} ) {
         $ping = sprintf( "%.2f ms", $s->{ping} );
      }
      if ( $s->{update_time} ) {
         my $seconds = time - $s->{update_time};
         $update = sprintf( "%is ago", $seconds );
      }
      if ( $s->{cpu} ) {
         my $cores = $s->{cores} || 1;
         $cpu = sprintf( "%.2f (%i)", $s->{cpu}, $cores );
      }

      push @$rows, [ $s->{id}, $s->{name}, $pmem, $pdisk, $cpu, $ping, $uptime, $s->{os}, $update, $s->{hostname} ];
   }
   say generate_table( rows => $rows, header_row => 1 );
};

sub find_cal {
   my $json = shift;
   return unless $json->{cals} && scalar @{ $json->{cals} };
   print "Local time is " . localtime(time) . " $tz\n";
   foreach my $cal ( @{ $json->{cals} } ) {
      my $crows       = [ [qw(ID CALENDAR NEXT_START TIME_ZONE CLUSTER_IDS DESCRIPTION)] ];
      my $cnext       = $cal->{next_start} ? strftime( "%b %d %H:%M:%S", localtime( $cal->{next_start} ) ) : '';
      my $cluster_ids = join( ',', @{ $cal->{cluster_ids} } );
      push @$crows, [ $cal->{id}, $cal->{name}, $cnext, $cal->{tz}, $cluster_ids, $cal->{description} ];
      say generate_table( rows => $crows, header_row => 1, style => 'classic' );
      unless ( scalar @{ $cal->{crons} } ) {
         print "\n";
         next;
      }
      my $rows = [ [qw(ID QUARTZ_CRONTAB NEXT_START BEGIN EXPIRE DESCRIPTION)] ];
      foreach my $cron ( @{ $cal->{crons} } ) {
         my $start = $cron->{begin}      ? strftime( "%b %d %H:%M:%S %Y", localtime( $cron->{begin} ) )      : '';
         my $end   = $cron->{expire}     ? strftime( "%b %d %H:%M:%S %Y", localtime( $cron->{expire} ) )     : 'never';
         my $next  = $cron->{next_start} ? strftime( "%b %d %H:%M:%S %Y", localtime( $cron->{next_start} ) ) : '';
         push @$rows, [ $cron->{id}, $cron->{name}, $next, $start, $end, $cron->{description} ];
      }
      say generate_table( rows => $rows, header_row => 1, style => 'classic' );
      print "\n";
   }
}

sub find_cluster {
   my $json = shift;
   return unless $json->{clusters} && scalar @{ $json->{clusters} };
   print "Local time is " . localtime(time) . " $tz\n";

   my @clusters = @{ $json->{clusters} };
   my %cluster  = map { $_->{id}, $_ } @{ $json->{clusters} };

   my @paths;
   for my $cluster (@clusters) {
      my @parts;
      my $next = $cluster->{id};
      while ($next) {
         unshift @parts, $next;
         $next = $cluster{$next}->{parent_id};
         $next = $next && exists $cluster{$next} ? $next : undef;
      }
      push @paths, \@parts;
   }

   my $rows = [ [qw(ID CLUSTER/JOB STATE NEEDS %MEM %CPU PID SERVER STARTED DURATION NEXT_START CALENDAR)] ];
   foreach my $part (@paths) {
      my $path       = join( '/', ( map { $cluster{$_}->{name} } @{$part} ) );
      my $colored    = colored( $path, 'bold blue' );
      my $cluster_id = pop @{$part} || 0;
      my $c          = $cluster{$cluster_id};
      my $cstate =
          $c->{jobstate} eq 'complete' ? colored( $c->{jobstate}, 'bold green' )
        : $c->{jobstate} eq 'failed'   ? colored( $c->{jobstate}, 'bold red' )
        :                                $c->{jobstate};
      my ( $started, $ended, $duration ) = format_time($c);
      my $needs = join( ',', keys %{ $c->{needs} } );
      my $next  = $c->{next_start} ? strftime( "%b %d %H:%M:%S", localtime( $c->{next_start} ) ) : '';
      push @{$rows}, [ $c->{id}, $colored, $cstate, $needs, '', '', '', '', $started, $duration, $next, $c->{cal} ];

      next unless $cluster{$cluster_id}->{jobs};

      foreach my $j ( @{ $cluster{$cluster_id}->{jobs} } ) {

         my ( $started, $ended, $duration ) = format_time($j);

         my $jstate =
             $j->{jobstate} eq 'complete' ? colored( $j->{jobstate}, 'bold green' )
           : $j->{jobstate} eq 'failed'   ? colored( $j->{jobstate}, 'bold red' )
           :                                $j->{jobstate};

         my $row = [ $j->{id}, "$path/$j->{name}", $jstate, join( ',', keys %{ $j->{needs} } ), $j->{pctmem}, $j->{pctcpu}, $j->{pid}, $j->{server_name}, $started, $duration, '', '' ];

         push @{$rows}, $row;

      }
   }
   say generate_table( rows => $rows, header_row => 1, style => 'classic' );
}

sub format_time {
   my $row = shift;
   my $s   = $row->{started};
   my $e   = $row->{ended};

   return ( '', '', '' ) unless $s;

   my $started = strftime( "%b %d %H:%M:%S", localtime($s) );
   my ( $ended, $end_seconds );

   if ( $row->{jobstate} eq 'running' ) {
      $ended       = '';
      $end_seconds = time;
   }
   else {
      $end_seconds = $e || time;
      $ended       = $e ? strftime( "%b %d %H:%M:%S", localtime($end_seconds) ) : '';
   }

   my $epoch_seconds = $end_seconds - $s;
   my $hours         = int( $epoch_seconds / 3600 );
   my $minutes       = int( ( $epoch_seconds % 3600 ) / 60 );
   my $seconds       = $epoch_seconds % 60;

   my $duration = sprintf( "%02d:%02d:%02d", $hours, $minutes, $seconds );
   return ( $started, $ended, $duration );
}

my $remote_dispatch = {
   change_cluster => $change_cluster,
   read_user      => $read_user,
   find_cluster   => \&find_cluster,
   find_cal       => \&find_cal,
   read_cal       => \&find_cal,
   read_monitor   => $read_monitor,
   top_jobs       => $top_jobs,
};

my $local_dispatch = {
   token        => $update_token,
   update_token => $update_token,
   help         => $help,
};

my $string2hash = sub {
   my $string = shift;
   my %options;

   my ( $ret, $args ) = GetOptionsFromString(
      $string,       \%options,         "command=s",     "token=s",        "state:s",      "username:s",      "hostname:s",     "newname:s",
      "password:s",  "shell_command:s", "email:s",       "level:i",        "cron:s",       "at:s",            "cal:s",          "cal_id:i",
      "force",       "count:i",         "needs:i@",      "description:s",  "server_id:i",  "name:s",          "job_id:i",       "cluster_id:i",
      "server:s",    "org_id:i",        "pid:i",         "id:s",           "match:s",      "tz:s",            "begin:s",        "expire:s",
      "parent_id:i", "retrys:i",        "retry_delay:i", "loops:i",        "loop_delay:i", "fail_hook:i",     "max_duration:i", "max_duration_hook:i",
      "max_cpu:f",   "max_cpu_hook:i",  "max_mem:f",     "max_mem_hook:i", "max_disk:f",   "max_disk_hook:i", "max_load:f",     "max_load_hook:i",
      "max_ping:f",  "max_ping_hook:i", "max_uptime:f",  "max_uptime_hook:i"
   );

   my ( $verb, $noun, $name ) = @{$args};

   return { success => 0, message => 'missing verb' } unless defined $verb;
   unless ( $noun || exists $local_dispatch->{$verb} || exists $aliases->{$verb} ) {
      return { success => 0, message => 'missing noun' };
   }

   my $cmd;

   if ( exists $aliases->{$verb} ) {
      $cmd  = $aliases->{$verb};
      $name = $noun;
   }
   else {
      $cmd =
        $noun
        ? join( '_', ( $verb, $noun ) )
        : $verb;
   }

   # execute local command
   if ( exists $local_dispatch->{$verb} ) {
      my $v = &{ $local_dispatch->{$verb} }($noun);
      return $v;
   }
   elsif ( exists $local_dispatch->{$cmd} ) {
      my $v = &{ $local_dispatch->{$cmd} }($name);
      return $v;
   }

   # execute remote command

   # convert dates to epoch seconds
   foreach my $o (qw(at begin expire)) {
      if ( $options{$o} ) {
         my $seconds = &date_to_epoch( $options{$o} );
         if ($seconds) {
            $options{$o} = $seconds;
         }
         else {
            delete $options{$o};
         }
      }
   }

   if ( $cmd eq 'create_at' ) {
      $name = &date_to_epoch($name);
   }

   $options{tz} ||= $tz;    # time zone needed for crontab
   my $r = { token => $token, command => $cmd, %options };
   $r->{name} = $name if defined $name;
   print Dumper($r);
   return $r;
};

&request("read user");

my $term = Term::ReadLine::Perl5->new('ordo');
while ( defined( my $line = $term->readline("$user:/$cluster> ") ) ) {
   next unless $line;
   &request($line);
}

sub request {
   my $line = shift;
   my $r    = &{$string2hash}($line);
   unless ( $r->{token} ) {

      #say to_json( $r, { pretty => 1 } );
      return;
   }

   my $json;
   eval { $json = $ua->get( $api => { Accept => 'application/json' } => json => $r )->result->json; };
   $json = { success => 0, message => $@ } if $@;
   print to_json( $json, { pretty => 1 } );

   #return unless $json->{success};
   if ( exists $json->{command_reply} && exists $remote_dispatch->{ $json->{command_reply} } ) {
      &{ $remote_dispatch->{ $json->{command_reply} } }($json);
   }
   my $success = $json->{success} ? 'successful' : 'failed';
   print "Command $success. ";
   print ucfirst("$json->{message}.") if $json->{message};
   print "\n\n";
}

sub read_config {
   my $config;
   open( my $fh, "<", "$Bin/../ordo.json" ) or die $!;
   $config = decode_json( do { local $/; <$fh> } );
   close($fh);
   return $config;
}

sub write_config {
   my $config = shift;
   eval {
      open( my $fh, ">", "$Bin/../ordo.json" ) or die $!;
      print $fh to_json( $config, { pretty => 1 } );
      close($fh);
   };
   return $@ ? 0 : 1;
}

sub date_to_epoch {
   my $date = shift;
   my $epoch;
   $epoch = $date =~ /^\d+$/ ? $date : str2time($date);
   $epoch ||= qx/date -d "$date" +%s/;
   chomp($epoch);
   print "EPOCH: $epoch\n";
   return $epoch;
}
