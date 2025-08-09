package ordo;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use ordo::Model::User;
use JSON;
use Digest::SHA qw(hmac_sha1_hex);
use FindBin     qw($Bin);
use Net::OpenSSH;
use Sys::Hostname;
use POSIX ":sys_wait_h";
use EV;
use DateTime;
use DateTime::Event::Cron::Quartz;
use Data::Dumper;

# TODO: logs, time series stats, runtime alarms, state alarms, threshold alarms, eggs (lay, hatch, rezrov, blorb)
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
         print "API\n";
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

   # start monitors

   my $monitor_sql = <<~"SQL";
      select s.id as server_id, j.id as job_id, j.name, s.name, j.state_id, u.org_id, min(u.id) as user_id, u.token
      from job j 
      join cluster c on j.cluster_id = c.id
      join server s on s.name = j.name
      join user u on u.org_id = c.org_id
      where c.name = 'monitors' and c.parent_id IS NULL
      group by j.id
   SQL

   my $results = $self->sqlite->db->query($monitor_sql);
   while ( my $s = $results->hash ) {
      my $user = ordo::Model::User->new( id => $s->{user_id}, org_id => $s->{org_id} );
      $self->_install_monitor( $user, { id => $s->{server_id} } );
      $self->_start_monitor( $user, { id => $s->{server_id} } );

      # start_monitor if monitor job left in running state
      if ( scalar grep { $s->{state_id} == $self->job_states->{$_} } (qw(starting running)) ) {
         $self->stop_monitor( $user, { id => $s->{server_id} } );
         $self->start_monitor( $user, { id => $s->{server_id} } );
      }
   }

   # delete old crons
   $self->sqlite->db->delete( 'cron', { expire => { '<', time } } );

   # load cron timers
   my $cron_timers_sql = <<~"SQL";
      select cal.id as cal_id, cal.org_id as org_id, cron.id as cron_id, min(user.id) as user_id
      from cron 
      join cal on cron.cal_id = cal.id
      join user on cal.org_id = user.org_id
      group by cron.id
   SQL

   my $cron_timers = $self->sqlite->db->query($cron_timers_sql);
   while ( my $a = $cron_timers->hash ) {
      my $count = $self->sqlite->db->query("select count(*) as count from cluster where cal_id = $a->{cal_id}")->hash->{count};
      next unless $count;
      my $user = ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      $self->_create_cron_object( $user, { id => $a->{cron_id} } );
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

      #$optional->{request_id} = $i;    # request_id added by client to every request
      $optional->{token} = $w;                    # token added for rest api
      $optional->{tz}    = qr/^[\w\/]{3,50}$/;    # added for cron
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
            unless ( ( $regex eq 's' && ref $params->{$param} eq 'ARRAY' ) || $params->{$param} =~ $regex ) {
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

   #$response->{request_id}    = $params->{request_id} if $params->{request_id};
   return $response;
}

# cluster related subroutines

sub _has_permission {

   # id (cluster)
   #my ( $self, $bits, $user, $cluster ) = @_;
   my ( $self, $bits, $user, $d ) = @_;

   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id}, org_id => $user->org_id } )->hash;

   return 0 unless $cluster->{id};
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

sub _cluster_info {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );
   return if defined $cluster_id && $cluster_id == 0;
   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
   return $cluster;
}

sub read_cluster {
   my ( $self, $user, $d ) = @_;

   my $cluster = $self->_cluster_info( $user, $d );

   return { success => 0, message => 'cluster not found' } unless $cluster && $cluster->{id};
   my $cluster_id = $cluster->{id};

   my $is_readable = $self->is_readable( $user, { id => $cluster_id } );
   return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;

   my @fields = qw(id cal_id mode org_id user_id parent_id server_id state_id name description started ended);
   my %rv     = map { $_, $cluster->{$_} } @fields;
   $rv{jobstate}   = $self->sqlite->db->select( 'job_states', ['state'], { id => $rv{state_id} } )->hash->{state} if $rv{state_id};
   $rv{cal}        = $self->sqlite->db->select( 'cal', ['name'], { id => $rv{cal_id} } )->hash->{name} if $rv{cal_id};
   $rv{needs}      = $self->_read_cluster_needs( $user, { id => $cluster_id } );
   $rv{next_start} = $self->_cal_next_start( $user, { id => $rv{cal_id} } ) if $rv{cal_id};
   return { success => 1, %rv };
}

sub _set_cluster_state {
   my ( $self, $user, $d ) = @_;

   # id state

   my $state_id = $self->job_states->{ $d->{state} };
   return unless $state_id;

   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id} } )->hash;
   my $current_state_id = $cluster->{state_id}; 
   #$self->sqlite->db->select( 'cluster', ['state_id'], { id => $d->{id} } )->hash->{state_id};
   return if $current_state_id && $current_state_id == $state_id;

   my $update_hash = { state_id => $state_id };

   if ( $d->{state} eq 'running' ) {
      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      # max duration hook
   }
   elsif ( $d->{state} eq 'complete' ) {
      $update_hash->{ended} = time;
   }
   elsif ( $d->{state} eq 'failed' ) {
      $update_hash->{ended} = time;

      # fail hook
      if ( $cluster->{fail_hook} ) {
         my $hook_cluster = $self->sqlite->db->select( 'cluster', ['id'], { id => $cluster->{fail_hook} } );
         if ( $hook_cluster->{id} ) {
            $self->_start_cluster( $user, { id => $hook_cluster->{id}, force => 1 } );
         }
      }
   }
   $self->sqlite->db->update( 'cluster', $update_hash, { id => $d->{id} } );
}

sub start_cluster {
   my ( $self, $user, $d ) = @_;
   $self->_start_cluster( $user, $d );
}

sub _start_cluster {
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

   if ( $cluster_info->{state_id} == $self->job_states->{running} ) {

      return { success => 0, message => 'cluster already running' };

      # TODO: add IGNORE, CLONE, QUEUE, or NOTIFY options
   }

   unless ( $d->{force} ) {

      # return if needs not met
      while ( my ( $id, $state_id ) = each %{ $cluster_info->{needs} } ) {
         if ( !grep { $state_id == $self->job_states->{$_} } (qw(complete ice)) ) {

            # ALARM: dependency not met
            #$self->_set_cluster_state( $user, { state => 'failed', id => $cluster_id } );
            return { success => 0, skipped => 1, message => "dependency not met. use --force to start anyway" };
         }
      }
   }

   #my $jobs_ready = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => [ ( $complete, $ready ) ] }, { limit => 1 } );
   #return { success => 0, message => 'no jobs to start' } unless $jobs_ready->hash;

   my $not_ready = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $complete, $ready, $hold, $ice ) ] } }, { limit => 1 } );
   return { success => 0, message => 'jobs not ready' } if $not_ready->hash;

   $self->_reset_cluster( $user, { id => $cluster_id } );

   #return { success => 0, message => $@ } if $@;

   my $results = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => { '=', [$ready] } }, { -desc => 'id' } )->hashes;

   my $jobs_started = 0;
   my $jobs_failed  = 0;
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
      $self->_set_cluster_state( $user, { state => 'failed', id => $cluster_id } );
      return { success => 0, message => "$jobs_failed failed jobs: $error" };
   }
   elsif ($jobs_started) {
      $self->_set_cluster_state( $user, { state => 'running', id => $cluster_id } );
      return { success => 1, message => "$jobs_started jobs started, $jobs_skipped jobs skipped" };
   }
   else {
      $self->_set_cluster_state( $user, { state => 'running',  id => $cluster_id } );
      $self->_set_cluster_state( $user, { state => 'complete', id => $cluster_id } );
      return { success => 1, message => "nothing to start" };
   }
}

