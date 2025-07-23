package ordo;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use ordo::Model::User;
use JSON;
use Digest::SHA qw(hmac_sha1_hex);
use FindBin qw($Bin);
use Net::OpenSSH;
use Sys::Hostname;
use POSIX ":sys_wait_h";
use EV;
use DateTime;
use DateTime::Event::Cron;
use Data::Dumper;

# TODO: logs, threshholds, time series stats, timers
$SIG{CHLD} = sub {
   1 while ( ( waitpid( -1, WNOHANG ) ) > 0 );
};

has 'user' => sub {
   state $user = {};
};

has 'ssh_connection' => sub {
   state $ssh = {};
};

has 'cron' => sub {
   state $timer = {};
};

has 'at' => sub {
   state $timer = {};
};

# This method will run once at server start
sub startup {

   my $self = shift;

   # Configure the application
   $self->secrets( [ 'gu$!$#UessM%#eI36#$fYo43@#$uC^%5an', '%!#GDA$#!gfds%#@sdf' ] );

   #my $log = Mojo::Log->new(path => '/tmp/mojo.log', level => 'fatal'); # new log instance
   #$self->log($log); # tell app to use new log instance

   # Helpers
   $self->helper( request => \&request );
   $self->helper( routing => \&routing );
   $self->helper( sqlite  => sub { state $sql = Mojo::SQLite->new("$Bin/../db/ordo.db"); $sql->db->query('PRAGMA foreign_keys = ON;') } );

   my $states = $self->sqlite->db->select( 'job_states', ['*'] )->hashes->to_array;
   $self->helper(
      job_states => sub {
         state $states = { map { $_->{state}, $_->{id} } @{$states} };
      }
   );

   # Router
   my $r = $self->routes;

   # Normal route to controller
   # $r->get('/')->to( controller => 'landing', action => 'welcome' );
   $r->websocket('/websocket')->to( controller => 'websocket', action => 'default' );

   # HTTP status codes
   # 200 OK: The request was successful.
   # 201 Created: A new resource has been created.
   # 400 Bad Request: The request was invalid or cannot be fulfilled.
   # 401 Unauthorized: Authentication is required and has failed or has not yet been provided.
   # 404 Not Found: The requested resource could not be found.
   # 500 Internal Server Error: The server encountered an unexpected condition.

   $r->any(
      '/api' => sub {
         my $c    = shift;
         my $body = $c->req->json;
         if ( ref $body ne 'HASH' || !$body->{token} ) {
            $c->render( json => { success => 0, message => 'missing login token' }, status => 400 );
         }
         else {
            state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );
            my $auth = $self->request( $user, { token => $body->{token}, command => 'login_user' } );
            if ( $auth->{success} ) {
               my $result = $self->request( $user, $body );
               $c->render( json => $result );
            }
            else {
               $c->render( json => { success => 0, message => 'invalid login token' }, status => 401 );
            }
         }
      }
   );

   # start server monitors
   my $monitor_sql = <<~"SQL";
      select s.id as id, s.org_id as org_id, u.id as user_id, min(u.id) as mid, u.token as token
      from server s
      join user u on u.org_id = s.org_id
      group by s.id;
   SQL
   my $results = $self->sqlite->db->query($monitor_sql);
   while ( my $s = $results->hash ) {
      my $user = ordo::Model::User->new( id => $s->{mid}, org_id => $s->{org_id} );
      $self->_install_monitor( $user, { id => $s->{id} } );
      $self->_start_monitor( $user, { id => $s->{id} } );
      # run start_monitor ?
   }

   # load at timers
   my $at_timers = $self->sqlite->db->select( 'cluster', ['*'], { at_id => { '!=', undef } } );
   while ( my $a = $at_timers->hash ) {
      my $user = ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      my $at = $self->_create_at_object($user, { at_id => $a->{at_id}, cluster_id => $a->{id} });
   }

   # load cron timers
   # TODO add time zone to at and cron tables
   my $cron_timers = $self->sqlite->db->select( 'cluster', ['*'], { cron_id => { '!=', undef } } );
   while ( my $a = $cron_timers->hash ) {
      my $user = ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      $self->_create_cron_object($user, { cron_id => $a->{cron_id}, cluster_id => $a->{id} });
   }
}

sub request {
   my ( $self, $user, $decoded ) = @_;

   my $response = {};

   state $i = qr/^\d{1,20}$/;    # is integer
   state $w = qr/^\w{1,60}$/;    # is word

   die unless ref $decoded eq 'HASH';

   my ( $command, $params ) = ( delete $decoded->{command}, $decoded );
   if ( exists $self->routing->{$command} ) {
      my $level = $user->level || 0;
      my ( $sub, $min_level, $legal_options ) = @{ $self->routing->{$command} };
      my ( $required, $optional ) = @{$legal_options};
      $optional->{request_id} = $i;    # request_id added by client to every request
      $optional->{token}      = $w;    # token added for rest api
      my @unknown = grep { !exists $required->{$_} && !exists $optional->{$_} } keys %$params;
      my @missing = grep { !exists $params->{$_} } keys %$required;

      if ( $user->level < $min_level ) {
         $response->{success} = 0;
         $response->{message} = 'Level too low.';
      }
      elsif ( scalar @unknown ) {
         $response->{success} = 0;
         $response->{message} = "unknown parameters: @unknown";
      }
      elsif ( scalar @missing ) {
         $response->{success} = 0;
         $response->{message} = "missing parameters: @missing";
      }
      else {
         my $error = 0;
         my $bad_option;
         for my $param ( keys %$params ) {
            my $regex = $required->{$param} || $optional->{$param};

            # check that param matches regex
            unless ( ($regex eq 's' && ref $params->{$param} eq 'ARRAY') || $params->{$param} =~ $regex ) {
               $error      = 1;
               $bad_option = $param;
               last;
            }
         }
         $response =
           $error
           ? { success => 0, message => "validation failed: $bad_option" }
           : &$sub( $self, $user, {%$params} );
      }
   }
   else {
      $response = { success => 0, message => 'no such command' };
   }

   $response->{command_reply} = $command;
   $response->{request_id}    = $params->{request_id} if $params->{request_id};
   return $response;
}

# cluster related subroutines

sub _has_permission {
   my ( $self, $bits, $user, $cluster ) = @_;
   return 0 unless $cluster;
   my $owner = substr( $cluster->{mode}, 0, 1 );
   my $group = substr( $cluster->{mode}, 1, 1 );
   my $other = substr( $cluster->{mode}, 2, 1 );
   return 1 if $user->{id} == $cluster->{user_id}    && scalar( grep { $owner eq $_ } @{$bits} );
   return 1 if $user->{org_id} == $cluster->{org_id} && scalar( grep { $group eq $_ } @{$bits} );
   return 1 if scalar( grep { $other eq $_ } @{$bits} );
   return 0;
}

sub is_readable {
   my ( $self, $user, $d ) = @_;
   return $self->_has_permission( [qw(7 6 5 4)], $user, $d );
}

sub is_writable {
   my ( $self, $user, $d ) = @_;
   return $self->_has_permission( [qw(7 6 3 2)], $user, $d );
}

sub is_executable {
   my ( $self, $user, $d ) = @_;
   return $self->_has_permission( [qw(7 5 3 1)], $user, $d );
}

sub read_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;

   my $c           = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
   my $is_readable = $self->is_readable( $user, $c );
   return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;

   #my @fields = qw(id cron at cal cal_id next_start command mode org_id user_id parent_id server_id state_id name description started ended);
   my @fields = qw(id cal_id cron_id at_id next_start command mode org_id user_id parent_id server_id state_id name description started ended);
   my %rv     = map { $_, $c->{$_} } @fields;
   $rv{at} = $self->sqlite->db->select( 'at', ['value'], { id => $c->{at_id} } )->hash->{value} if $c->{at_id};
   $rv{cron} = $self->sqlite->db->select( 'cron', ['value'], { id => $c->{cron_id} } )->hash->{value} if $c->{cron_id};
   if ($c->{cal_id}) {
      $rv{cal} = {}; # TODO
   }
   $rv{jobstate} = $self->sqlite->db->select( 'job_states', ['state'], { id => $rv{state_id} } )->hash->{state} if $rv{state_id};
   $rv{needs} = $self->_read_cluster_needs( $user, { id => $cluster_id } );
   return { success => 1, %rv };
}

