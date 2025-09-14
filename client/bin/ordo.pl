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

#use MIME::Base64;
use Term::ReadKey;
use POSIX qw(ceil);

use feature qw(say);

my $config = &read_config;

my $tz      = $config->{tz} || DateTime::TimeZone::Local->TimeZone->name;
my $token   = $config->{token};
my $aliases = $config->{aliases};
my $api     = $config->{api};

#$api = "http://localhost:3000/api";
#$api = "https://192.168.68.56/api";
#my $api     = "https://127.0.0.1/api";
my $host    = '';
my $cluster = '';

my $term = Term::ReadLine::Perl5->new('ordo');
my $ua   = Mojo::UserAgent->new(
   ssl_opts => {

      #ca => ['/etc/nginx/ssl/nginx-selfsigned.crt'],
      #ca => ['/etc/nginx/ssl/dhparam.pem'],
      #insecure => 1
   }
);

$ua->inactivity_timeout(10);
$ua->max_redirects(0)->connect_timeout(4)->request_timeout(7);

my $login = &request("login user");

if ( $login->{success} ) {
   if ( $login->{level} == 0 ) {
      say "Already registered and awaiting confirmation. Try again later.";
      exit;
   }
   &request("find cluster");
}
else {
   say $login->{message} if $login->{message};

   #exit;
}

# main loop
while ( defined( my $line = $term->readline("$host:/$cluster> ") ) ) {
   next unless $line;
   print "\n";
   my $json = &request($line);

   #print to_json( $json, { pretty => 1 } );

   my $success = $json->{success} ? 'successful' : 'failed';
   print "Command $success. ";
   print ucfirst("$json->{message}") if $json->{message};
   print "\n\n";
}

sub change_cluster {
   my $json = shift;
   if ( $json && $json->{success} ) {
      $cluster = $json->{path};
   }
}

sub login_user {
   my $json = shift;
   return unless $json && $json->{token};

   #print Dumper($json);
   &new_token($json);
   $host    = $json->{host} || '';
   $cluster = $json->{path} || '';
}

sub _print_table {
   my $json = shift;
   return unless $json && ref $json eq 'HASH';

   #my $success = delete $json->{success};
   return unless $json->{success};
   my $rows = [ [qw(key value)] ];
   for my $k ( sort { $a cmp $b } keys %{$json} ) {
      next if $k eq 'success';
      my $row =
          ref $json->{$k} eq 'ARRAY' ? join( ' ', map { $_->{id} } @{ $json->{$k} } )
        : ref $json->{$k} eq 'HASH'  ? join( ' ', keys %{ $json->{$k} } )
        :                              $json->{$k};
      push @$rows, [ $k, $row ];
   }

   &less( generate_table( rows => $rows, header_row => 1 ) );

   #ReadMode('normal');
}

sub read_user {
   my $json = shift;
   &_print_table($json);
}

sub new_token {
   my $json = shift;

   #return { success => 0 } unless $json && $json->{token};
   return unless $json && $json->{token};

   $config->{token} = $json->{token};
   $token = $json->{token};

   my $success = &write_config($config);

   if ($success) {
      say "Using token: $json->{token}";
   }
}

sub create_monitor {
   my $json = shift;
   if ( $json->{exit_code} ) {
      print "Enter the password: ";
      ReadMode 'noecho';
      my $password = ReadLine(0);
      chomp $password;
      ReadMode 'normal';
      delete $json->{success};
      delete $json->{message};
      $json->{command}  = delete $json->{command_reply};
      $json->{password} = $password;
      $json->{token}    = $token;
      &send_request($json);
   }
}

sub help {
   my $json = shift;
   print Dumper($json);
}

sub read_job {
   my $json = shift;
   &_print_table($json);
}

sub read_cluster {
   my $json = shift;
   &_print_table($json);
}

sub find_monitor {
   my $json = shift;
   return unless $json->{servers};
   my $rows    = [ [qw(ID ALIAS %MEMORY %DISK LOADAVG PING UPTIME OS UPDATED USER@HOST)] ];
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
      if ( exists $s->{cpu} ) {
         my $cores = $s->{cores} || 1;
         $cpu = sprintf( "%.2f (%i)", $s->{cpu}, $cores );
      }

      push @$rows, [ $s->{id}, $s->{name}, $pmem, $pdisk, $cpu, $ping, $uptime, $s->{os}, $update, $s->{user} . '@' . $s->{host} ];
   }
   say generate_table( rows => $rows, header_row => 1 );
}