sub _reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};
   my $hold         = $self->job_states->{hold};
   my $ice          = $self->job_states->{ice};

   $self->_set_cluster_state( $user, { state => 'ready', id => $cluster_id } );

   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $hold, $ice ) ] } } );
   while ( my $job = $jobs->hash ) {
      my $needs = $self->_read_job_needs( $user, { id => $job->{id} } );
      my $state = scalar keys %$needs ? 'waiting' : 'ready';
      $self->_set_job_state( $user, { id => $job->{id}, state => $state } );
   }

   return 1;
}

sub reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_reset_cluster( $user, $d );
   return $rv ? { success => 1 } : { success => 0 };
}

sub find_cluster {
   my ( $self, $user, $d ) = @_;

   my $cluster    = $self->read_cluster( $user, $d );
   my $cluster_id = $cluster->{id};

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;

   my @clusters;

   if ($cluster_id) {
      my $is_readable = $self->is_readable( $user, { id => $cluster->{id} } );
      return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;

      $cluster->{jobs}  = $self->_find_jobs( $user, { cluster_id => $cluster_id } );
      $cluster->{needs} = $self->_read_cluster_needs( $user, { id => $cluster_id } );
      push @clusters, $cluster;
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
         $c->{jobs}       = $self->_find_jobs( $user, { cluster_id => $c->{id} } );
         $c->{needs}      = $self->_read_cluster_needs( $user, { id => $c->{id} } );
         $c->{next_start} = $self->_cal_next_start( $user, { id => $c->{cal_id} } ) if $c->{cal_id};

         push @clusters, $c;
         __SUB__->( $c->{id} );
      }
      return;
   };

   $find_clusters->($cluster_id);
   return scalar @clusters ? { success => 1, clusters => \@clusters } : { success => 0, message => 'no clusters found' };
}

sub update_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );

   return $cluster if $cluster->{success} == 0;
   my $cluster_id = $cluster->{id};

   return { success => 0, message => 'cluster not found' } unless $cluster_id;
   my $is_writable = $self->is_writable( $user, { id => $cluster_id } );
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   # add cal_id
   my $cal;

   eval {
      #my $tx = $self->sqlite->db->begin;
      $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster_id } )       if scalar keys %{$update_hash};
      $self->_write_cluster_needs( $user, { id => $cluster_id, needs => $d->{needs} } ) if $d->{needs};

      if ( exists $d->{cal_id} || exists $d->{cal} ) {
         my $new_cal    = $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
         my $new_cal_id = $new_cal->{id} if $new_cal;
         die unless $self->_set_cluster_cal_id( $user, { cluster_id => $cluster_id, cal_id => $new_cal_id } );
      }
      elsif ( $d->{cron} || $d->{at} ) {
         die unless $self->_add_cluster_cron( $user, { id => $cluster_id, tz => $d->{tz}, cron => $d->{cron}, at => $d->{at} } );
      }

      #$tx->commit;
   };
   my $success = $@ ? 0 : 1;
   return { success => $success, message => $@ };
}

sub delete_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );
   return $cluster if $cluster->{success} == 0;
   my $cluster_id = $cluster->{id};

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;

   if ($cluster_id) {
      my $is_writable = $self->is_writable( $user, { id => $cluster_id } );
      return { success => 0, message => 'no write permissions on this cluster' } unless $is_writable;
   }

   # delete cluster and all descendants

   my $clusters = $self->find_cluster( $user, { id => $cluster_id } )->{clusters};
   foreach my $c ( @{$clusters} ) {

      # delete jobs
      my $jobs = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $c->{id} } );
      while ( my $j = $jobs->hash ) {
         my $rv = $self->delete_job( $user, { id => $j->{id}, force => 1 } );
      }

      # delete cluster
      $self->sqlite->db->delete( 'cluster', { id => $c->{id} } );
      next unless $c->{cal_id};

      # calendar cleanup
      my $count = $self->sqlite->db->query("select count(*) as count from cluster where cal_id = $c->{cal_id}")->hash->{count};
      if ( $count == 0 ) {

         # stop cal if no clusters subscribed
         $self->_stop_cal( $user, { id => $c->{cal_id} } );

         # delete cal if it has no name
         $self->sqlite->db->delete( 'cal', { name => undef, id => $c->{cal_id}, org_id => $user->org_id } );
      }
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
      my $is_writable = $self->is_writable( $user, { id => $cluster_id } );
      return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;
   }

   my $insert_hash = {
      org_id    => $user_info->{org_id},
      user_id   => $user_info->{id},
      parent_id => $cluster_id,
      server_id => $d->{server_id},
      name      => $name,
   };

   $insert_hash->{mode} =
       $d->{mode}         ? $d->{mode}
     : $user_info->{mode} ? $user_info->{mode}
     :                      770;

   my $id;
   eval {
      my $tx = $self->sqlite->db->begin;
      $id = $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id;
      die unless $id;
      $self->_write_cluster_needs( $user, { id => $id, needs => $d->{needs} } ) if $d->{needs};
      $tx->commit;
   };
   if ( $d->{cron} || $d->{at} ) {
      my $rv = $self->_add_cluster_cron( $user, { id => $id, tz => $d->{tz}, cron => $d->{cron}, at => $d->{at} } );
   }
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $id };
}

# shortcut to add a cal+cron directly to a cluster
sub _add_cluster_cron {
   my ( $self, $user, $d ) = @_;

   # id (cluster) tz cron at

   return unless $d->{cron} || $d->{at};

   my $cluster    = $self->sqlite->db->select( 'cluster', [ 'id', 'cal_id' ], { id => $d->{id}, org_id => $user->org_id } )->hash;
   my $cluster_id = $cluster->{id};
   my $cal_id     = $cluster->{cal_id};

   my $tz = $d->{tz} || 'UTC';
   eval {
      my $tx = $self->sqlite->db->begin;

      my $cal_id = $self->_create_cal( $user, { tz => $tz, description => "calendar for cluster_id $cluster_id" } );
      die unless $cal_id;

      my $rv =
          $d->{cron} ? $self->_add_cron( $user, { name => $d->{cron}, cal_id => $cal_id } )
        : $d->{at}   ? $self->_add_at( $user, { name => $d->{at}, cal_id => $cal_id } )
        :              { success => 0 };

      die unless $rv->{success};
      my $success = $self->_set_cluster_cal_id( $user, { cluster_id => $cluster_id, cal_id => $cal_id } );
      die unless $success;
      $tx->commit;
   };
   return $@ ? 0 : 1;
}

sub change_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster    = $self->read_cluster( $user, $d );
   my $cluster_id = $cluster->{id};

   if ($cluster_id) {
      my $is_readable = $self->is_readable( $user, { id => $cluster_id } );
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
      $user_insert->{mode}            = 770;
      $user_id                        = $db->insert( 'user', $user_insert )->last_insert_id;
      $db->update( 'org',     { user_id => $user_id }, { id => $org_id } );
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

      #$self->_is_stale( $user, $j ) if $j->{last_update} && $j->{state_id} != $self->job_states->{stale};

      push @jobs, $j;
   }
   return \@jobs;
}

