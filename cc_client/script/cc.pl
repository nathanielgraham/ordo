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
use MIME::Base64;
use Term::ReadKey;

use feature qw(say);

my $config = &read_config;

my $tz      = $config->{tz} || DateTime::TimeZone::Local->TimeZone->name;
my $token   = $config->{token};
my $aliases = $config->{aliases};
my $api     = $config->{api};
my $user    = 'offline';
my $cluster = '';

my $term = Term::ReadLine::Perl5->new('ordo');
my $ua   = Mojo::UserAgent->new;
$ua->inactivity_timeout(10);
$ua->max_redirects(0)->connect_timeout(3)->request_timeout(5);

my $rv = &request("read user");

#die "Invalid token\n" unless $rv->{success};

# main loop
while ( defined( my $line = $term->readline("$user:/$cluster> ") ) ) {
   next unless $line;
   my $json = &request($line);

   #print to_json( $json, { pretty => 1 } );

   my $success = $json->{success} ? 'successful' : 'failed';
   print "Command $success. ";
   print ucfirst("$json->{message}.") if $json->{message};
   print "\n\n";
}

sub change_cluster {
   my $json = shift;
   $cluster = $json->{path} || '';
}

sub read_user {
   my $json = shift;
   $user    = $json->{hostname} || 'offline';
   $cluster = $json->{path}     || '';
}

sub update_token {
   my $new_token = shift;
   return { success => 0, message => 'missing token' } unless $new_token;

   $token = $new_token;
   $config->{token} = $token;
   my $success = &write_config($config);

   if ($success) {
      say "Using new token: $token";
   }

   return { success => $success };
}

sub help {
   say <<~'HELP';
      TODO
      cmd1
      cmd2
      cmd3
   HELP
   return { success => 1 };
}

sub read_job {
   my $json = shift;
   print Dumper($json);
}

sub read_cluster {
   my $json = shift;
   print Dumper($json);
}

sub read_monitor {
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
}

sub find_log {
   my $json = shift;
   return unless $json && $json->{success} && $json->{logs};
   print "\nJob history for $json->{path}/$json->{name}\n";
   my $rows    = [ [qw(ID JOB_ID PID STARTED ENDED EXIT_CODE SIGNAL)] ];
   foreach my $l (@{ $json->{logs} }) {
      my $started = $l->{started} ? strftime( "%b %d %H:%M:%S", localtime($l->{started}) ) : '';
      my $ended = $l->{ended} ? strftime( "%b %d %H:%M:%S", localtime($l->{ended}) ) : '';
      push @$rows, [ $l->{id}, $l->{job_id}, $l->{pid}, $started, $ended, $l->{exit_code}, $l->{signal} ];
   }
   say generate_table( rows => $rows, header_row => 1 );
   #print Dumper($json);
}