sub _set_cluster_state {
   my ( $self, $user, $d ) = @_;
   # id state

   my $state_id = $self->job_states->{ $d->{state} };
   return unless $state_id;
   
   my $update_hash = { state_id => $state_id };

   if ($d->{state} == 'running') {
      $update_hash->{started} = time;
      $update_hash->{ended} = undef;
   }
   elsif ($d->{state} == 'complete') {
      $update_hash->{ended} = time;
   }
   elsif ($d->{state} == 'failed') {
      $update_hash->{ended} = time;
   }
   $self->sqlite->db->update( 'cluster', $update_hash, { id => $d->{id} } );
}

sub start_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   return $cluster_info if $cluster_info->{success} == 0;
   my $cluster_id = $cluster_info->{id};

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;

   # check jobs are in ready state
   my $complete = $self->job_states->{complete};
   my $running  = $self->job_states->{running};
   my $failed   = $self->job_states->{failed};
   my $ready    = $self->job_states->{ready};
   my $hold     = $self->job_states->{hold};
   my $ice      = $self->job_states->{ice};

   return { success => 0, message => 'cluster already running' } if $cluster_info->{state_id} == $self->job_states->{running};

   #my $jobs_ready = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => [ ( $complete, $ready ) ] }, { limit => 1 } );
   #return { success => 0, message => 'no jobs to start' } unless $jobs_ready->hash;

   my $not_ready = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $complete, $ready, $hold, $ice ) ] } }, { limit => 1 } );
   return { success => 0, message => 'jobs not ready' } if $not_ready->hash;

   $self->_reset_cluster( $user, { id => $cluster_id } );

   return { success => 0, message => $@ } if $@;

   my $results = $self->sqlite->db->select('job', ['id'], { cluster_id => $cluster_id, state_id => { '=', [$ready] } }, { -desc => 'id' } )->hashes;

   my $jobs_started = 0;
   my $jobs_failed = 0;
   my $jobs_skipped = 0;
   my $error;
   foreach my $j ( @{ $results->to_array } ) {
      my $rv = $self->start_job( $user, $j );
      if ( $rv->{success} ) {
         $jobs_started++;
      }
      elsif ( $rv->{skipped} ) {
         $jobs_skipped++;
      }
      else {
         $jobs_failed++;
         $error = $rv->{message};
      }
   }

   if ($jobs_failed) {
      $self->_set_cluster_state($user, { state => 'failed', id => $cluster_id });
      return { success => 0, message => "$jobs_failed failed jobs: $error" };
   }
   elsif ($jobs_started) {
      $self->_set_cluster_state($user, { state => 'running', id => $cluster_id });
      return { success => 1, message => "$jobs_started jobs started, $jobs_skipped jobs skipped" };
   }
   else {
      $self->_set_cluster_state($user, { state => 'running', id => $cluster_id });
      $self->_set_cluster_state($user, { state => 'complete', id => $cluster_id });
      return { success => 1, message => "nothing to start" };
   }
}

sub _reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};
   my $ready        = $self->job_states->{ready};
   my $hold         = $self->job_states->{hold};
   my $ice          = $self->job_states->{ice};
   eval { $self->sqlite->db->update( 'cluster', { state_id => $ready, started => undef, ended => undef }, { id => $cluster_id } ) };
   eval { $self->sqlite->db->update( 'job', { state_id => $ready, started => undef, ended => undef }, { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $hold, $ice ) ] } } ) };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

sub reset_cluster {
   my ( $self, $user, $d ) = @_;
   return $self->_reset_cluster( $user, $d );
}

sub find_cluster {
   my ( $self, $user, $d ) = @_;

   #my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;

   my @clusters;

   if ($cluster_id) {
      my $top = $cluster_info;

      #my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
      my $is_readable = $self->is_readable( $user, $top );
      return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;

      $top->{jobs}  = $self->_find_jobs( $user, { cluster_id => $cluster_id } );
      $top->{needs} = $self->_read_cluster_needs( $user, { id => $cluster_id } );
      push @clusters, $top;
   }

   my $find_clusters = sub {
      my $id     = shift;
      my $org_id = $user->org_id;

      my $patch = $id ? " = $id " : " IS NULL ";

      my $sql = <<~"SQL";
         select c.*, js.state as jobstate
         from cluster c
         left join job_states js on c.state_id = js.id
         where parent_id $patch
         and org_id = $org_id 
      SQL

      my $cluster = $self->sqlite->db->query($sql);

      while ( my $c = $cluster->hash ) {
         $c->{jobs}  = $self->_find_jobs( $user, { cluster_id => $c->{id} } );
         $c->{needs} = $self->_read_cluster_needs( $user, { id => $c->{id} } );

         push @clusters, $c;
         __SUB__->( $c->{id} );
      }
      return;
   };

   $find_clusters->($cluster_id);
   return { success => 1, clusters => \@clusters };
}

sub update_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   return $cluster_info if $cluster_info->{success} == 0;
   my $cluster_id = $cluster_info->{id};

   return { success => 0, message => 'cluster not found' } unless $cluster_id;
   my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
   my $is_writable = $self->is_writable( $user, $top );
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   eval {
      $self->_update_timers($user, $d) or die "unable to load timer";
      $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster_id } )       if scalar keys %{$update_hash};
      $self->_write_cluster_needs( $user, { id => $cluster_id, needs => $d->{needs} } ) if $d->{needs};
   };
   my $success = $@ ? 0 : 1;
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $cluster_id };
}

sub _update_timers {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id = $cluster_info->{id};
   my $update_hash = {};
   eval {
      if (defined $d->{at}) {
         $self->_delete_at($user, { at_id => $cluster_info->{at_id} }) if $cluster_info->{at_id};
         return 1 unless $d->{at};
         my $at_id = $self->_create_at_row($user, { at => $d->{at} }) or die "unable to create at row";
         $self->_create_at_object($user, { at_id => $at_id, cluster_id => $cluster_id }) or die "invalid at";
         $update_hash->{at_id} = $at_id;
         $self->_delete_cron($user, { cron_id => $cluster_info->{cron_id} }) if $cluster_info->{cron_id};
         $self->_delete_cal($user, { cal_id => $cluster_info->{cal_id} }) if $cluster_info->{cal_id};
      }
      elsif (defined $d->{cron}) {
         $self->_delete_cron($user, { cron_id => $cluster_info->{cron_id} }) if $cluster_info->{cron_id};
         return 1 unless $d->{cron};
         my $cron_id = $self->_create_cron_row($user, { cron => $d->{cron}, tz => $d->{tz} }) or die "unable to create cron row";
         $self->_create_cron_object($user, { cron_id => $cron_id, cluster_id => $cluster_id }) or die "invalid cron";
         $update_hash->{cron_id} = $cron_id;
         $self->_delete_at($user, { at_id => $cluster_info->{at_id} }) if $cluster_info->{at_id};
         $self->_delete_cal($user, { cal_id => $cluster_info->{cal_id} }) if $cluster_info->{cal_id};
      }
      elsif (defined $d->{cal_id}) {
         $self->_delete_cal($user, { cal_id => $cluster_info->{cal_id} }) if $cluster_info->{cal_id};
         return 1 unless $d->{cal_id};
         $update_hash->{cal_id} = $d->{cal_id};
         $self->_delete_at($user, { at_id => $cluster_info->{at_id} }) if $cluster_info->{at_id};
         $self->_delete_cron($user, { cron_id => $cluster_info->{cron_id} }) if $cluster_info->{cron_id};
      }
      $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster_id } ) if scalar keys %{$update_hash};
   };
   return $@ ? 0 : 1;
}