#sub _is_stale {
#   my ( $self, $user, $job ) = @_;
#   my $updated = time - $job->{last_update};
#   if ( ( grep { $job->{state_id} == $self->job_states->{$_} } (qw(running watching)) ) && $updated > 20 ) {
#      $self->update_job( $user, { id => $job->{id}, state => 'stale' } );
#      $job->{state_id} = $self->job_states->{stale};
#      $self->_reset_job_stats( $user, { id => $job->{id} } );
#      return 1;
#   }
#   return;
#}

sub clone_cluster {
   my ( $self, $user, $d ) = @_;

   # id name parent_id

   my $cluster = $self->_cluster_info( $user, $d );

   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $parent_id = $d->{parent_id} || $cluster->{parent_id};

   my $rv = $self->_clone_cluster( $user, { id => $cluster->{id}, parent_id => $parent_id } );

   return { success => $rv };
}

sub _clone_cluster {
   my ( $self, $user, $d ) = @_;

   # id name parent_id

   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id}, org_id => $user->org_id } )->hash;

   #print "PARENT: $cluster->{parent_id}\n";
   return unless $cluster->{id};

   my $name = delete $cluster->{name};
   $cluster->{parent_id}        = $d->{parent_id};
   $cluster->{clone_cluster_id} = delete $cluster->{id};

   my $cluster_id = $self->sqlite->db->insert( 'cluster', $cluster )->last_insert_id;
   my $new_name   = $name .= "_$cluster_id";
   $self->sqlite->db->update( 'cluster', { name => $new_name }, { id => $cluster_id } );
   my $jobs = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $cluster->{clone_cluster_id} } );
   while ( my $job = $jobs->hash ) {
      delete $job->{id};
      $job->{cluster_id} = $cluster_id;
      $self->sqlite->db->insert( 'job', $job )->last_insert_id;
   }
   $self->_reset_cluster( $user, { id => $cluster_id } );
   return $cluster_id ? 1 : 0;
}

sub create_job {
   my ( $self, $user, $d ) = @_;

   my $j = $self->_path2name( $user, $d->{name} );
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $j->{is_writable};
   my $rv = $self->_create_job( $user, $d );
   return $rv;
}

sub _create_job {
   my ( $self, $user, $d ) = @_;

   my $j = $self->_path2name( $user, $d->{name} );
   return { success => 0, message => 'a job by that name already exists' } if $j->{job_id};
   return { success => 0, message => 'cluster not found' }                 if defined $j->{cluster_id} && $j->{cluster_id} == 0;

   #return { success => 0, message => 'you do not have permission to write to this cluster' } unless $j->{is_writable};

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
      $self->_write_job_needs( $user, { needs => $d->{needs}, id => $id, cluster_id => $j->{cluster_id} } );
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

   if ( $job->{cluster_id} ) {
      my $is_writable = $self->is_writable( $user, { id => $job->{cluster_id} } );
      return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;
   }

   unless ( $d->{force} ) {
      if ( $job->{state_id} == $self->job_states->{running} ) {
         return { success => 0, message => 'job running. use --force to delete anyway' };
      }
   }

   $self->_hard_kill_job( $user, { id => $job->{id} } ) unless $job->{state_id} == $self->job_states->{watching};
   $self->sqlite->db->delete( 'job', { id => $job->{id} } );

   # if no jobs left in the cluster, set cluster state to ready and de-link it from any calendar
   my $count = $self->sqlite->db->query("select count(*) as count from job where cluster_id = $job->{cluster_id}")->hash->{count};
   unless ($count) {
      $self->_set_cluster_cal_id( $user, { cluster_id => $job->{cluster_id}, cal_id => undef } );
      $self->_set_cluster_state( $user, { id => $job->{cluster_id}, state => 'ready' } );
   }
   return { success => 1, id => $job->{id} };
}

sub unwatch_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'not a watcher job' } unless $job->{state_id} == $self->job_states->{watching};
   return $self->delete_job( $user, { id => $job->{id} } );
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
   return $self->_set_job_state( $user, { id => $job->{id}, state => 'hold' } );
}

sub _set_job_state {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info

   my $failed    = $self->job_states->{failed};
   my $killed    = $self->job_states->{killed};
   my $ready     = $self->job_states->{ready};
   my $waiting   = $self->job_states->{waiting};
   my $completed = $self->job_states->{complete};
   my $ice       = $self->job_states->{ice};
   my $zombie    = $self->job_states->{zombie};

   my $state_id = $self->job_states->{ $d->{state} };
   return unless $state_id;

   my $current_state_id = $self->sqlite->db->select( 'job', ['state_id'], { id => $job->{id} } )->hash->{state_id};
   return if $current_state_id && $current_state_id == $state_id;

   my $update_hash = { state_id => $state_id };

   if ( $d->{state} eq 'running' ) {

      # TODO: add max duration hook
      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      # set cluster to running if no failed jobs in cluster
      my $r = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $job->{cluster_id}, id => { '!=', $job->{id} }, state_id => { '=', [ ( $killed, $failed, $zombie ) ] } } );
      unless ( $r->hash ) {
         $self->_set_cluster_state( $user, { state => 'running', id => $job->{cluster_id} } );
      }
   }
   elsif ( grep { $d->{state} eq $_ } (qw(failed killed zombie)) ) {

      $self->sqlite->db->update( 'job', { state_id => $self->job_states->{ $d->{state} } }, { id => $job->{id} } );
      $update_hash->{ended} = time;
      $self->_reset_job_stats( $user, { id => $job->{id} } );
      $self->_set_cluster_state( $user, { state => 'failed', id => $job->{cluster_id} } );

      if ( $d->{state} eq 'failed' ) {

         # retrys
         if ( $job->{retrys} && $job->{retrys} > $job->{retry_count} ) {
            $job->{retry_count}++;
            $self->sqlite->db->update( 'job', { retry_count => $job->{retry_count} }, { id => $job->{id} } );
            $self->start_job( $user, { id => $job->{id}, force => 1 } );
         }
         elsif ( $job->{retrys} ) {
            $self->sqlite->db->update( 'job', { retry_count => 0 }, { id => $job->{id} } );
         }

         # fail hook
         if ( $job->{fail_hook} ) {
            my $cluster_hook = $self->sqlite->db->select( 'cluster', ['id'], { id => $job->{fail_hook} } );
            if ( $cluster_hook->{id} ) {
               $self->_start_cluster( $user, { id => $cluster_hook->{id}, force => 1 } );
            }
         }
      }
   }
   elsif ( $d->{state} eq 'complete' || $d->{state} eq 'fake_complete' ) {

      $self->sqlite->db->update( 'job', { state_id => $self->job_states->{complete} }, { id => $job->{id} } ) unless $d->{state} eq 'fake_complete';

      # TODO: add loops

      # find jobs in ready or waiting state that just had a dependency met
      my $depends_sql = <<~"SQL";
         select jn.job_id, j.state_id
         from job_needs jn
         join job j on jn.job_id = j.id
         where jn.needs_job_id = $job->{id}
         and j.state_id in ($ready, $waiting)
      SQL

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
            my $rv = $self->start_job( $user, { id => $j->{job_id}, force => 1 } );
         }
      }
      $update_hash->{ended} = time;
      $self->_reset_job_stats( $user, { id => $job->{id} } );

      # complete cluster if all jobs completed or on ice
      my $cluster_id = $job->{cluster_id};

      my $c = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $completed, $ice ) ] } } );
      if ( !$c->hash ) {

         $self->_set_cluster_state( $user, { state => 'complete', id => $job->{cluster_id} } );

         # find all clusters in ready state that just had a dependency met

         my $depends_sql = <<~"SQL";
           select c.id, cn.cluster_id, c.state_id
           from cluster_needs cn
           join cluster c on cn.cluster_id = c.id
           where cn.needs_cluster_id = $cluster_id
           and c.state_id in ($ready)
         SQL

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
               $self->start_cluster( $user, { id => $c->{id} } );

               # TODO:
            }
         }
      }
   }
   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
}

