#!/usr/bin/env perl 

use strict;
use warnings;

use Term::ReadLine::Perl5;
use Mojo::UserAgent;
use Term::ANSIColor;
use DateTime;
use POSIX qw(strftime);
use Data::Dumper;
use Getopt::Long qw(GetOptionsFromString);
use JSON;
use FindBin     qw($Bin);
use Text::Table::Tiny 1.02 qw/ generate_table /;

use feature qw(say);

my $config;

eval {
   open( my $fh, "<", "$Bin/../ordo.json" ) or die $!;
   $config = decode_json( do { local $/; <$fh> } );
   close($fh);
};

die "Unable to open config file: $@\n" if $@;

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
   $token = shift;
   return { success => 0, message => 'missing token' } unless $token;
   $config->{token} = $token;
   eval {
      open( my $fh, ">", "ordo.json" ) or die $!;
      my $json = encode_json($config);
      print $fh $json;
      close($fh);
   };
   my $success;
   if ($@) {
      $success = 0;
   }
   else {
      $success = 1;
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

my $read_server = sub {
   my $json     = shift;
   my $rows = [ [qw(ID ALIAS %MEMORY %DISK LOADAVG PING UPTIME OS ACTIVE UPDATED HOST)] ];
   my @servers = @{ $json->{servers} };
   for my $s (@servers) {
      my ($cpu, $pmem, $pdisk, $uptime, $ping, $conn, $update);
      if ($s->{total_memory}) {
         $pmem = sprintf ("%.2f", ($s->{used_memory} / $s->{total_memory}) * 100 );
      }
      if ($s->{total_disk}) {
         $pdisk = sprintf ("%.2f", ($s->{used_disk} / $s->{total_disk}) * 100 );
      }
      if ($s->{uptime}) {
         $uptime = sprintf ("%.2f days", ($s->{uptime} / 86000));
      }
      if ($s->{uptime}) {
         $ping = sprintf ("%.2f ms", $s->{ping});
      }
      if ($s->{update_time}) {
         my $seconds = time - $s->{update_time};
         $update = sprintf ("%is ago", $seconds);
      }
      if ($s->{cpu}) {
         my $cores = $s->{cores} || 1;
         $cpu = sprintf("%.2f (%i)", $s->{cpu}, $cores);
      }

      $conn = $s->{connected} ? 'yes' : 'no';
      push @$rows, [ $s->{id}, $s->{name}, $pmem, $pdisk, $cpu, $ping, $uptime, $s->{os}, $conn, $update, $s->{hostname} ];
   }
   say generate_table( rows => $rows, header_row => 1 );
};

my $find_cluster = sub {
   my $json     = shift;
   my @clusters = @{ $json->{clusters} };
   my %cluster   = map { $_->{id}, $_ } @{ $json->{clusters} };

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

   my $rows = [ [qw(ID CLUSTER/JOB STATE SERVER %MEM %CPU PRI PID PSTATE PNAME STARTED ENDED DURATION)] ];
   foreach my $part (@paths) {
      my $path       = join( '/', ( map { $cluster{$_}->{name} } @{$part} ) );
      my $colored    = colored( $path, 'bold blue' );
      my $cluster_id = pop @{$part} || 0;
      my $c          = $cluster{$cluster_id};
      my ( $start, $end, $dur ) = &format_epoch( $c->{started}, $c->{ended} );
      push @{$rows}, [ $c->{id}, $colored, $c->{state},,,,,,,,,$dur ];

      next unless $cluster{$cluster_id}->{jobs};

      foreach my $j ( @{ $cluster{$cluster_id}->{jobs} } ) {
         my ( $s, $e, $d ) = &format_epoch( $j->{started}, $j->{ended} );

         my $started = strftime("%H:%M:%S", localtime($j->{started})),

         my ($ended, $end_seconds);
         if ( $j->{jobstate} eq 'running' ) {
            $ended = '';
            $end_seconds = time;
         }
         else {
            $end_seconds = $j->{ended};
            $ended = strftime("%H:%M:%S", localtime($j->{ended})),
            $j->{$_} = '' for (qw(fname pname pctmem pctcpu priority pid state));
         }

         my $duration = sprintf ("%.3f hrs", ($end_seconds - $j->{started}) / 3600);

         my $row = [ 
            $j->{id},
            "$path/$j->{name}",
            $j->{jobstate},
            $j->{server_name},
            $j->{pctmem},
            $j->{pctcpu},
            $j->{priority},
            $j->{pid},
            $j->{state},
            $j->{fname},
            $started,
            $ended,
            $duration,
         ];
         
         push @{$rows}, $row; 

         print Dumper($j);
      }
   }
   say generate_table( rows => $rows, header_row => 1 );
};

sub format_epoch {
   my ( $start, $end ) = @_;
   return ( '', '', '' ) unless $start;
   my $sdt = DateTime->from_epoch( epoch => $start );
   my $s   = $sdt->ymd . ' ' . $sdt->hms;

   my $epoch = $end || time;

   my $edt = DateTime->from_epoch( epoch => $epoch );

   my $dur     = $edt - $sdt;
   my $elapsed = sprintf '%02s:%02s:%02s', $dur->hours, $dur->minutes, $dur->seconds;

   my $e = $end ? $edt->ymd . ' ' . $edt->hms : '';
   return ( $s, $e, $elapsed );
}

my $remote_dispatch = {
   change_cluster => $change_cluster,
   read_user      => $read_user,
   find_cluster   => $find_cluster,
   read_server    => $read_server,
};

my $local_dispatch = {
   token        => $update_token,
   update_token => $update_token,
   help         => $help,
};

&request("read user");

sub request {
   my $line = shift;
   my $r    = &string2hash($line);
   unless ( $r->{token} ) {
      say to_json( $r, { pretty => 1 } );
      return;
   }

   my $json;
   eval { $json = $ua->get( $api => { Accept => 'application/json' } => json => $r )->result->json; };
   $json = { success => 0, message => $@ } if $@;
   print to_json( $json, { pretty => 1 } );
   return unless $json->{success};
   &{ $remote_dispatch->{ $json->{command_reply} } }($json) if exists $json->{command_reply} && $remote_dispatch->{ $json->{command_reply} };
}

my $term = Term::ReadLine::Perl5->new('ordo');
while ( defined( my $line = $term->readline("$user:/$cluster> ") ) ) {
   next unless $line;
   &request($line);
}

sub string2hash {
   my $string = shift;

   my %options;
   my ( $ret, $args ) = GetOptionsFromString(
      $string,   \%options, "command=s", "token=s", "state:s", "username:s",  "hostname:s", "newname:s", "password:s", "shell_command:s", "email:s",
      "level:s", "server_id:i", "name:s",  "job_id:i",  "cluster_id:i", "server:s", "org_id:i",  "pid:i",      "to:s",            "id:s",
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
   my $r = { token => $token, command => $cmd, %options };
   $r->{name} = $name if defined $name;
   return $r;
}