sub delete_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   return $cluster_info if $cluster_info->{success} == 0;
   my $cluster_id = $cluster_info->{id};

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
      my $is_writable = $self->is_writable( $user, $top );
      return { success => 0, message => 'no write permissions on this cluster' } unless $is_writable;
   }

   # delete cluster and all descendants
   my $clusters = $self->find_cluster( $user, { id => $cluster_id } )->{clusters};
   foreach my $c ( @{$clusters} ) {

      # delete jobs
      my $jobs = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $c->{id} } );
      while ( my $j = $jobs->hash ) {
         eval { $self->sqlite->db->delete( 'job', { id => $j->{id} } ); };
      }

      # delete cluster
      eval { 
         $self->sqlite->db->delete( 'cluster', { id => $c->{id} } );
         delete $self->cron->{ $c->{id} };
      };
   }

   my $success = $@ ? 0 : 1;
   return { success => $success, id => $cluster_id };
}

sub create_cluster {
   my ( $self, $user, $d ) = @_;

   my ($root) = $d->{name} =~ /^(\/)/;
   my @parts  = split( '/', $d->{name} );
   my $name   = pop @parts;
   my $path   = join( '/', @parts );
   $path = $root . $path if $root;

   my $cluster_id = $self->path2id( $user, $path );
   my $cluster    = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster_id, name => $name } )->hash;
   return { success => 0, message => 'a cluster by that name already exists' } if $cluster->{id};

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   my $user_info = $self->read_user($user);

   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
      my $is_writable = $self->is_writable( $user, $top );
      return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;
   }

   my $insert_hash = {
      org_id    => $user_info->{org_id},
      user_id   => $user_info->{id},
      parent_id => $cluster_id,
      server_id => $d->{server_id},
      name      => $name,
   };

   $insert_hash->{mode} = $user_info->{mode} if $user_info->{mode};

   my $id;
   eval {
      $id = $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id;
      $self->_update_timers($user, { %$d, id => $cluster_id });
      $self->_write_cluster_needs( $user, { id => $id, needs => $d->{needs} } ) if $d->{needs};
   };
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $id };
}

sub change_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};

   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
      my $is_readable = $self->is_readable( $user, $top );
      return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;
   }

   # 0 = not found, undef = root cluster
   return { success => 0, message => 'unable to locate cluster' } if defined $cluster_id && $cluster_id == 0;

   my $fullpath  = $self->id2path($cluster_id);
   my $user_info = $self->read_user($user);
   eval { $self->sqlite->db->update( 'user', { base_cluster_id => $cluster_id }, { id => $user_info->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { path => $fullpath, cluster_id => $cluster_id, success => $success };
}

sub path2id {
   my ( $self, $user, $path ) = @_;
   my $user_info       = $self->read_user($user);
   my $base_cluster_id = $user_info->{base_cluster_id};
   my $base_path       = $self->id2path($base_cluster_id);
   my $fullpath =
       ( $path && substr( $path, 0, 1 ) eq '/' ) ? $path
     : $path && $base_path                       ? "/$base_path/$path"
     : $path                                     ? "/$path"
     : $base_path                                ? "/$base_path"
     :                                             '/';

   my @parts    = split( '/', $fullpath );
   my @ups      = grep { $parts[$_] eq '..' } ( 1 .. $#parts );
   my $up_count = scalar @ups;
   if ($up_count) {
      @parts = grep { $_ ne '..' } @parts;
      my $offset = $ups[0] - $up_count;
      $offset = $offset > 0 ? $offset : 0;
      splice( @parts, $offset, $up_count );
   }

   my $parent_id = undef;

   foreach my $part (@parts) {
      my $result = $self->sqlite->db->select( 'cluster', ['*'], { parent_id => $parent_id, name => $part, org_id => $user_info->{org_id} } )->hash;
      $parent_id = $result->{id};
      return 0 if $part && !$parent_id;    # invalid path name
   }
   return $parent_id;
}

sub id2path {
   my ( $self, $cluster_id ) = @_;

   my $parent_id = $cluster_id;
   my @names;

   while ( defined $parent_id ) {
      my $results = $self->sqlite->db->select( 'cluster', ['*'], { id => $parent_id } )->hash;
      $parent_id = $results->{parent_id};
      unshift( @names, $results->{name} );
   }
   @names = grep { $_ } @names;
   my $path = join( '/', @names );
   return $path;
}

# user related subroutines

sub login_user {
   my ( $self, $user, $d ) = @_;
   my $results = $self->sqlite->db->select( 'user', ['*'], { token => $d->{token} } )->hash;

   my ( $message, $success );

   if ( $results->{id} ) {
      $user->id( $results->{id} );
      $user->level( $results->{level} );
      $user->org_id( $results->{org_id} );
      $message = 'logged in as ' . $results->{name};
      $success = 1;
   }
   else {
      $message = 'login failed';
      $success = 0;
   }
   return { message => $message, success => $success, user_id => $user->id };
}

sub create_user {
   my ( $self, $user, $d ) = @_;
   my $db = $self->sqlite->db;

   my $user_insert = {
      name           => $d->{name},
      email          => $d->{email},
      remote_address => $user->remote_address,
      level          => defined $d->{level} ? $d->{level} : 1,
   };
   my $user_id;

   eval {
      my $tx = $db->begin;

      # generate org bookmark
      my $bookmark = hmac_sha1_hex( $d->{name}, $self->app->secrets->[1] );

      my $org_id = $d->{org_id} || $db->insert( 'org', { bookmark => $bookmark } )->last_insert_id;
      my $cluster_id;

      my $cluster = $db->select( 'cluster', ['id'], { org_id => $org_id, name => 'monitors' } );
      if ( $cluster->{id} ) {
         $cluster_id = $cluster->{id};
      }
      else {
         $cluster_id = $db->insert( 'cluster', { org_id => $org_id, name => 'monitors', mode => 550 } )->last_insert_id;
      }

      # generate login token
      my $token = hmac_sha1_hex( $d->{name}, $self->app->secrets->[0] );
      $user_insert->{org_id}          = $org_id;
      $user_insert->{base_cluster_id} = $cluster_id;
      $user_insert->{token}           = $token;
      $user_id                        = $db->insert( 'user', $user_insert )->last_insert_id;
      $db->update( 'org', { user_id => $user_id }, { id => $org_id } );
      $db->update( 'cluster', { user_id => $user_id }, { id => $cluster_id } );
      $tx->commit;
   };

   return { message => $@, success => 0 } if $@;
   my $user_info = $db->select( 'user', ['*'], { id => $user_id } )->hash;
   return $user_info;
}

sub read_user {
   my ( $self, $user, $decoded ) = @_;

   my $info = $self->sqlite->db->select( 'user', ['*'], { id => $user->id } )->hash;
   my $path = $self->id2path( $info->{base_cluster_id} );

   return {
      id              => $info->{id},
      org_id          => $info->{org_id},
      name            => $info->{name},
      token           => $info->{token},
      level           => $info->{level},
      email           => $info->{email},
      base_cluster_id => $info->{base_cluster_id},
      mode            => $info->{mode},
      remote_address  => $user->remote_address,
      hostname        => hostname(),
      path            => $path,
      success         => 1,
   };
}

sub update_user {
   my ( $self, $user, $decoded ) = @_;
   eval { $self->sqlite->db->update( 'user', $decoded, { id => $user->id } )->hash; };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

sub delete_user {
   my ( $self, $user, $decoded ) = @_;
   eval { $self->sqlite->db->delete( 'user', { id => $decoded->{id} } )->hash; };
   my $success = $@ ? 0 : 1;
   return { success => $success, id => $decoded->{id} };
}

# job related subroutines

sub _path2name {
   my ( $self, $user, $path ) = @_;
   my ($root)  = $path =~ /^(\/)/;
   my @parts   = split( '/', $path );
   my $name    = pop @parts;
   my $newpath = join( '/', @parts );
   $newpath = $root . $newpath if $root;
   my $cluster_id = $self->path2id( $user, $newpath );
   my $rv         = {
      path       => $newpath,
      name       => $name,
      cluster_id => $cluster_id,
   };

   # cluster found
   unless ( defined $cluster_id && $cluster_id == 0 ) {
      my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
      $rv->{is_writable}   = $self->is_writable( $user, $cluster );
      $rv->{is_readable}   = $self->is_readable( $user, $cluster );
      $rv->{is_executable} = $self->is_executable( $user, $cluster );
      my $job = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, name => $name } )->hash;
      $rv->{job_id} = $job->{id};
   }
   return $rv;
}

sub _job_info {
   my ( $self, $user, $d ) = @_;
   my $job_id;
   my $org_id = $user->org_id;
   if ( $d->{id} ) {
      $job_id = $d->{id};
   }
   elsif ( $d->{name} ) {
      my $ji = $self->_path2name( $user, $d->{name} );
      $job_id = $ji->{job_id};
   }
   return unless $job_id;

   my $sql = <<~"SQL";
      select j.*, c.org_id,
      s.name as server_name, js.state as jobstate
      from job j
      join cluster c on j.cluster_id = c.id
      left join server s on j.server_id = s.id
      left join job_states js on j.state_id = js.id
      where c.org_id = $org_id 
      and j.id = $job_id 
   SQL

   my $job = $self->sqlite->db->query($sql)->hash;

   return unless $job->{id};

   $job->{needs} = $self->_read_job_needs( $user, { id => $job_id } );
   return $job;
}

sub _find_jobs {
   my ( $self, $user, $d ) = @_;
   my $org_id = $user->org_id;

   return { success => 0 } unless $d->{cluster_id};

   my $sql = <<~"SQL";
      select j.*, c.org_id,
      s.name as server_name, js.state as jobstate
      from job j
      join cluster c on j.cluster_id = c.id
      left join server s on j.server_id = s.id
      left join job_states js on j.state_id = js.id
      where c.org_id = $org_id
      and c.id = $d->{cluster_id}
      order by j.id
   SQL

   my @jobs;
   my $results = $self->sqlite->db->query($sql);
   while ( my $j = $results->hash ) {
      my $need_sql = <<~"SQL";
         select jn.job_id, jn.needs_job_id, j.state_id
         from job_needs jn
         join job j on jn.needs_job_id = j.id
         where jn.job_id = $j->{id}
      SQL

      my $need = $self->sqlite->db->query($need_sql);
      my %needs;

      while ( my $jn = $need->hash ) {
         $needs{ $jn->{needs_job_id} } = $jn->{state_id};
      }
      $j->{needs} = \%needs;
      $self->_is_stale( $user, $j ) if $j->{last_update} && $j->{state_id} != $self->job_states->{stale};

      push @jobs, $j;
   }
   return \@jobs;
}

sub _is_stale {
   my ( $self, $user, $job ) = @_;
   my $updated = time - $job->{last_update};
   if ( ( grep { $job->{state_id} == $self->job_states->{$_} } (qw(running watching)) ) && $updated > 20 ) {
      $self->update_job( $user, { id => $job->{id}, state => 'stale' } );
      $job->{state_id} = $self->job_states->{stale};
      $self->_reset_stats( $user, { id => $job->{id} } );
      return 1;
   }
   return;
}

sub create_job {
   my ( $self, $user, $d ) = @_;

   my $j = $self->_path2name( $user, $d->{name} );
   return { success => 0, message => 'a job by that name already exists' } if $j->{job_id};
   return { success => 0, message => 'cluster not found' }                 if defined $j->{cluster_id} && $j->{cluster_id} == 0;
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $j->{is_writable};

   my $insert_hash = { cluster_id => $j->{cluster_id}, name => $j->{name} };
   if ( $d->{shell_command} ) {
      $insert_hash->{shell_command} = $d->{shell_command};
   }

   if ( $d->{server_id} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'], { id => $d->{server_id}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' } unless $res->{id};
      $insert_hash->{server_id} = $res->{id};
   }
   elsif ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'], { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' } unless $res->{id};
      $insert_hash->{server_id} = $res->{id};
   }
   my $id;
   eval { $id = $self->sqlite->db->insert( 'job', $insert_hash )->last_insert_id; };

   if ($@) {
      return { success => 0, message => $@ };
   }
   elsif ( $d->{needs} ) {
      $self->_write_job_needs( $user, { needs => $d->{needs}, id => $id } );
   }
   return { success => 1, id => $id, cluster_id => $j->{cluster_id} };
}