sub update_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless $job->{id};

   my $success     = 0;
   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw( retrys retry_delay loops loop_delay signal ppid pid started ended exit_code server_id shell_command)) };

   if ( $d->{state} ) {
      my $rv = $self->_set_job_state( $user, { id => $job->{id}, state => $d->{state} } );
      $success++ if $rv;
   }
   if ( $d->{needs} ) {
      my $rv = $self->_write_job_needs( $user, { needs => $d->{needs}, id => $job->{id}, cluster_id => $job->{cluster_id} } );
      $success++ if $rv;
   }
   if ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'], { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' } unless $res->{id};
      $update_hash->{server_id} = $res->{id};
      $success++;
   }
   $update_hash->{name} = $d->{newname} if $d->{newname};
   $success++                           if scalar keys %{$update_hash};
   $update_hash->{last_update} = time;
   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   return { success => $success };
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

   my ( $needs, $success );
   return 0 unless ref $d->{needs} eq 'ARRAY';
   my @n = grep { $_ =~ /^\d{1,10}$/ } @{ $d->{needs} };
   $needs = $self->sqlite->db->select( 'job', ['id'], { id => { '=', [@n] } } )->hashes->to_array;

   eval {
      my $tx = $self->sqlite->db->begin;
      $self->sqlite->db->delete( 'job_needs', { job_id => $d->{id} } );

      foreach my $need ( @{$needs} ) {

         # a job must not need itself
         next if $d->{id} == $need->{id};

         # job and needed job must both be in the same cluster
         my $need_cluster_id = $self->sqlite->db->select( 'job', ['cluster_id'], { id => $need->{id} } )->hash->{cluster_id};
         if ( $d->{cluster_id} == $need_cluster_id ) {
            $self->sqlite->db->insert( 'job_needs', { job_id => $d->{id}, needs_job_id => $need->{id} } );
            $success++;
         }
      }
      $tx->commit;
   };
   return $success ? 1 : 0;
}

sub _write_cluster_needs {
   my ( $self, $user, $d ) = @_;

   my $needs;
   return unless ref $d->{needs} eq 'ARRAY';
   my @n = grep { $_ =~ /^\d{1,11}$/ } @{ $d->{needs} };
   $needs = $self->sqlite->db->select( 'cluster', ['id'], { id => { '=', [@n] } } )->hashes->to_array;

   $self->sqlite->db->delete( 'cluster_needs', { cluster_id => $d->{id} } );
   foreach my $need ( @{$needs} ) {

      # a cluster must not need itself
      next if $d->{id} == $need->{id};

      $self->sqlite->db->insert( 'cluster_needs', { cluster_id => $d->{id}, needs_cluster_id => $need->{id} } );
   }
   return scalar @$needs;
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

   # TODO: server alarms: max cpu mem disk ping load uptime

   my $ssh = $self->ssh_connection->{ $server->{id} };
   return { success => 0, exit => 1 } unless $server->{id} && $ssh && $ssh->check_master;
   $uh->{ping}        = $self->_ping( $server->{hostname} ) if $server->{hostname};
   $uh->{update_time} = time;
   my $running  = $self->job_states->{running};
   my $watching = $self->job_states->{watching};
   my $starting = $self->job_states->{starting};

   #my $stopping = $self->job_states->{stopping};

   # receive pid info
   if ( $d->{pids} && ref $d->{pids} eq 'ARRAY' ) {
      foreach my $pid ( @{ $d->{pids} } ) {
         my $job = $self->sqlite->db->select( 'job', ['id'], { server_id => $server->{id}, pid => $pid->{pid} } )->hash;
         next unless $job->{id};
         my $update = { map { $_, $pid->{$_} } grep { exists $pid->{$_} } (qw(pctcpu pid time start size priority rss pctmem ppid state cmndline fname)) };
         $update->{last_update} = time;
         $self->sqlite->db->update( 'job', $update, { id => $job->{id} } );

         # TODO: job resource alarms: max duration pctcpu pctmem
      }
   }

   # identify zombies
   if ( $d->{zombies} && ref $d->{zombies} eq 'ARRAY' ) {

      #my $ids = $self->sqlite->db->select( 'job', [ 'id', 'state_id' ], { pid => $d->{zombies}, state_id => [ $running, $watching ] } );
      my $ids = $self->sqlite->db->select( 'job', [ 'id', 'state_id' ], { pid => $d->{zombies}, server_id => $d->{id} } );
      while ( my $next = $ids->hash ) {
         $self->_set_job_state( $user, { state => 'zombie', id => $next->{id} } );
      }
   }

   # send pid request
   my @pids;
   my $pids = $self->sqlite->db->select( 'job', ['pid'], { server_id => $d->{id}, pid => { '!=', undef }, state_id => [ $starting, $running, $watching ] } );
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
   return $job_info;

}

# TODO: replace top_jobs with output from top
sub top_jobs {
   my ( $self, $user, $d ) = @_;
   return { success => 0 };
}

sub start_job {
   my ( $self, $user, $d ) = @_;
   return $self->_start_job( $user, $d );
}

sub _start_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, skipped => 1, message => 'job not found' } unless $job->{id};

   if ( scalar grep { $self->job_states->{$_} == $job->{state_id} } (qw(starting running)) ) {
      return { success => 0, skipped => 1, message => 'job is already running' };
   }

   # skip if job on ice
   if ( $job->{state_id} == $self->job_states->{ice} ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'fake_complete' } );
      return { success => 0, skipped => 1, message => 'job on ice' };
   }

   # don't start if dependencies not satisfied
   unless ( $d->{force} ) {

      # make sure that job is ready or waiting
      if ( $job->{state_id} != $self->job_states->{ready} ) {
         return { success => 0, message => 'job not ready. use --force to start anyway' };
      }

      # don't start if dependencies not satisfied
      while ( my ( $id, $state_id ) = each %{ $job->{needs} } ) {
         if ( !grep { $state_id == $self->job_states->{$_} } (qw(complete ice)) ) {
            return { success => 0, skipped => 1, message => 'dependency not met. use --force to start anyway' };
         }
      }
   }

   # TODO: add flex_server load balancing
   my $server = $self->_server_info( $user, { id => $job->{server_id} } );
   unless ($server) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'failed' } );
      return { success => 0, message => 'server not found' };
   }

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $job->{server_id} } );
      $ssh = $self->ssh_connection->{ $job->{server_id} };
   }

   my $token    = $self->read_user($user)->{token};
   my $json     = encode_json( { token => $token, id => $job->{id}, cluster_id => $job->{cluster_id}, shell => $job->{shell_command} } );
   my $json_hex = unpack( 'H*', $json );
   my $cmd      = "perl cc_worker/script/launcher.pl $json_hex";

   $self->_set_job_state( $user, { id => $job->{id}, state => 'starting' } );

   $ssh->spawn($cmd);

   #$ssh->system($cmd);
   if ( $ssh->error ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => $d->{failed} } );
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