sub find_log {
   my $json = shift;
   return unless $json && $json->{success} && $json->{logs};
   print "\nJob history for $json->{path}/$json->{name}\n";
   my $rows = [ [qw(ID JOB_ID PID STARTED ENDED EXIT_CODE SIGNAL)] ];
   foreach my $l ( @{ $json->{logs} } ) {
      my $started = $l->{started} ? strftime( "%b %d %H:%M:%S", localtime( $l->{started} ) ) : '';
      my $ended   = $l->{ended}   ? strftime( "%b %d %H:%M:%S", localtime( $l->{ended} ) )   : '';
      push @$rows, [ $l->{id}, $l->{job_id}, $l->{pid}, $started, $ended, $l->{exit_code}, $l->{signal} ];
   }
   say generate_table( rows => $rows, header_row => 1 );
}

sub read_log {
   my $json = shift;
   return unless $json && $json->{out};

   #ReadMode('raw');
   &less( $json->{out} );
   #ReadMode('normal');
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

         #print "\n";
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

   my $path_padding = ' ';

   my $rows = [ [qw(ID CLUSTER/JOB STATE SERVER NEEDS %MEM %CPU PID LAST_START DURATION NEXT_START CALENDAR)] ];
   foreach my $i ( 0 .. $#paths ) {
      my @parts      = @{ $paths[$i] };
      my $cluster_id = $parts[$#parts];

      unless ( $i == 0 ) {
         shift @parts;
      }
      my $path = join( '/', ( map { $cluster{$_}->{name} } @parts ) );

      #my $blue_path;
      if ( $i == 0 ) {
         $path .= '/';
      }
      else {
         $path = $path_padding . $path;
      }
      my $blue_path = colored( $path, 'bold blue' );

      my $c     = $cluster{$cluster_id};
      my $credo = $c->{retry_count} || $c->{loop_count};

      my $cstate =
          scalar( grep { $c->{jobstate} eq $_ } (qw(complete ice pruned)) )            ? colored( $c->{jobstate}, 'bold green' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(failed zombie killed hold)) )      ? colored( $c->{jobstate}, 'bold red' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(running)) )                        ? colored( $c->{jobstate}, 'bold magenta' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(immutable)) )                      ? colored( $c->{jobstate}, 'bold cyan' )
        : scalar( grep { $c->{jobstate} eq $_ } (qw(ready waiting looping retrying)) ) ? colored( $c->{jobstate}, 'bold yellow' )
        :                                                                                $c->{jobstate};

      $cstate .= "($credo)" if $credo;
      my ( $started, $ended, $duration ) = format_time($c);
      my $needs = join( ' ', keys %{ $c->{needs} } );

      #my $clast = $c->{started} ? strftime( "%b %d %H:%M:%S", localtime( $c->{started} ) ) : '';
      my $ctminus = &epoch_to_tminus( $c->{next_start} );
      my $ctplus  = &epoch_to_tminus( $c->{started} );
      my $cdur    = &epoch_to_duration( $c->{started}, $c->{ended} || time );

      push @{$rows}, [ $c->{id}, $blue_path, $cstate, '', $needs, '', '', '', $ctplus, $cdur, $ctminus, $c->{cal_id} ];

      next unless $cluster{$cluster_id}->{jobs};

      foreach my $j ( @{ $cluster{$cluster_id}->{jobs} } ) {

         my $pathname = $i == 0 ? $path_padding . $j->{name} : "$path/$j->{name}";

         #my $pathname = $i == 0 ? " $path" . $j->{name};
         #my $jlast = $j->{started} ? strftime( "%b %d %H:%M:%S", localtime( $j->{started} ) ) : '';
         my $jtminus = &epoch_to_tminus( $j->{next_start} );
         my $jtplus  = &epoch_to_tminus( $j->{started} );
         my $jdur    = &epoch_to_duration( $j->{started}, $j->{ended} || time );

         my ( $started, $ended, $duration ) = format_time($j);

         my $redo = $j->{retry_count} || $j->{loop_count};

         my $jstate =
             scalar( grep { $j->{jobstate} eq $_ } (qw(complete ice pruned)) )            ? colored( $j->{jobstate}, 'bold green' )
           : scalar( grep { $j->{jobstate} eq $_ } (qw(failed zombie killed hold)) )      ? colored( $j->{jobstate}, 'bold red' )
           : scalar( grep { $j->{jobstate} eq $_ } (qw(running)) )                        ? colored( $j->{jobstate}, 'bold magenta' )
           : scalar( grep { $j->{jobstate} eq $_ } (qw(ready waiting looping retrying)) ) ? colored( $j->{jobstate}, 'bold yellow' )
           :                                                                                $j->{jobstate};

         $jstate .= "($redo)" if $redo;

         my $row = [ $j->{id}, $pathname, $jstate, $j->{server_name}, join( ' ', keys %{ $j->{needs} } ), $j->{pctmem}, $j->{pctcpu}, $j->{pid}, $jtplus, $duration, '', '' ];

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

sub after_dispatch {
   my ( $command, $json ) = @_;
   return unless $command && $json;

   my %dispatch = (
      change_cluster => \&change_cluster,
      login_user     => \&login_user,
      find_cluster   => \&find_cluster,
      read_job       => \&_print_table,
      read_cluster   => \&_print_table,
      read_path      => \&_print_table,
      find_cal       => \&find_cal,
      read_cal       => \&find_cal,
      find_log       => \&find_log,
      read_log       => \&read_log,
      read_monitor   => \&_print_table,
      find_monitor   => \&find_monitor,
      create_monitor => \&create_monitor,

      #update_monitor => \&create_monitor,
      new_token => \&new_token,
      read_user => \&_print_table,
      help_commands => \&help,
   );

   if ( exists( $dispatch{$command} ) ) {
      &{ $dispatch{$command} }($json);
      return 1;
   }
   return 0;
}

sub before_dispatch {
   my ( $command, $json ) = @_;

   my %dispatch = ();

   if ( exists( $dispatch{$command} ) ) {
      &{ $dispatch{$command} }($json);
      return 1;
   }
   return 0;
}

sub string2hash {
   my $string = shift;
   my %options;

   my ($cmds) = $string =~ /(.*?)(-.*)?$/;
   my ($opts) = $string =~ /(-.*$)/;
   my ( $verb, $noun, $name ) = &extract_command($cmds);

   if ($opts) {

      my ( $ret, $args ) = GetOptionsFromString(
         $opts,         \%options,  "command=s",   "token=s",      "state:s",  "user:s",   "host:s",       "newname:s", "password:s", "script:s",
         "email:s",     "level:i",  "cron:s",      "at:s",         "cal:s",    "cal_id:i", "force",        "count:i",   "needs:i@",   "description:s",
         "server_id:i", "name:s",   "job_id:i",    "cluster_id:i", "server:s", "org_id:i", "pid:i",        "id:s",      "match:s",    "tz:s",
         "begin:s",     "expire:s", "parent_id:i", "retrys:i",     "delay:i",  "loops:i",  "fail_alarm:i", "mode:i",    "clonable:i",   "log:i",
         "json:s", "needs_any:i"
      );

      # allow multi-value needs

      if ( $opts =~ /needs\s+/ ) {
         my @needs;
         $opts =~ s/^.*?(-needs.*$)/$1/;
         $opts =~ s/(.*?needs[^-]*?)-.*/$1/;
         GetOptionsFromString( $opts, 'needs:i{,}' => \@needs );
         $options{needs} = \@needs if scalar @needs && scalar @needs > scalar @{ $options{needs} };
      }
   }

   my $cmd;

   if ( exists $aliases->{$verb} ) {
      $cmd  = $aliases->{$verb};
      $name = $noun;
   }
   else {
      $cmd = $noun ? join( '_', ( $verb, $noun ) ) : $verb;
   }

   #return { success => 0, message => 'command not found' } unless $noun && defined $verb;
   return { success => 0, message => 'command not found' } unless $cmd;

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
   my $res = { token => $token, command => $cmd, %options };
   $res->{name} = $name if defined $name;
   print Dumper($res);
   return $res;
}

sub request {
   my $line    = shift;
   my $command = &string2hash($line);

   return $command if defined $command->{success} && $command->{success} == 0;
   &before_dispatch( $command->{command}, $command );

   my $json = &send_request($command);

   &after_dispatch( $json->{command_reply}, $json );

   return $json;
}

sub send_request {
   my $request = shift;
   my $json;
   eval { $json = $ua->get( $api => { Accept => 'application/json' } => json => $request )->result->json; };
   return $@ ? { success => 0, message => $@ } : $json;
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
   return $epoch;
}

sub less {
   my $string = shift;
   my @lines  = split( /\n/, $string );
   $_ .= "\n" for @lines;
   push @lines, "\n";

   # Get terminal size
   my ( $term_width, $term_height ) = GetTerminalSize();
   $term_height -= 1;    # Reserve one line for status

   my $total_lines  = @lines;
   my $current_line = 0;

   # If file fits in one screen, print and exit
   if ( $total_lines <= $term_height ) {
      for my $i ( 0 .. $total_lines - 1 ) {
         print $lines[$i];
      }
      return;
   }

   # Enable raw mode for key reading
   ReadMode('cbreak');

   # Main loop for interactive paging
   while (1) {

      # Move to top for content
      print "\033[1;1H";

      # Display lines for the current page, ensuring last line is shown
      my $lines_to_show = $term_height;
      if ( $current_line + $term_height > $total_lines ) {
         $current_line  = $total_lines - $term_height if $total_lines >= $term_height;
         $current_line  = 0                           if $current_line < 0;
         $lines_to_show = $total_lines - $current_line;
      }
      for my $i ( $current_line .. $current_line + $lines_to_show - 1 ) {
         last if $i >= $total_lines;
         print "\033[K";    # Clear line
         print $lines[$i];
      }

      # Clear any remaining lines to prevent artifacts
      for my $i ( $lines_to_show + 1 .. $term_height ) {
         print "\033[$i;1H\033[K";    # Clear line
      }

      # Calculate percentage
      my $percent = ( $total_lines > 0 ) ? ceil( ( $current_line + $lines_to_show ) / $total_lines * 100 ) : 100;
      $percent = 100 if $percent > 100;

      # Move cursor to bottom and print status line
      my $bottom_line = $current_line + $lines_to_show;
      print "\033[$term_height;1H\033[K";    # Move to bottom, clear line
      print "\033[7m:(line $bottom_line of $total_lines, $percent%) [Press q to quit, space to page down, b to page up, j/down or k/up to scroll]\033[0m";

      # Read key with better arrow key handling
      my $key   = ReadKey(0);
      my $input = $key;

      # Handle arrow key escape sequences
      if ( $key eq "\033" ) {                # Escape sequence start
         $key = ReadKey(0);
         if ( $key eq '[' ) {                # Arrow key sequence
            $key   = ReadKey(0);
            $input = "\033[$key";            # Full escape sequence
         }
         else {
            $input = "\033$key";             # Handle other escape sequences
         }
      }

      # Handle key presses
      if ( $input eq 'q' ) {
         print "\033[$term_height;1H\033[K";    # Clear status line
         last;                                  # Quit
      }
      elsif ( $input eq ' ' ) {
         $current_line += $term_height;         # Page down
         $current_line = $total_lines - $term_height if $current_line > $total_lines - $term_height;
         $current_line = 0                           if $current_line < 0;
      }
      elsif ( $input eq 'b' ) {
         $current_line -= $term_height;         # Page up
         $current_line = 0 if $current_line < 0;
      }
      elsif ( $input eq 'j' || $input eq "\033[B" ) {    # j or down arrow
         $current_line += 1;                             # Scroll down one line
         $current_line = $total_lines - $term_height if $current_line > $total_lines - $term_height;
         $current_line = 0                           if $current_line < 0;
      }
      elsif ( $input eq 'k' || $input eq "\033[A" ) {    # k or up arrow
         $current_line -= 1;                             # Scroll up one line
         $current_line = 0 if $current_line < 0;
      }
   }

   # Restore terminal
   ReadMode('restore');
}

sub extract_command {
   my $string = shift;
   my @parts;
   my $current   = '';
   my $in_quotes = '';
   my $i         = 0;

   while ( $i < length($string) ) {
      my $char = substr( $string, $i, 1 );

      if ($in_quotes) {

         # Inside quotes, collect until matching quote
         $current .= $char;
         if ( $char eq $in_quotes && ( $i == 0 || substr( $string, $i - 1, 1 ) ne '\\' ) ) {
            $in_quotes = '';    # Exit quote mode
         }
      }
      elsif ( $char eq '"' || $char eq "'" ) {

         # Start of quoted string
         $in_quotes = $char;
         $current .= $char;
      }
      elsif ( $char =~ /\s/ ) {

         # Whitespace outside quotes: finalize current part
         if ( $current ne '' ) {
            push @parts, $current;
            $current = '';
         }
      }
      else {
         # Non-whitespace outside quotes
         $current .= $char;
      }
      $i++;
   }

   push @parts, $current if $current ne '';

   # Clean up quotes from the parts
   @parts = map { s/^['"]|['"]$//g; $_ } @parts;

   return @parts;
}