sub read_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );

   return { success => 0, message => 'job not found' } unless $job->{id};
   return { success => 1, %{$job} };
}

sub delete_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   eval {
      #$self->update_job( $user, { id => $job->{id}, state => 'running' } );
      $self->sqlite->db->delete( 'job', { id => $job->{id} } );
   };
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $job->{id} };
}

sub melt_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' }  unless $job->{id};
   return { success => 0, message => 'job not on ice' } unless $job->{state_id} == $self->job_states->{ice};
   eval { $self->sqlite->db->update( 'job', { state_id => $self->job_states->{ready} }, { id => $job->{id} } ); };

   if ($@) {
      return { success => 0, message => $@ };
   }
   return { success => 1 };
}

sub ice_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   eval { $self->sqlite->db->update( 'job', { state_id => $self->job_states->{ice} }, { id => $job->{id} } ); };

   if ($@) {
      return { success => 0, message => $@ };
   }
   return { success => 1 };
}

sub release_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' }   unless $job->{id};
   return { success => 0, message => 'job not on hold' } unless $job->{state_id} == $self->job_states->{hold};

   eval { $self->sqlite->db->update( 'job', { state_id => $self->job_states->{ready} }, { id => $job->{id} } ); };

   if ($@) {
      return { success => 0, message => $@ };
   }
   my $cluster_state = $self->read_cluster( $user, { id => $job->{cluster_id} } )->{state_id};
   return $cluster_state == $self->job_states->{running} ? $self->start_job( $user, { id => $job->{id} } ) : { success => 1 };
}

sub hold_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   return { success => 0, message => 'job is running' } if $job->{state_id} == $self->job_states->{running};
   return $self->update_job( $user, { id => $job->{id}, state => 'hold' } );
}