sub _hard_kill_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );

   return { success => 0, message => 'pid not found' } unless $job && $job->{pid};
   my @pids = ( $job->{pid} );
   unshift @pids, $job->{ppid} if $job->{ppid};
   my $pid_list = join( ', ', @pids );

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;

   my $rv = $ssh->system("perl -e 'kill KILL, $pid_list'");

   if ($rv) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'killed' } );
      return { success => 1 };
   }
   else {
      return { success => 0 };
   }
}

sub kill_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' }      unless $job && $job->{id};
   return { success => 0, message => 'job pid not found' }  unless $job->{pid};
   return { success => 0, message => 'job is not running' } unless $job->{state_id} == $self->job_states->{running};
   return { success => 0, message => 'watcher jobs cannot be killed. unwatch or delete it instead' } if $job->{state_id} == $self->job_states->{watching};

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;

   $self->_set_job_state( $user, { id => $job->{id}, state => 'stopping' } );
   my $rv      = $ssh->system("perl -e 'kill TERM, $job->{pid}'");
   my $success = $rv ? 1 : 0;
   return { success => $success };
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

sub _reset_job_stats {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless ref $job && $job->{id};

   my %update = map { $_ => undef } (qw(signal ppid pid exit_code pctcpu time start size priority rss pctmem state cmndline fname));

   #my %update = map { $_ => undef } (qw(signal pctcpu time start size priority rss pctmem state cmndline fname));
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
   return unless $s;

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
      return if $error;
      my $basicinfo = decode_json($out);
      my $update    = { map { $_, $basicinfo->{$_} } grep { exists $basicinfo->{$_} } (qw(home os cores cwd)) };
      $self->sqlite->db->update( 'server', $update, { id => $s->{id} } );
   };
   return $@ ? 0 : 1;
}

sub create_monitor {
   my ( $self, $user, $d ) = @_;
   my $token = $self->read_user($user)->{token};

   $self->_ssh_copy( $user, $d ) if $d->{password};

   my $port        = $d->{port} || 22;
   my $insert_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(name username hostname password)) };
   $insert_hash->{port}   = $port;
   $insert_hash->{org_id} = $user->org_id;

   my ( $id, $json, $cwd );

   eval {
      my $tx = $self->sqlite->db->begin;

      # create monitor and start it
      $id = $self->sqlite->db->insert( 'server', $insert_hash )->last_insert_id;
      $self->_connect_ssh( $user, { id => $id } )     or die "connect failed";
      $self->_install_monitor( $user, { id => $id } ) or die "install failed";
      $self->_start_monitor( $user, { id => $id } )   or die "start failed";

      # create monitor cluster if it doesn't already exist
      my $monitors = $self->sqlite->db->select( 'cluster', ['id'], { org_id => $user->org_id, name => 'monitors', parent_id => undef } )->hash;
      unless ( $monitors->{id} ) {
         my $rv = $self->_create_cluster( $user, { name => '/monitors', mode => 550 } );
         die "create monitor cluster failed" unless $rv->{success};
      }

      # create monitor job
      my $server = $self->_server_info( $user, { id => $id } );
      die "missing server" unless $server->{id};
      $json = encode_json( { token => $token, id => $id } );
      $cwd  = $server->{cwd} || '';
      my $rv = $self->_create_job( $user, { name => "/monitors/$d->{name}", shell_command => "$cwd/cc_worker/script/sysinfo.pl $json", server_id => $id } );
      die "create monitor job failed" unless $rv->{success};
      my $sj = $self->_start_job( $user, { id => $rv->{id}, force => 1 } );
      die "unable to start monitor" unless $sj->{success};
      $tx->commit;
   };

   return $@ ? { success => 0, message => $@ } : { success => 1 };
}

sub read_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->sqlite->db->select( 'server', ['*'], { org_id => $user->org_id } );
   my @s;
   while ( my $server = $servers->hash ) {
      my $info = { map { $_, $server->{$_} } (qw(id os cwd home cores update_time ping username hostname name port total_memory used_memory cpu total_disk used_disk uptime)) };
      push @s, $info;
   }
   return scalar @s ? { success => 1, servers => \@s } : { success => 0, message => 'no monitors found' };
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

   return unless $s && $s->{id} && $s->{username} && $s->{hostname};
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

   return if $ssh->error || !$ssh->check_master;

   # add connection
   $self->ssh_connection->{ $s->{id} } = $ssh;

   return 1;
}

sub _start_monitor {
   my ( $self, $user, $d ) = @_;
   my $token = $self->read_user($user)->{token};
   my $s     = $self->_server_info( $user, $d );
   return unless $s;
   $self->_disconnect_ssh( $user, $d );
   my $ssh = $self->ssh_connection->{ $s->{id} };
   $self->_connect_ssh( $user, { id => $s->{id} } ) unless ( $ssh && $ssh->check_master );
   $ssh = $self->ssh_connection->{ $s->{id} };
   return 1;
}

sub stop_monitor {
   my ( $self, $user, $d ) = @_;

   # id (server id)

   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

   my $job = $self->_job_info( $user, { name => "/monitors/$server->{name}" } );
   return { success => 0, message => 'monitor job not found' } unless $job->{id};

   my $rv = $self->_hard_kill_job( $user, { id => $job->{id} } );

   return $rv;
}

sub start_monitor {
   my ( $self, $user, $d ) = @_;
   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

   my $job = $self->_job_info( $user, { name => "/monitors/$server->{name}" } );

   return { success => 0, message => 'monitor job not found' } unless $job->{id};
   return $self->start_job( $user, { id => $job->{id}, force => 1 } );
}

sub update_monitor {
   my ( $self, $user, $d ) = @_;
   return { success => 1 };
}

sub upgrade_monitor {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_install_monitor( $user, $d );
   return { success => $rv };
}

sub delete_monitor {
   my ( $self, $user, $d ) = @_;
   return { success => 0, message => 'missing name or id' } unless $d->{name} || $d->{id};
   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'server not found' } unless $server;
   my $id  = $server->{id};
   my $ci  = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => undef, name => 'monitors', org_id => $user->org_id } )->hash;
   my $job = $self->sqlite->db->select( 'job',     [ 'id', 'cluster_id' ], { cluster_id => $ci->{id}, name => $server->{name} } )->hash;

   if ( $job->{id} ) {
      $self->sqlite->db->delete( 'job', { cluster_id => $ci->{id}, name => $server->{name} } );
      my $count = $self->sqlite->db->query("select count(*) as count from job where cluster_id = $job->{cluster_id}")->hash->{count};
      $self->_set_cluster_state( $user, { id => $job->{cluster_id}, state => 'ready' } ) unless $count;
   }
   my $rows    = $self->sqlite->db->delete( 'server', { id => $id } )->rows;
   my $success = $rows ? 1 : 0;
   $self->_disconnect_ssh( $user, { id => $id } );
   delete $self->ssh_connection->{$id};
   return { success => $success };
}

# cron related subroutines

