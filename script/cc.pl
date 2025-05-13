#!/usr/bin/env perl 

use strict;
use warnings;

use Term::ReadLine::Perl5;
use Mojo::UserAgent;
use Data::Dumper;
use Getopt::Long qw(GetOptionsFromString);
use JSON;
use feature qw(say);

my $config;

eval {
   open( my $fh, "<", "ordo.json" ) or die $!;
   $config = decode_json( do { local $/; <$fh> } );
   close($fh);
};

die "Unable to open config file: $@\n" if $@;

my $token = $config->{token};
my $url = 'http://127.0.0.1:3000/api';
my $user = 'offline';
my $cluster = '';

my $ua = Mojo::UserAgent->new;

my $change_cluster = sub {
   my $json = shift;
   $cluster = $json->{path};
};

my $read_user = sub {
   my $json = shift;
   $user = $json->{hostname} || 'offline';
   $cluster = $json->{path} || '';
};

my $update_token = sub {
   $token = shift;
   return { success => 0, message => 'missing token' } unless $token;
   $config->{token} = $token;
   eval {
      open( my $fh, ">", "ordo.json" ) or die $!;
      my $json = encode_json( $config );
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
      cmd1
      cmd2
      cmd3
   HELP
   return { success => 1 };
};

my $remote_dispatch = {
   change_cluster => $change_cluster,
   read_user => $read_user,
};

my $local_dispatch = {
   token => $update_token,
   update_token => $update_token,
   help => $help,
};

&request("read user");

sub request {
   my $line = shift;
   my $r = &string2hash($line);    
   unless ($r->{token}) {
      say to_json( $r, { pretty => 1 } );
      return;
   }
   print Dumper($r);
   my $json;
   eval {
      $json = $ua->get( $url => { Accept => 'application/json' } => json => $r )->result->json;
   };
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
      $string,
      \%options,
      "command=s",
      "token=s",
      "username:s",
      "hostname:s",
      "newname:s",
      "password:s",
      "shell_command:s",
      "email:s",
      "level:s",
      "name:s",
      "job_id:i",
      "cluster_id:i",
      "server_id:i",
      "state_id:i",
      "org_id:i",
      "pid:i",
   );

   my ($verb, $noun, $name) = @{ $args };

   return { success => 0, message => 'missing verb' } unless defined $verb;

   unless ( $noun || exists $local_dispatch->{$verb} ) {
      return { success => 0, message => 'missing noun' };
   }

   my $cmd = $noun ? join('_', ($verb, $noun)) : $verb;

   # execute local command
   if ( exists $local_dispatch->{$verb} ) {
      my $v = &{ $local_dispatch->{ $verb } }($noun);
      return $v;
   }
   elsif ( exists $local_dispatch->{$cmd} ) {
      my $v = &{ $local_dispatch->{ $cmd } }($name);
      return $v;
   }
   
   # execute remote command
   my $r = { token => $token, command => $cmd, %options };
   $r->{name} = $name if defined $name;
   return $r
}