sub read_log {
   my $json = shift;
   return unless $json && $json->{err} && $json->{out};

   my $joined = $json->{out} . $json->{err};

   ReadMode('raw');
   if ( $^O =~ /MSWin32/i ) {
      print $joined;
   }
   else {
      &less($joined);
      #system("echo '$joined' | less");
   }
   ReadMode('normal');
}

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

   my $rows = [ [qw(ID CLUSTER/JOB STATE NEEDS %MEM %CPU PID SERVER LAST_START DURATION NEXT_START CALENDAR)] ];
   foreach my $part (@paths) {
      my $path       = join( '/', ( map { $cluster{$_}->{name} } @{$part} ) );
      my $colored    = colored( $path, 'bold blue' );
      my $cluster_id = pop @{$part} || 0;
      my $c          = $cluster{$cluster_id};
      my $credo      = $c->{retry_count} || $c->{loop_count};

      my $cstate =
          scalar( grep { $c->{jobstate} eq $_ } (qw(complete ice)) )                   ? colored( $c->{jobstate}, 'bold green' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(failed zombie killed hold)) )      ? colored( $c->{jobstate}, 'bold red' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(running)) )                        ? colored( $c->{jobstate}, 'bold magenta' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(ready waiting looping retrying)) ) ? colored( $c->{jobstate}, 'bold yellow' )
        :                                                                                $c->{jobstate};

      $cstate .= "($credo)" if $credo;
      my ( $started, $ended, $duration ) = format_time($c);
      my $needs = join( ',', keys %{ $c->{needs} } );

      #my $clast = $c->{started} ? strftime( "%b %d %H:%M:%S", localtime( $c->{started} ) ) : '';
      my $ctminus = &epoch_to_tminus( $c->{next_start} );
      my $ctplus  = &epoch_to_tminus( $c->{started} );
      my $cdur    = &epoch_to_duration( $c->{started}, $c->{ended} || time );

      push @{$rows}, [ $c->{id}, $colored, $cstate, $needs, '', '', '', '', $ctplus, $cdur, $ctminus, $c->{cal_id} ];

      next unless $cluster{$cluster_id}->{jobs};

      foreach my $j ( @{ $cluster{$cluster_id}->{jobs} } ) {

         #my $jlast = $j->{started} ? strftime( "%b %d %H:%M:%S", localtime( $j->{started} ) ) : '';
         my $jtminus = &epoch_to_tminus( $j->{next_start} );
         my $jtplus  = &epoch_to_tminus( $j->{started} );
         my $jdur    = &epoch_to_duration( $j->{started}, $j->{ended} || time );

         my ( $started, $ended, $duration ) = format_time($j);

         my $redo = $j->{retry_count} || $j->{loop_count};

         my $jstate =
             scalar( grep { $j->{jobstate} eq $_ } (qw(complete ice)) )                   ? colored( $j->{jobstate}, 'bold green' )
           : scalar( grep { $j->{jobstate} eq $_ } (qw(failed zombie killed hold)) )      ? colored( $j->{jobstate}, 'bold red' )
           : scalar( grep { $j->{jobstate} eq $_ } (qw(running)) )                        ? colored( $j->{jobstate}, 'bold magenta' )
           : scalar( grep { $j->{jobstate} eq $_ } (qw(ready waiting looping retrying)) ) ? colored( $j->{jobstate}, 'bold yellow' )
           :                                                                                $j->{jobstate};

         $jstate .= "($redo)" if $redo;

         my $row = [ $j->{id}, "$path/$j->{name}", $jstate, join( ',', keys %{ $j->{needs} } ), $j->{pctmem}, $j->{pctcpu}, $j->{pid}, $j->{server_name}, $jtplus, $duration, '', '' ];

         push @{$rows}, $row;

      }
   }
   say generate_table( rows => $rows, header_row => 1, style => 'classic' );
}

sub epoch_to_tminus {
   my $epoch = shift;

   return unless $epoch && $epoch =~ /^\d+$/;

   my $current_epoch = time;
   my $sign          = $epoch > $current_epoch ? '-' : '+';

   my $duration = &epoch_to_duration( $current_epoch, $epoch );

   return "T$sign$duration";
}

sub epoch_to_duration {
   my ( $start, $end ) = @_;
   return unless $start && $end;
   my $diff_seconds = abs( $end - $start );

   # Convert to days, hours, minutes, seconds
   my $days = int( $diff_seconds / ( 24 * 60 * 60 ) );
   $diff_seconds %= ( 24 * 60 * 60 );
   my $hours = int( $diff_seconds / ( 60 * 60 ) );
   $diff_seconds %= ( 60 * 60 );
   my $minutes  = int( $diff_seconds / 60 );
   my $seconds  = $diff_seconds % 60;
   my $duration = sprintf( "%02d:%02d:%02d", $hours, $minutes, $seconds );

   if ($days) {
      $duration .= " +$days" . 'd';
   }
   return $duration;
}