sub update_cron {
   my ( $self, $user, $d ) = @_;

   # id begin expire description

   my $cron = $self->sqlite->db->select( 'cron', ['*'], { id => $d->{id} } )->hash;
   return { success => 0, message => 'cron not found' } unless $cron->{id};

   my $cal;
   if ( $d->{cal} || $d->{cal_id} ) {
      $cal = $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
      return { success => 0, message => 'calendar not found' } unless $cal->{id};
   }

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description begin expire)) };
   $update_hash->{cal_id} = $cal->{id} if $cal->{id};

   my $rows    = $self->sqlite->db->update( 'cron', $update_hash, { id => $cron->{id}, org_id => $user->org_id } )->rows if scalar keys %$update_hash;
   my $success = $rows ? 1 : 0;
   return { success => $success };
}

sub create_cron {
   my ( $self, $user, $d ) = @_;

   # name cal tz

   return $self->_add_cron( $user, $d );
}

sub create_at {
   my ( $self, $user, $d ) = @_;

   # name cal tz

   return $self->_add_at( $user, $d );
}

# add row to cron table and return id
sub _create_cron_row {
   my ( $self, $user, $d ) = @_;

   # name cal_id begin expire

   my $cal_row = $self->sqlite->db->select( 'cal', ['tz'], { id => $d->{cal_id} } )->hash;
   my $tz      = $cal_row->{tz} || 'UTC';

   my @units = split( /\s+/, $d->{name} );
   return if scalar @units < 5 || scalar @units > 7;

   # convert unix cron to quartz cron
   unshift( @units, '0' ) if scalar @units == 5;
   if ( $units[3] =~ /\?/ ) {
      return if $units[5] =~ /\?/;
   }
   else {
      $units[5] = '?';
   }

   my $crontab = join( ' ', @units );

   my $next;
   eval {
      my $cron = DateTime::Event::Cron::Quartz->new($crontab);
      $next = $cron->get_next_valid_time_after( DateTime->from_epoch( epoch => time, time_zone => $tz ) )->epoch;
   };

   return if $@;
   return unless $next && $next > time;

   my $start = $d->{begin} && $d->{begin} > $next ? $d->{begin} : $next;
   my $end   = $d->{expire};

   return if $start >= 4102466400;    # max year 2099

   # sanity check
   if ( $start && $end ) {
      return if $start > $end;
   }

   my $id;
   eval {
      $id = $self->sqlite->db->insert(
         'cron',
         {
            name        => $crontab,
            cal_id      => $d->{cal_id},
            begin       => $start,
            expire      => $end,
            description => $d->{description},
            org_id      => $user->org_id
         }
      )->last_insert_id;
   };
   return $@ ? undef : $id;
}

sub _create_cron_object {
   my ( $self, $user, $d ) = @_;

   # id

   my $cron_row = $self->sqlite->db->select( 'cron', ['*'], { id => $d->{id} } )->hash;
   return { success => 0, message => 'cron not found' } unless $cron_row;

   my $cal_id = $cron_row->{cal_id};
   return { success => 0, message => 'missing cal_id' }              unless $cal_id;
   return { success => 0, message => 'cron has no next start time' } unless $self->_cron_next_start( $user, $d );

   $self->_delete_cron_object( $user, { id => $d->{id} } );

   $self->cron->{ $d->{id} } = EV::periodic(
      0, 0,
      sub {
         my ( $watcher, $now ) = @_;
         my $next = $self->_cron_next_start( $user, $d ) || 0;
         print "NEXT: $next\n";
         $self->sqlite->db->update( 'cron', { next_start => $next }, { id => $d->{id} } );
         return $next;
      },
      sub {
         # delete cron if no next start date
         $self->_delete_cron( $user, $d ) unless $self->_cron_next_start( $user, $d );

         # start all clusters connected to this calendar
         my $cluster_ids = $self->_cal_cluster_ids( $user, { id => $cal_id } );
         for my $cluster_id (@$cluster_ids) {
            $self->start_cluster( $user, { id => $cluster_id } );
            print "start cluster: $cluster_id " . localtime(time) . "\n";

            # TODO:
         }

         # delete cal if no next start date
         unless ( $self->_cal_next_start( $user, { id => $cal_id } ) ) {
            $self->_stop_cal( $user, { id => $cal_id } );
            $self->_delete_cal( $user, { id => $cal_id } );
         }
      }
   );
   return { success => 1, message => 'cron scheduled' };
}

sub _delete_cron_row {
   my ( $self, $user, $d ) = @_;
   my $rows = $self->sqlite->db->delete( 'cron', { id => $d->{id} } )->rows;
   return $rows ? 1 : 0;
}

sub _delete_cron_object {
   my ( $self, $user, $d ) = @_;

   # id

   my $w = $self->cron->{ $d->{id} };
   if ( $w && $w->is_active ) {
      $w->stop;
      delete $self->cron->{ $d->{id} };
      return 1;
   }
   else {
      delete $self->cron->{ $d->{id} };
      return 0;
   }
}

sub _delete_cron {
   my ( $self, $user, $d ) = @_;

   # id

   my $rv = 0;
   $self->_delete_cron_object( $user, $d ) && $rv++;
   $self->_delete_cron_row( $user, $d )    && $rv++;
   return $rv;
}

sub delete_cron {
   my ( $self, $user, $d ) = @_;

   # id

   my $rv = $self->_delete_cron( $user, { id => $d->{id} } );
   return $rv ? { success => $rv } : { success => 0, message => 'cron not found' };
}

# cal related subroutines

sub _create_cal {
   my ( $self, $user, $d ) = @_;

   # name tz

   my $id;
   eval { $id = $self->sqlite->db->insert( 'cal', { name => $d->{name}, tz => $d->{tz}, description => $d->{description}, org_id => $user->org_id } )->last_insert_id; };

   return $id ? $id : undef;
}

sub create_cal {
   my ( $self, $user, $d ) = @_;

   # name id tz cron at

   my $id = $self->_create_cal( $user, $d );
   if ($id) {

      #$self->_add_cron( $user, $d ) if $d->{cron};
      #$self->_add_at( $user, $d )   if $d->{at};
      return { success => 1, id => $id };
   }
   return { success => 0, message => 'a calendar by that name already exists' };
}

sub _cal_info {
   my ( $self, $user, $d ) = @_;

   # name id

   my $select =
       $d->{id}   ? { id => $d->{id}, org_id => $user->org_id }
     : $d->{name} ? { org_id => $user->org_id, name => $d->{name} }
     :              undef;

   return unless $select;
   my $cal = $self->sqlite->db->select( 'cal', ['*'], $select )->hash;
   return $cal->{id} ? $cal : undef;
}

# return crons in the cal
sub _cal_crons {
   my ( $self, $user, $d ) = @_;

   # id

   my @crons;
   my $results = $self->sqlite->db->select( 'cron', ['*'], { cal_id => $d->{id}, org_id => $user->org_id } );
   while ( my $c = $results->hash ) {
      push @crons, $c;
   }
   return \@crons;
}

sub _start_cal {
   my ( $self, $user, $d ) = @_;

   # id

   my $crons = $self->_cal_crons( $user, { id => $d->{id} } );
   foreach my $cron (@$crons) {
      my $w = $self->cron->{ $d->{id} };
      unless ( $w && $w->is_active ) {    # skip if already active;
         $self->_create_cron_object( $user, { id => $cron->{id} } );
      }
   }
}