sub update_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless $job->{id};

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw( signal ppid pid started ended exit_code server_id shell_command)) };
   if ( $d->{state} ) {

      my $failed    = $self->job_states->{failed};
      my $running   = $self->job_states->{running};
      my $killed    = $self->job_states->{killed};
      my $ready     = $self->job_states->{ready};
      my $completed = $self->job_states->{complete};
      my $hold      = $self->job_states->{hold};
      my $ice       = $self->job_states->{ice};
      my $zombie    = $self->job_states->{zombie};

      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
      if ( $d->{state} eq 'running' ) {
         $update_hash->{started} = time;
         $update_hash->{ended}   = undef;

         # set cluster to running if nothing bad
         my $r = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $job->{cluster_id}, id => { '!=', $job->{id} }, state_id => { '=', [ ( $killed, $failed, $zombie ) ] } } );
         if ( my $k = $r->hash ) {

         }
         else {
            $self->_set_cluster_state($user, { state => 'running', id => $job->{cluster_id} });

            #$self->sqlite->db->update( 'cluster', { state_id => $self->job_states->{running}, started => time, ended => undef }, { id => $job->{cluster_id} } );
         }
      }
      elsif ( grep { $d->{state} eq $_ } (qw(failed killed zombie)) ) {
         $update_hash->{ended} = time;
         $self->_reset_stats( $user, { id => $job->{id} } );
         $self->_set_cluster_state($user, { state => 'failed', id => $job->{cluster_id} });
         #$self->sqlite->db->update( 'cluster', { state_id => $self->job_states->{failed}, ended => time }, { id => $job->{cluster_id} } );
      }
      elsif ( $d->{state} eq 'complete' || $d->{state} eq 'fake_complete' ) {

         $self->sqlite->db->update( 'job', { state_id => $self->job_states->{complete} }, { id => $job->{id} } ) unless $d->{state} eq 'fake_complete';

         # find all jobs in ready state that had a dependency met

         my $depends_sql = <<~"SQL";
            select jn.job_id, j.state_id
            from job_needs jn
            join job j on jn.job_id = j.id
            where jn.needs_job_id = $job->{id}
            and j.state_id in ($ready)
         SQL

         #   and j.state_id = $ready
         #   and j.id != $job->{id}

         my $need = $self->sqlite->db->query($depends_sql);
         while ( my $j = $need->hash ) {

            # start job if all dependanciess are complete or on ice

            my $complete_sql = <<~"SQL";
               select jn.needs_job_id, j.state_id
               from job_needs jn
               join job j on jn.needs_job_id = j.id
               where jn.job_id = $j->{job_id}
               and state_id not in ($completed, $ice)
            SQL

            my $ret = $self->sqlite->db->query($complete_sql);

            unless ( $ret->hash ) {
               eval { $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } ) };
               $self->start_job( $user, { id => $j->{job_id} } );
            }
         }
         $update_hash->{ended} = time;
         $self->_reset_stats( $user, { id => $job->{id} } );

         # complete cluster if all jobs completed or on ice
         my $cluster_id = $job->{cluster_id};

         my $c = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $completed, $ice ) ] } } );
         if ( !$c->hash ) {
            #$self->sqlite->db->update( 'cluster', { state_id => $self->job_states->{complete}, ended => time }, { id => $job->{cluster_id} } );
            $self->_set_cluster_state($user, { state => 'complete', id => $job->{cluster_id} });

            # find all clusters in ready state that just had a dependency met

            my $depends_sql = <<~"SQL";
              select c.id, cn.cluster_id, c.state_id
              from cluster_needs cn
              join cluster c on cn.cluster_id = c.id
              where cn.needs_cluster_id = $cluster_id
              and c.state_id in ($ready)
            SQL

            #   and j.state_id = $ready
            #   and j.id != $job->{id}

            my $cneed = $self->sqlite->db->query($depends_sql);

            while ( my $c = $cneed->hash ) {

               # start cluster if all dependanciess are complete or on ice

               my $cluster_sql = <<~"SQL";
                  select cn.needs_cluster_id, c.state_id
                  from cluster_needs cn
                  join cluster c on cn.needs_cluster_id = c.id
                  where cn.cluster_id = $c->{id}
                  and c.state_id not in ($completed, $ice)
               SQL

               my $ret = $self->sqlite->db->query($cluster_sql);

               unless ( $ret->hash ) {
                  #eval { $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } ) };
                  $self->start_cluster( $user, { id => $c->{id} } );
               }
            }
         }
      }
   }
   if ( $d->{needs} ) {
      $self->_write_job_needs( $user, { needs => $d->{needs}, id => $job->{id} } );
   }
   if ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'], { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' } unless $res->{id};
      $update_hash->{server_id} = $res->{id};
   }
   $update_hash->{name}        = $d->{newname} if $d->{newname};
   $update_hash->{last_update} = time;
   eval { $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } ) };
   my $success = $@ ? 0 : 1;
   return { success => $success, %{$update_hash} };
}

sub _read_job_needs {
   my ( $self, $user, $d ) = @_;
   my $need_sql = <<~"SQL";
         select jn.job_id, jn.needs_job_id, j.state_id
         from job_needs jn
         join job j on jn.needs_job_id = j.id
         where jn.job_id = $d->{id}
      SQL

   my $need = $self->sqlite->db->query($need_sql);
   my %needs;

   while ( my $jn = $need->hash ) {
      $needs{ $jn->{needs_job_id} } = $jn->{state_id};
   }
   return \%needs;
}

sub _write_job_needs {
   my ( $self, $user, $d ) = @_;

   my $needs;
   if ( ref $d->{needs} eq 'ARRAY' ) {
      my @n = grep { $_ =~ /^\d{1,10}$/ } @{ $d->{needs} };
      $needs = $self->sqlite->db->select( 'job', ['id'], { id => { '=', [@n] } } )->hashes->to_array;
   }
   else {
      return { success => 0, message => 'not an array reference' };
   }

   $self->sqlite->db->delete( 'job_needs', { job_id => $d->{id} } );
   foreach my $need ( @{$needs} ) {
      $self->sqlite->db->insert( 'job_needs', { job_id => $d->{id}, needs_job_id => $need->{id} } );
   }
}

sub _write_cluster_needs {
   my ( $self, $user, $d ) = @_;

   my $needs;
   return unless ref $d->{needs} eq 'ARRAY';
   my @n = grep { $_ =~ /^\d{1,10}$/ } @{ $d->{needs} };
   $needs = $self->sqlite->db->select( 'cluster', ['id'], { id => { '=', [@n] } } )->hashes->to_array;

   $self->sqlite->db->delete( 'cluster_needs', { cluster_id => $d->{id} } );
   foreach my $need ( @{$needs} ) {
      $self->sqlite->db->insert( 'cluster_needs', { cluster_id => $d->{id}, needs_cluster_id => $need->{id} } );
   }
}

sub _read_cluster_needs {
   my ( $self, $user, $d ) = @_;

   return unless $d->{id};

   my $need_sql = <<~"SQL";
      select cn.cluster_id, cn.needs_cluster_id, c.state_id
      from cluster_needs cn
      join cluster c on cn.needs_cluster_id = c.id
      where cn.cluster_id = $d->{id}
   SQL

   my $need = $self->sqlite->db->query($need_sql);
   my %needs;

   while ( my $cn = $need->hash ) {
      $needs{ $cn->{needs_cluster_id} } = $cn->{state_id};
   }
   return \%needs;
}

sub _ping {
   my ( $self, $host ) = @_;
   return unless $host;
   my $output = `ping -c 1 $host 2>&1`;
   if ( $output =~ /min\/avg\/max\/(mdev|stddev) = ([\d.]+)\/([\d.]+)\/([\d.]+)/ ) {
      return $3;
   }
}

sub update_sysinfo {
   my ( $self, $user, $d ) = @_;
   return { success => 0, exit => 1, message => 'missing server id' } unless $d->{id};

   my $server = $self->_server_info( $user, { id => $d->{id} } );
   return { success => 0, exit => 1, message => 'server not found' } unless $server;

   my $uh = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(total_memory used_memory cpu total_disk used_disk uptime)) };

   #my $result = $self->sqlite->db->select( 'server', ['*'], { id => $d->{id} } )->hash;
   my $ssh = $self->ssh_connection->{ $server->{id} };
   return { success => 0, exit => 1 } unless $server->{id} && $ssh && $ssh->check_master;
   $uh->{ping}        = $self->_ping( $server->{hostname} ) if $server->{hostname};
   $uh->{update_time} = time;
   my $running  = $self->job_states->{running};
   my $watching = $self->job_states->{watching};

   # receive pid info
   if ( $d->{pids} && ref $d->{pids} eq 'ARRAY' ) {

      foreach my $pid ( @{ $d->{pids} } ) {
         my $update = { map { $_, $pid->{$_} } grep { exists $pid->{$_} } (qw(pctcpu pid time start size priority rss pctmem ppid state cmndline fname)) };
         $update->{last_update} = time;
         $self->sqlite->db->update( 'job', $update, { pid => $pid->{pid} } );
      }
   }

   # identify zombies
   if ( $d->{zombies} && ref $d->{zombies} eq 'ARRAY' ) {
      my $ids = $self->sqlite->db->select( 'job', [ 'id', 'state_id' ], { pid => $d->{zombies}, state_id => [ $running, $watching ] } );
      while ( my $next = $ids->hash ) {
         $self->update_job( $user, { state => 'zombie', ended => time, id => $next->{id} } );
      }
   }

   # send pid request
   my @pids;
   my $pids = $self->sqlite->db->select( 'job', ['pid'], { server_id => $d->{id}, pid => { '!=', undef }, state_id => [ $running, $watching ] } );
   while ( my $next = $pids->hash ) {
      push @pids, $next->{pid};
   }

   eval { $self->sqlite->db->update( 'server', $uh, { id => $d->{id} } ) };
   return $@ ? { success => 0, message => $@ } : { success => 1, pids => \@pids };
}