sub format_time {
   my $opt = shift;
   my $s   = $opt->{started};
   my $e   = $opt->{ended};

   return ( '', '', '' ) unless $s;

   my $started = strftime( "%b %d %H:%M:%S", localtime($s) );
   my ( $ended, $end_seconds );

   if ( $opt->{jobstate} eq 'running' ) {
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

sub remote_dispatch {
   my ( $command, $json ) = @_;

   my %dispatch = (
      change_cluster => \&change_cluster,
      read_user      => \&read_user,
      find_cluster   => \&find_cluster,
      read_job       => \&read_job,
      read_cluster   => \&read_cluster,
      find_cal       => \&find_cal,
      read_cal       => \&find_cal,
      find_log       => \&find_log,
      read_log       => \&read_log,
      read_monitor   => \&read_monitor,
   );

   &{ $dispatch{$command} }($json) if exists( $dispatch{$command} );
}

my $local_dispatch = {
   token        => \&update_token,
   update_token => \&update_token,
   help         => \&help,
};

sub string2hash {
   my $string = shift;
   my %options;

   my ($cmds) = $string =~ /(.*?)(-.*)?$/;
   my ($opts) = $string =~ /(-.*$)/;
   my ( $verb, $noun, $name ) = ( split( /\s+/, $cmds ) )[ 0 .. 2 ];

   if ($opts) {

      my ( $ret, $args ) = GetOptionsFromString(
         $opts,         \%options,         "command=s",     "token=s",           "state:s",      "username:s",      "hostname:s",     "newname:s",
         "password:s",  "shell_command:s", "email:s",       "level:i",           "cron:s",       "at:s",            "cal:s",          "cal_id:i",
         "force",       "count:i",         "needs:i@",      "description:s",     "server_id:i",  "name:s",          "job_id:i",       "cluster_id:i",
         "server:s",    "org_id:i",        "pid:i",         "id:s",              "match:s",      "tz:s",            "begin:s",        "expire:s",
         "parent_id:i", "retrys:i",        "retry_delay:i", "loops:i",           "loop_delay:i", "fail_hook:i",     "max_duration:i", "max_duration_hook:i",
         "max_cpu:f",   "max_cpu_hook:i",  "max_mem:f",     "max_mem_hook:i",    "max_disk:f",   "max_disk_hook:i", "max_load:f",     "max_load_hook:i",
         "max_ping:f",  "max_ping_hook:i", "max_uptime:f",  "max_uptime_hook:i", "mode:i",       "forkable",        "log:i"
      );

      # allow multi-value needs

      if ( $opts =~ /needs/ ) {
         my @needs;
         $opts =~ s/^.*?(-needs.*$)/$1/;
         $opts =~ s/(.*?needs[^-]*?)-.*/$1/;
         GetOptionsFromString( $opts, 'needs:i{,}' => \@needs );
         $options{needs} = \@needs if scalar @needs && scalar @needs > scalar @{ $options{needs} };
      }
   }

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

   $options{tz} ||= $tz;    # time zone needed for crontab
   my $r = { token => $token, command => $cmd, %options };
   $r->{name} = $name if defined $name;
   return $r;
}

sub request {
   my $line = shift;
   my $r    = &string2hash($line);
   return unless $r->{token};

   my $json;
   eval { $json = $ua->get( $api => { Accept => 'application/json' } => json => $r )->result->json; };
   $json = { success => 0, message => $@ } if $@;

   if ( exists $json->{command_reply} ) {
      &remote_dispatch( $json->{command_reply}, $json );
   }

   return $json;
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

sub less {
   my $string = shift;
   my @lines = split( /\n/, $string );
   $_ .= "\n" for @lines;

   # Get terminal size (rows)
   my ( $term_width, $term_height ) = GetTerminalSize();
   $term_height = $term_height - 1;    # Reserve one line for prompt

   # Initialize variables
   my $start_line  = 0;                # Starting line for the current page
   my $total_lines = @lines;

   # If file fits on one screen, print it and exit
   if ($total_lines <= $term_height) {
     print $_ for @lines;
     return;
   }

   # Enable raw mode for key input
   ReadMode('cbreak');

   # Main loop
   while (1) {

      # Clear the screen (portable way)
      system( $^O eq 'MSWin32' ? 'cls' : 'clear' );

      # Display lines for the current page
      for my $i ( $start_line .. $start_line + $term_height - 1 ) {
         last if $i >= $total_lines;
         print $lines[$i];
      }

      # Show prompt
      print ": (q to quit, space for next page, b for previous page) ";

      # Read a single key
      my $key = ReadKey(0);

      # Process key commands
      if ( $key eq 'q' ) {
         last;    # Quit
      }
      elsif ( $key eq ' ' ) {

         # Move to next page
         $start_line += $term_height if $start_line + $term_height < $total_lines;
      }
      elsif ( $key eq 'b' ) {

         # Move to previous page
         $start_line -= $term_height if $start_line > 0;
      }
   }

   # Restore terminal mode and clear screen
   ReadMode('restore');
   #system( $^O eq 'MSWin32' ? 'cls' : 'clear' );
}