sub _stop_cal {
   my ( $self, $user, $d ) = @_;

   # id

   my $crons = $self->_cal_crons( $user, { id => $d->{id} } );
   foreach my $cron (@$crons) {
      $self->_delete_cron_object( $user, { id => $cron->{id} } );
   }
   $self->sqlite->db->update( 'cron', { next_start => undef }, { cal_id => $d->{id}, org_id => $user->org_id } );
}

sub _set_cluster_cal_id {
   my ( $self, $user, $d ) = @_;

   # cluster_id cal_id

   # get old cal_id
   my $old_cal    = $self->sqlite->db->select( 'cluster', ['cal_id'], { id => $d->{cluster_id} } )->hash;
   my $old_cal_id = $old_cal->{cal_id};
   my $new_cal_id = $d->{cal_id};

   # update cal_id
   my $rows = $self->sqlite->db->update( 'cluster', { cal_id => $new_cal_id }, { id => $d->{cluster_id} } )->rows;

   if ($old_cal_id) {
      my $count = $self->sqlite->db->query("select count(*) as count from cluster where cal_id = $old_cal_id")->hash->{count};

      if ( $count == 0 ) {

         # stop old cal if no clusters subscribed
         $self->_stop_cal( $user, { id => $old_cal_id } );

         # delete old calendar if cal is cluster specific (has no name)
         $self->sqlite->db->delete( 'cal', { name => undef, id => $old_cal_id, org_id => $user->org_id } );

         # nothing to do so return
         return 1 if $new_cal_id && $old_cal_id == $new_cal_id;
      }
   }

   if ($new_cal_id) {
      my $count = $self->sqlite->db->query("select count(*) as count from cluster where cal_id = $new_cal_id")->hash->{count};

      # start new cal if subscribers went from 0 to 1
      if ( $count == 1 ) {
         $self->_start_cal( $user, { id => $new_cal_id } );
      }
   }
   return $rows ? 1 : 0;
}

sub _cron_next_start {
   my ( $self, $user, $d ) = @_;

   # id (cron id)

   my $c    = $self->sqlite->db->query("select cron.*, cal.tz from cron join cal on cron.cal_id = cal.id where cron.id = $d->{id}")->hash;
   my $tz   = $c->{tz} || 'UTC';
   my $name = $c->{name};
   return unless $name && $tz;

   my ( $cron, $next );
   eval {
      $cron = DateTime::Event::Cron::Quartz->new( $c->{name} );
      $next = $cron->get_next_valid_time_after( DateTime->from_epoch( epoch => time, time_zone => $tz ) )->epoch;
   };
   return if $@ || !$next;

   $next = $cron->get_next_valid_time_after( DateTime->from_epoch( epoch => $c->{begin}, time_zone => $tz ) )->epoch if $c->{begin} && $next < $c->{begin};

   $next = undef if $c->{expire} && $next > $c->{expire};

   return $next;
}

sub _cal_next_start {
   my ( $self, $user, $d ) = @_;

   # id (cal id)

   my $cal_id = $d->{id};
   return unless $cal_id;

   my $sql = <<~"SQL";
      select min(next_start) as next_start
      from cron
      where cal_id = $cal_id
      and next_start >= unixepoch('now');
   SQL

   my $next_start = $self->sqlite->db->query($sql)->hash->{next_start};
   return $next_start;
}

# return cluster ids that use the cal
sub _cal_cluster_ids {
   my ( $self, $user, $d ) = @_;

   # id

   my @cluster_ids;
   my $results = $self->sqlite->db->select( 'cluster', ['id'], { cal_id => $d->{id} } );
   while ( my $c = $results->hash ) {
      push @cluster_ids, $c->{id};
   }

   return \@cluster_ids;
}

sub _read_cal {
   my ( $self, $user, $d ) = @_;

   # id

   my $cal = $self->_cal_info( $user, $d );

   if ($cal) {
      $cal->{cluster_ids} = $self->_cal_cluster_ids( $user, { id => $cal->{id} } );
      $cal->{crons}       = $self->_cal_crons( $user, { id => $cal->{id} } );
      $cal->{next_start}  = $self->_cal_next_start( $user, { id => $cal->{id} } );
      return $cal;
   }
   else {
      return;
   }
}

sub read_cal {
   my ( $self, $user, $d ) = @_;

   # id name

   my @all;
   my $cal_info = $self->_read_cal( $user, $d );
   push @all, $cal_info if $cal_info;
   return $cal_info->{id} ? { success => 1, cals => \@all } : { success => 0, message => 'cal not found' };
}

sub find_cal {
   my ( $self, $user, $d ) = @_;

   my @all;
   my $select =
       $d->{id}   ? { id => $d->{id} }
     : $d->{name} ? { name => { '-like' => "$d->{name}%" } }
     :              { org_id => $user->org_id };

   $select->{org_id} = $user->org_id;
   my $cals = $self->sqlite->db->select( 'cal', ['*'], $select );
   while ( my $cal = $cals->hash ) {
      my $c = $self->_read_cal( $user, { id => $cal->{id} } );
      push @all, $c;
   }
   return scalar @all ? { success => 1, cals => \@all } : { success => 0, message => 'no cals found' };
}

sub _add_cron {
   my ( $self, $user, $d ) = @_;

   # name description start end

   my $cal_info = $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
   return { success => 0, message => 'calendar not found' } unless $cal_info->{id};

   my $id;
   eval { $id = $self->_create_cron_row( $user, { name => $d->{name}, begin => $d->{begin}, expire => $d->{expire}, description => $d->{description}, cal_id => $cal_info->{id}, } ); };

   return { success => 0, message => 'an identical cron already exists in that calendar' } unless $id;

   # only start when subscribers exist
   my $count = $self->sqlite->db->query("select count(*) as count from cluster where cal_id = $cal_info->{id}")->hash->{count};
   return { success => 1, message => 'cron created but not started' } unless $count;

   my $rv = $self->_create_cron_object( $user, { id => $id } );
   return $rv;
}

sub _add_at {
   my ( $self, $user, $d ) = @_;

   # at name description start end cal cal_id

   return { success => 0, message => 'only future events may be scheduled' } if time > $d->{name};
   return { success => 0, message => 'event too far in the future' }         if $d->{name} > 4102466400;    # max year 2100

   my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $d->{name} );

   $d->{name} = sprintf( "%d %d %d %d %d ? %d", $sec, $min, $hour, $mday, $mon + 1, $year += 1900 );

   my $rv = $self->_add_cron( $user, $d );
   return $rv;
}

sub update_cal {
   my ( $self, $user, $d ) = @_;

   # name id cron cron_id at remove

   my $cal = $self->_cal_info( $user, $d );
   return { success => 0, message => 'cal not found' } unless $cal->{id};

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description tz)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   my $success = scalar keys %$update_hash;
   $self->sqlite->db->update( 'cal', $update_hash, { id => $cal->{id}, org_id => $user->org_id } ) if scalar $success;
   return { success => $success };
}

sub _delete_cal {
   my ( $self, $user, $d ) = @_;

   # id (cal id)

   my $rows = $self->sqlite->db->delete( 'cal', { id => $d->{id} } )->rows;
   return $rows ? 1 : 0;
}

sub delete_cal {
   my ( $self, $user, $d ) = @_;

   # id name

   my $cal = $self->_cal_info( $user, $d );

   $self->_stop_cal( $user, { id => $cal->{id} } );
   my $success = $self->_delete_cal( $user, { id => $cal->{id} } );
   return { success => $success };
}