sub watch_job {
   my ( $self, $user, $d ) = @_;

   return { success => 0, message => 'missing pid or match' } unless ( $d->{pid} || $d->{match} );

   my $server = $self->_server_info( $user, { id => $d->{server_id}, name => $d->{server} } );
   return { success => 0, message => 'server not found' } unless $server;

   # check connection
   my $ssh = $self->ssh_connection->{ $server->{id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $server->{id} } );
      $ssh = $self->ssh_connection->{ $server->{id} };
   }

   my $cmd =
     $d->{pid}
     ? "perl cc_worker/script/find_pid.pl $d->{pid}"
     : "perl cc_worker/script/find_match.pl $d->{match}";

   my ( $out, $err ) = $ssh->capture2($cmd);
   return { success => 0, message => $ssh->error } if $ssh->error;

   my ($pid) = $out =~ /^(\d+)$/;
   return { success => 0, message => 'pid not found' } unless $pid;

   my $job_info = $self->create_job( $user, $d );
   return $job_info unless $job_info->{success};

   return $self->update_job( $user, { id => $job_info->{id}, state => 'watching', pid => $pid, ended => undef, started => time } );
}

sub top_jobs {
   my ( $self, $user, $d ) = @_;
   my $server = $self->_server_info( $user, { id => $d->{server_id}, name => $d->{name} } );
   return { success => 0, message => 'server not found' } unless $server;

   my $count = $d->{count} || 10;
   my $sort  = $d->{sort}  || 'pctcpu';
   $sort = ( grep { $sort eq $_ } (qw(pctmem pctcpu time rss start pid ppid)) )[0];
   return { success => 0, message => 'sort field missing' } unless $sort;

   my $ssh = $self->ssh_connection->{ $server->{id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $server->{id} } );
      $ssh = $self->ssh_connection->{ $server->{id} };
   }

   my $cmd = "perl cc_worker/script/top.pl $sort $count";
   my ( $out, $err ) = $ssh->capture2($cmd);
   return { success => 0, message => $ssh->error } if $ssh->error;
   my $json;
   eval { $json = decode_json($out) };
   return $@ ? { success => 0, message => $@ } : { success => 1, jobs => $json };
}

sub start_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, skipped => 1, message => 'job not found' } unless $job->{id};
   return { success => 0, skipped => 1, message => 'job is already running' } if $self->job_states->{running} == $job->{state_id};

   # skip if job on ice
   if ( $job->{state_id} == $self->job_states->{ice} ) {
      $self->update_job( $user, { id => $job->{id}, state => 'fake_complete' } );
      return { success => 0, skipped => 1, message => 'job on ice' };
   }

   # don't start if dependencies not satisfied
   while ( my ( $id, $state_id ) = each %{ $job->{needs} } ) {
      if ( !grep { $state_id == $self->job_states->{$_} } (qw(complete ice)) ) {
         return { success => 0, skipped => 1, message => 'dependencies not satisfied' };
      }
   }

   my $server = $self->_server_info( $user, { id => $job->{server_id} } );
   unless ($server) {
      $self->update_job( $user, { id => $job->{id}, state => 'failed' } );
      return { success => 0, message => 'server not found' };
   }

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $job->{server_id} } );
      $ssh = $self->ssh_connection->{ $job->{server_id} };
   }

   my $token    = $self->read_user($user)->{token};
   my $json     = encode_json( { token => $token, id => $job->{id}, shell => $job->{shell_command} } );
   my $json_hex = unpack( 'H*', $json );
   my $cmd      = "perl cc_worker/script/launcher.pl $json_hex";

   $ssh->spawn($cmd);
   #$ssh->system($cmd);

   if ( $ssh->error ) {
      $self->update_job( $user, { state => 'failed', ended => time }, { id => $job->{id} } );
      return { success => 0, message => $ssh->error };
   }
   else {
      return { success => 1 };
   }
}

# job states
#(1,'inactive');
#(2,'ready');
#(3,'starting');
#(4,'running');
#(5,'complete');
#(6,'failed');
#(7,'hold');
#(8,'ice');
#(9,'killed');

sub kill_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' }      unless ref $job && $job->{id};
   return { success => 0, message => 'job is not running' } unless $job->{state_id} == $self->job_states->{running};

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;

   $ssh->system("perl -e 'kill TERM, $job->{pid}'");
   return $ssh->error ? { success => 0, message => $ssh->error } : { success => 1 };
}

sub nice_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   my $pid = $job->{pid};
   return { success => 0, message => 'job not found' } unless ref $job && $job->{id};

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;

   $ssh->system("renice -n 19 -p $job->{pid}");
   return $ssh->error ? { success => 0, message => $ssh->error } : { success => 1 };
}

sub _reset_stats {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless ref $job && $job->{id};
   my %update = map { $_ => undef } (qw(signal ppid pid exit_code pctcpu time start size priority rss pctmem state cmndline fname));
   eval { $self->sqlite->db->update( 'job', \%update, { id => $job->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

# server related subroutines

sub ssh_copy {
   my ( $self, $user, $d ) = @_;
   my $s = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless $s;
   return { success => 0 }                                unless $s->{password} && $s->{username} && $s->{hostname};
   $self->_ssh_copy( $user, $s );
   return { success => 1 };
}

sub _ssh_copy {
   my ( $self, $user, $d ) = @_;
   my $port = $d->{port} || 22;

   # copy public ssh key to remote host
   my $copy_key  = "sshpass -p $d->{password} ssh-copy-id -p $port $d->{username}\@$d->{hostname}";
   my $exit_code = system($copy_key);
   my $success   = $exit_code ? 0 : 1;
   return { success => $success, exit_code => $exit_code };
}

# install
sub _install_monitor {
   my ( $self, $user, $d ) = @_;
   my $s = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless $s;

   # check connection
   my $ssh = $self->ssh_connection->{ $s->{id} };
   $self->_connect_ssh( $user, { id => $s->{id} } ) unless ( $ssh && $ssh->check_master );
   $ssh = $self->ssh_connection->{ $s->{id} };

   # install
   eval {
      # copy cc_worker directory to remote server
      $ssh->scp_put( { recursive => 1 }, "$Bin/../cc_worker" );

      #or die "scp failed: " . $ssh->error;

      my $token = $self->read_user($user)->{token};
      my $json  = encode_json( { token => $token, id => $s->{id} } );

      # install perl modules in background
      my $spawn = "perl cc_worker/script/install.pl";
      $ssh->spawn($spawn);

      # gather basic info about remote system
      my ( $out, $err ) = $ssh->capture2("perl cc_worker/script/basicinfo.pl");
      my $error = $ssh->error || $err;
      return { success => 0, message => $error } if $error;
      my $basicinfo = decode_json($out);
      my $update    = { map { $_, $basicinfo->{$_} } grep { exists $basicinfo->{$_} } (qw(home os cores cwd)) };
      $self->sqlite->db->update( 'server', $update, { id => $s->{id} } );
   };
   return $@ ? { success => 0, message => $@ } : { success => 1 };
}

sub create_monitor {
   my ( $self, $user, $d ) = @_;
   my $token = $self->read_user($user)->{token};

   $self->_ssh_copy( $user, $d ) if $d->{password};

   my $port        = $d->{port} || 22;
   my $insert_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(name username hostname password)) };
   $insert_hash->{port}   = $port;
   $insert_hash->{org_id} = $user->org_id;

   my $id;
   eval { $id = $self->sqlite->db->insert( 'server', $insert_hash )->last_insert_id; };

   if ($@) {
      return { success => 0, message => $@ };
   }
   else {

      $self->_connect_ssh( $user, { id => $id } );
      $self->_install_monitor( $user, { id => $id } );
      $self->_start_monitor( $user, { id => $id } );
      my $server = $self->_server_info( $user, { id => $id } );

      my $json     = encode_json( { token => $token, id => $id } );
      my $monitors = $self->sqlite->db->select( 'cluster', ['id'], { org_id => $user->org_id, name => 'monitors', parent_id => undef } )->hash;
      my $cluster_id;
      $cluster_id = $monitors->{id};
      unless ($cluster_id) {
         my $c = $self->create_cluster( $user, { name => '/monitors' } );
         $cluster_id = $c->{id};
      }

      my $cwd = $server->{cwd} || '';

      my $rv = $self->create_job( $user, { name => "/monitors/$d->{name}", shell_command => "$cwd/cc_worker/script/sysinfo.pl $json", server_id => $id } );
      return $self->start_job( $user, { id => $rv->{id} } ) if $rv->{success};
   }
}

sub read_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->sqlite->db->select( 'server', ['*'], { org_id => $user->org_id } );
   my @s;
   while ( my $server = $servers->hash ) {
      my $info = { map { $_, $server->{$_} } (qw(id os cwd home cores update_time ping username hostname name port total_memory used_memory cpu total_disk used_disk uptime)) };
      push @s, $info;
   }
   return scalar @s ? { success => 1, servers => \@s } : { success => 0 };
}

sub _server_info {
   my ( $self, $user, $d ) = @_;
   my $select =
       $d->{id}   ? { id => $d->{id}, org_id => $user->org_id }
     : $d->{name} ? { org_id => $user->org_id, name => $d->{name} }
     :              undef;

   #:              { org_id => $user->org_id };

   return unless $select;
   my $server = $self->sqlite->db->select( 'server', ['*'], $select )->hash;

   #my $ssh       = $self->ssh_connection->{ $next->{id} };
   #my $connected = $ssh && $ssh->check_master ? 1 : 0;
   return unless $server;

   my $info = { map { $_, $server->{$_} } (qw(id os cwd home cores update_time ping username hostname name port total_memory used_memory cpu total_disk used_disk uptime)) };
   return $info;
}

sub _disconnect_ssh {
   my ( $self, $user, $d ) = @_;
   my $s = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless $s;
   my $ssh = $self->ssh_connection->{ $s->{id} };
   if ($ssh) {
      $ssh->disconnect(0);
   }
   return { success => 1 };
}

# refresh ssh connection
sub _connect_ssh {
   my ( $self, $user, $d ) = @_;
   my $token = $self->read_user($user)->{token};
   my $s     = $self->_server_info( $user, $d );
   return { success => 0, message => 'server not found' } unless $s;

   return { success => 0, message => 'server misconfigured' } unless $s->{id} && $s->{username} && $s->{hostname};
   my $port    = $s->{port} || 22;
   my $old_ssh = $self->ssh_connection->{ $s->{id} };
   if ( $old_ssh && ref $old_ssh ) {
      $old_ssh->disconnect(0);
      undef $old_ssh;
      undef $self->ssh_connection->{ $s->{id} };
   }

   my %option = (
      user       => $s->{username},
      port       => $port,
      batch_mode => 1,
      timeout    => 3,

      #kill_ssh_on_timeout => 1,
      #master_opts => [-o => "ControlPersist=10m" ],
      master_opts => [ -o => "ControlMaster=auto" ],
   );

   my $ssh = Net::OpenSSH->new( $s->{hostname}, %option );

   return { success => 0, message => $ssh->error } if $ssh->error || !$ssh->check_master;

   # add connection
   $self->ssh_connection->{ $s->{id} } = $ssh;

   return { success => 1 };
}

sub _start_monitor {
   my ( $self, $user, $d ) = @_;
   my $token = $self->read_user($user)->{token};
   my $s     = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless $s;
   my $ssh = $self->ssh_connection->{ $s->{id} };
   $self->_connect_ssh( $user, { id => $s->{id} } ) unless ( $ssh && $ssh->check_master );
   $ssh = $self->ssh_connection->{ $s->{id} };
   return { success => 1, message => 'monitor started' };
}

# disconnect ssh session
sub stop_monitor {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_disconnect_ssh( $user, $d );
   return $rv;
}

sub start_monitor {
   my ( $self, $user, $d ) = @_;
   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

   my $job = $self->_job_info( $user, { name => "/monitors/$server->{name}" });

   return { success => 0, message => 'monitor job not found' } unless $job->{id};
   return $self->start_job( $user, { id => $job->{id} } );
}

sub update_monitor {
   my ( $self, $user, $d ) = @_;
   return { success => 1 };
}

sub upgrade_monitor {
   my ( $self, $user, $d ) = @_;
   return $self->_install_monitor( $user, $d );
}

sub delete_monitor {
   my ( $self, $user, $d ) = @_;
   return { success => 0, message => 'missing name or id' } unless $d->{name} || $d->{id};
   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'server not found' } unless $server;
   my $id = $server->{id};
   my $ci = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => undef, name => 'monitors', org_id => $user->org_id } )->hash;

   if ( $ci->{id} ) {
      $self->sqlite->db->delete( 'job', { cluster_id => $ci->{id}, name => $server->{name} } );
   }
   my $rows    = $self->sqlite->db->delete( 'server', { id => $id } )->rows;
   my $success = $rows ? 1 : 0;
   $self->_disconnect_ssh( $user, { id => $id } );
   delete $self->ssh_connection->{$id};
   return { success => $success };
}

# cron related subroutines

# add row to cron table and return id
sub _create_cron_row {
   my ( $self, $user, $d ) = @_;
   # cron tz cal_id

   my $crontab = $d->{cron};
   $crontab =~ s/^\s+|\s+$//g;
   $crontab =~ s/\s+/ /g;
   
   eval {
      my $cron = DateTime::Event::Cron->new($crontab);
   };
   
   return if $@;

   my $id = $self->sqlite->db->insert( 'cron', { value => $crontab, tz => $d->{tz}, cal_id => $d->{cal_id}, org_id => $user->org_id } )->last_insert_id;
   return $id;
}

sub _create_cron_object {
   my ( $self, $user, $d ) = @_;
   # cron_id cluster_id tz

   my $c = $self->sqlite->db->select( 'cron', ['value', 'tz'], { id => $d->{cron_id} } )->hash;
   my $crontab = $c->{value};
   my $tz = $c->{tz} || 'UTC';
   return unless $crontab;

   my $cron;
   
   eval {
      $cron = DateTime::Event::Cron->new($crontab);
   };

   return if $@;

   $self->cron->{ $d->{cron_id} } = EV::periodic (
      0,
      0,
      sub {
         my ($watcher, $now) = @_;
         return $cron->next(DateTime->from_epoch(epoch => $now, time_zone => $tz))->epoch;
      },
      sub {
         $self->start_cluster($user, { id => $d->{cluster_id} });
         print "start cluster: " . $d->{cluster_id} . " " . time . "\n";
      }
   );
}

sub _delete_cron {
   my ( $self, $user, $d ) = @_;
   # cron_id
   
   my $w = $self->cron->{ $d->{cron_id} };
   $w->stop if $w && $w->is_active;
   delete $self->cron->{ $d->{cron_id} };
   $self->sqlite->db->delete( 'cron', { id => $d->{cron_id} } );
   print "delete cron timer: $d->{cron_id} " . time . "\n";
   return $@ ? 0 : 1;
}

# at related subroutines:

# add row to at table and return id
sub _create_at_row {
   my ( $self, $user, $d ) = @_;
   # at cal_id
   
   eval {
      my $time = localtime($d->{at});
   };

   return if $@;

   my $seconds = $d->{at} - time;
   return unless $seconds > 0; # future times only

   my $id = $self->sqlite->db->insert( 'at', { value => $d->{at}, cal_id => $d->{cal_id}, org_id => $user->org_id } )->last_insert_id;
   return $id;
}