# command routing

sub routing {
   state $i    = qr/^\d{1,20}$/;                                                 # integer
   state $w    = qr/^\w{1,50}$/;                                                 # word
   state $d    = qr/^[A-Za-z].*?$/;                                              # description
   state $f    = qr/^[\d\.]{1,20}$/;                                             # float
   state $p    = qr/^[\w\/\@\:\.]{1,50}$/;                                       # path
   state $e    = qr/^[\w\.\@]{1,50}$/;                                           # email
                                                                                 # state $c  = qr/^[\w\/\@\:\.\s\-\(\)\"\']{1,50}$/;    # shell command
   state $c    = qr/.{1,60}/;                                                    # shell command
   state $pw   = qr/^.{8,20}$/;                                                  # password
   state $ct   = qr/^((\S{1,12}\s+){4}(\S{1,12}\s+){0,2}(\S{1,12}\s*)|\s*)$/;    # cron
   state $at   = qr/^(\d+|\s*)$/;                                                # at
   state $cal  = qr/^(\w+|\s*)$/;                                                # cal
   state $flag = qr/^(\d+|\s*)$/;

   state %routing = (

      # user related
      'create_user' => [ \&create_user, 3, [ { name => $w }, { org_id => $i, email => $w, level => $i } ] ],
      'read_user'   => [ \&read_user,   1, [ {},             {} ] ],
      'update_user' => [ \&update_user, 1, [ {},             { email => $e, name => $w } ] ],
      'delete_user' => [ \&delete_user, 3, [ { id => $i }, {} ] ],
      'login_user'  => [ \&login_user,  0, [ { token => $w }, {} ] ],

      # job related
      'create_job' => [
         \&create_job,
         1,
         [
            { name => $p, shell_command => $c, server => $w },
            {
               needs                   => 's',
               description             => $d,
               max_duration            => $i,
               max_duration_cluster_id => $p
            }
         ]
      ],
      'read_job'   => [ \&read_job, 1, [ {}, { name => $p, id => $i, cluster_id => $i } ] ],
      'update_job' => [
         \&update_job,
         1,
         [
            {},
            {
               name               => $p,
               id                 => $i,
               signal             => $i,
               exit_code          => $i,
               server_id          => $i,
               mem                => $f,
               cpu                => $f,
               newname            => $w,
               state              => $w,
               server             => $w,
               ppid               => $i,
               pid                => $i,
               shell_command      => $c,
               started            => $i,
               needs              => 's',
               ended              => $i,
               retrys             => $i,
               retry_delay        => $i,
               max_cpu            => $f,
               max_cpu_alarm      => $i,
               max_mem            => $f,
               max_mem_alarm      => $i,
               max_duration       => $i,
               max_duration_alarm => $i,
            }
         ]
      ],
      'delete_job'  => [ \&delete_job,  1, [ {}, { name => $p, id => $i, force     => $i } ] ],
      'start_job'   => [ \&start_job,   1, [ {}, { name => $p, id => $i, force     => $i } ] ],
      'watch_job'   => [ \&watch_job,   1, [ {}, { name => $p, id => $i, server_id => $i, server => $w, pid => $i, match => $c } ] ],
      'kill_job'    => [ \&kill_job,    1, [ {}, { name => $p, id => $i } ] ],
      'nice_job'    => [ \&nice_job,    1, [ {}, { name => $p, id => $i } ] ],
      'hold_job'    => [ \&hold_job,    1, [ {}, { name => $p, id => $i } ] ],
      'release_job' => [ \&release_job, 1, [ {}, { name => $p, id => $i } ] ],
      'ice_job'     => [ \&ice_job,     1, [ {}, { name => $p, id => $i } ] ],
      'melt_job'    => [ \&melt_job,    1, [ {}, { name => $p, id => $i } ] ],
      'finish_job'  => [ \&finish_job,  1, [ {}, { name => $p, id => $i } ] ],

      #'top_jobs'    => [ \&top_jobs,    1, [ {}, { count => $i, sort => $w, server_id => $i, name => $p, id => $i } ] ],

      # cluster related
      'create_cluster' => [
         \&create_cluster,
         1,
         [
            { name => $p },
            {
               needs             => 's',
               description       => $d,
               cron              => $ct,
               at                => $at,
               cal               => $cal,
               cal_id            => $at,
               tz                => $p,
               fail_hook         => $i,
               max_duration      => $i,
               max_duration_hook => $i,
            }
         ]
      ],
      'read_cluster'   => [ \&read_cluster, 1, [ {}, { name => $p, id => $i } ] ],
      'update_cluster' => [
         \&update_cluster,
         1,
         [
            {},
            {
               id                => $i,
               name              => $p,
               needs             => 's',
               newname           => $w,
               description       => $d,
               cron              => $ct,
               at                => $at,
               cal               => $cal,
               cal_id            => $at,
               tz                => $p,
               fail_hook         => $i,
               max_duration      => $i,
               max_duration_hook => $i,
            }
         ]
      ],
      'delete_cluster' => [ \&delete_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'change_cluster' => [ \&change_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'find_cluster'   => [ \&find_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'reset_cluster'  => [ \&reset_cluster,  1, [ {}, { name => $p, id   => $i } ] ],
      'start_cluster'  => [ \&start_cluster,  1, [ {}, { id   => $i, name => $p, force     => $i } ] ],
      'clone_cluster'  => [ \&clone_cluster,  1, [ {}, { id   => $i, name => $p, parent_id => $i } ] ],

      #'copy_cluster'   => [ \&copy_cluster,   1, [ {}, { name => $p, id => $i, to => $p } ] ],

      # cal related
      'create_cal' => [ \&create_cal, 1, [ { name => $w, tz => $p }, { description => $d } ] ],
      'read_cal'   => [ \&read_cal,   1, [ {}, { name => $w, id   => $i } ] ],
      'find_cal'   => [ \&find_cal,   1, [ {}, { name => $w, id   => $i } ] ],
      'update_cal' => [ \&update_cal, 1, [ {}, { id   => $i, name => $w, tz => $p, description => $d, newname => $w } ] ],
      'delete_cal' => [ \&delete_cal, 1, [ {}, { name => $p, id   => $i } ] ],

      # crons ats
      'create_cron' => [ \&create_cron, 1, [ { name => $ct }, { description => $d, cal => $w, cal_id => $i, begin => $i, expire => $i } ] ],
      'delete_cron' => [ \&delete_cron, 1, [ {}, { name => $ct, id => $i } ] ],
      'create_at'   => [ \&create_at,   1, [ { name => $i }, { description => $d, cal => $w, cal_id => $i } ] ],
      'update_cron' => [ \&update_cron, 1, [ { id => $i }, { description => $d, begin => $i, expire => $i, cal => $w, cal_id => $i } ] ],

      # monitor related
      'create_monitor' => [
         \&create_monitor,
         1,
         [
            { name => $w, username => $w, hostname => $p },
            {
               password => $pw,
            }
         ]
      ],
      'read_monitor'   => [ \&read_monitor, 1, [ {}, { id => $i, name => $p } ] ],
      'update_monitor' => [
         \&update_monitor,
         1,
         [
            {},
            {
               id       => $i,
               name     => $p,
               newname  => $w,
               username => $w,
               hostname => $p,
            }
         ]
      ],
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