# create, validate, and return at timer
sub _create_at_object {
   my ( $self, $user, $d ) = @_;
   # at_id cluster_id

   my $at = $self->sqlite->db->select( 'at', ['value'], { id => $d->{at_id} } )->hash->{value};
   return unless $at;

   eval {
      my $time = localtime($at);
   };

   return if $@;

   my $seconds = $at - time; 
   return unless $seconds > 0; # future times only

   $self->at->{ $d->{at_id} } = EV::timer $seconds, 0, sub {
      $self->start_cluster($user, { id => $d->{cluster_id} });
      print "start cluster: $d->{cluster_id} " . time . "\n";
      $self->_delete_at($user, { at_id => $d->{at_id} });
   };
}

sub _delete_at {
   my ( $self, $user, $d ) = @_;
   # at_id

   my $w = $self->at->{ $d->{at_id} };
   $w->stop if $w && $w->is_active;
   delete $self->at->{ $d->{at_id} };
   $self->sqlite->db->delete( 'at', { id => $d->{at_id} } );
   print "delete at timer: $d->{at_id} " . time . "\n";
   return $@ ? 0 : 1;
}

# cal related subroutines

sub _delete_cal {
   my ( $self, $user, $d ) = @_;
   # cal_id

   eval {
      my $tx = $self->sqlite->db->begin;
      $self->sqlite->db->delete( 'cal', { id => $d->{cal_id} } );
      $tx->commit;
   };
   print "delete cal: $d->{cal_id} " . time . "\n";
   return $@ ? 0 : 1;
}

sub _create_cal {
   my ( $self, $user, $d ) = @_;
}

# command routing

sub routing {
   state $i  = qr/^\d{1,20}$/;              # integer
   state $w  = qr/^\w{1,50}$/;              # word
   state $f  = qr/^[\d\.]{1,20}$/;          # float
   state $p  = qr/^[\w\/\@\:\.]{1,50}$/;    # path
   state $e  = qr/^[\w\.\@]{1,50}$/;        # email
                                            # state $c  = qr/^[\w\/\@\:\.\s\-\(\)\"\']{1,50}$/;    # shell command
   state $c  = qr/.{1,60}/;                 # shell command
   state $pw = qr/^.{8,20}$/;               # password
   state $ct = qr/^((\S{1,12})\s+(\S{1,12})\s+(\S{1,12})\s+(\S{1,12})\s+(\S{1,12})|\s*)$/;         # cron
   state $at = qr/^(\d+|\s*)$/;         # at

   state %routing = (

      # user related
      'create_user' => [ \&create_user, 3, [ { name => $w }, { org_id => $i, email => $w, level => $i } ] ],
      'read_user'   => [ \&read_user,   1, [ {},             {} ] ],
      'update_user' => [ \&update_user, 1, [ {},             { email => $e, name => $w } ] ],
      'delete_user' => [ \&delete_user, 3, [ { id => $i }, {} ] ],
      'login_user'  => [ \&login_user,  0, [ { token => $w }, {} ] ],

      # job related
      'create_job' => [ \&create_job, 1, [ { name => $p, shell_command => $c }, { needs => 's', server => $w, description => $w, out_log_path => $w, err_log_path => $w } ] ],
      'read_job'   => [ \&read_job,   1, [ {}, { name => $p, id => $i, cluster_id => $i } ] ],
      'update_job' => [
         \&update_job,
         1,
         [
            {},
            {
               name          => $p,
               id            => $i,
               signal        => $i,
               exit_code     => $i,
               server_id     => $i,
               mem           => $f,
               cpu           => $f,
               newname       => $w,
               state         => $w,
               server        => $w,
               ppid          => $i,
               pid           => $i,
               shell_command => $c,
               started       => $i,
               needs         => 's',
               ended         => $i,
            }
         ]
      ],
      'delete_job'  => [ \&delete_job,  1, [ {}, { name  => $p, id   => $i } ] ],
      'start_job'   => [ \&start_job,   1, [ {}, { name  => $p, id   => $i } ] ],
      'watch_job'   => [ \&watch_job,   1, [ {}, { name  => $p, id   => $i, server_id => $i, server => $w, pid => $i, match => $c } ] ],
      'kill_job'    => [ \&kill_job,    1, [ {}, { name  => $p, id   => $i } ] ],
      'nice_job'    => [ \&nice_job,    1, [ {}, { name  => $p, id   => $i } ] ],
      'hold_job'    => [ \&hold_job,    1, [ {}, { name  => $p, id   => $i } ] ],
      'release_job' => [ \&release_job, 1, [ {}, { name  => $p, id   => $i } ] ],
      'ice_job'     => [ \&ice_job,     1, [ {}, { name  => $p, id   => $i } ] ],
      'melt_job'    => [ \&melt_job,    1, [ {}, { name  => $p, id   => $i } ] ],
      'finish_job'  => [ \&finish_job,  1, [ {}, { name  => $p, id   => $i } ] ],
      'top_jobs'    => [ \&top_jobs,    1, [ {}, { count => $i, sort => $w, server_id => $i, name => $p, id => $i } ] ],

      #'copy_job'   => [ \&copy_job,   1, [ {},              { name => $p, id => $i, to => $p } ] ],

      # cluster related
      'create_cluster' => [ \&create_cluster, 1, [ { name => $p }, { needs => 's', description => $w, cron => $ct, at => $at, cal => $w, cal_id => $i, tz => $p } ] ],
      'read_cluster'   => [ \&read_cluster,   1, [ {},             { name  => $p,  id          => $i } ] ],
      'update_cluster' => [ \&update_cluster, 1, [ {}, { id => $i, name => $p, needs => 's', newname => $w, description => $w, cron => $ct, at => $at, cal => $w, cal_id => $i, tz => $p } ] ],
      'delete_cluster' => [ \&delete_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'change_cluster' => [ \&change_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'find_cluster'   => [ \&find_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'reset_cluster'  => [ \&reset_cluster,  1, [ {}, { name => $p, id   => $i } ] ],
      'start_cluster'  => [ \&start_cluster,  1, [ {}, { id   => $i, name => $p } ] ],
      #'copy_cluster'   => [ \&copy_cluster,   1, [ {}, { name => $p, id => $i, to => $p } ] ],

      # calendar related
      'create_cal' => [ \&create_cal, 1, [ { name => $w }, {} ] ],
      'read_cal'   => [ \&read_cal,   1, [ {}, { name  => $w,  id => $i } ] ],
      'update_cal' => [ \&update_cal, 1, [ {}, { id => $i, name => $w, addcron => $ct, rmcron_id => $i, addat => $i, rmat_id => $i } ] ],
      'delete_cal' => [ \&delete_cal, 1, [ {}, { name => $p, id   => $i } ] ],

      # monitor related
      'create_monitor'  => [ \&create_monitor,  1, [ { name => $w, username => $w, hostname => $p }, { password => $pw } ] ],
      'read_monitor'    => [ \&read_monitor,    1, [ {},                                             { id       => $i, name => $p } ] ],
      'update_monitor'  => [ \&update_monitor,  1, [ {},                                             { id       => $i, name => $p, newname => $w, username => $w, hostname => $p } ] ],
      'delete_monitor'  => [ \&delete_monitor,  1, [ {},                                             { id       => $i, name => $p } ] ],
      'ssh_copy'        => [ \&ssh_copy,        1, [ { name => $w, username => $w, hostname => $p }, { password => $pw } ] ],
      'stop_monitor'    => [ \&stop_monitor,    1, [ {},                                             { id       => $i, name => $p } ] ],
      'start_monitor'   => [ \&start_monitor,   1, [ {},                                             { id       => $i, name => $p } ] ],
      'upgrade_monitor' => [ \&upgrade_monitor, 1, [ {},                                             { id       => $i, name => $p } ] ],
      'update_sysinfo'  => [
         \&update_sysinfo,
         1,
         [
            {
               free_memory  => $i,
               used_memory  => $i,
               total_memory => $i,
               free_disk    => $i,
               used_disk    => $i,
               total_disk   => $i,
               uptime       => $f,
               cpu          => $f,
               pids         => 's',
               zombies      => 's',
               id           => $i,
            },
            {}
         ]
      ],
   );
   return \%routing;
}

EV::run;

1;
