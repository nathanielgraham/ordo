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
use MIME::Base64;
use UUID::Tiny ':std';
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

   state $states = $self->sqlite->db->select( 'job_states', ['*'] )->hashes->to_array;
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

   # TODO: use SSH keys for authentication .. Mojo get_public_key method?
   # authenticate with Mojo::JWT ?
   # backend DBM::Deep
   # https://www.perl.com/article/193/2015/9/18/How-to-send-verification-emails-using-Mojolicious/

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
            if ( $body->{command} eq 'register_user' ) {
               my $result = $self->request( $user, { command => 'register_user' } );
               $c->render( json => $result );
            }
            else {
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
      }
   );

   # start monitors

   my $monitor_sql = <<~"SQL";
      select s.id as server_id, j.id as job_id, j.name as job_name, s.name, j.state_id, u.org_id, min(u.id) as user_id, u.token
      from job j 
      join cluster c on j.cluster_id = c.id
      join server s on s.name = j.name
      join user u on u.org_id = c.org_id
      join org o on u.org_id = o.id
      where c.name = 'monitors' and c.parent_id = o.root_cluster_id
      group by j.id
   SQL

   my $results = $self->sqlite->db->query($monitor_sql);
   while ( my $s = $results->hash ) {
      my $user = ordo::Model::User->new();
      $self->request( $user, { token => $s->{token}, command => 'login_user' } );

      my $connection_ok = $self->_connect_ssh($user, { id => $s->{server_id} });
      if (!$connection_ok) {
         $self->complete_job($user, { name => "/root/monitors/$s->{job_name}" });
         next;
      }

      $self->_install_monitor( $user, { id => $s->{server_id} } );
      $self->_start_monitor( $user, { id => $s->{server_id} } );

      # start_monitor if monitor job left in running state
      if ( scalar grep { $s->{state_id} == $self->job_states->{$_} } (qw(starting running)) ) {
         $self->stop_monitor( $user, { id => $s->{server_id} } );
         my $rv = $self->start_monitor( $user, { id => $s->{server_id} } );
      }
   }

   # delete old crons
   $self->sqlite->db->delete( 'cron', { expire => { '<', time } } );

   # load cron timers
   my $cron_timers_sql = <<~"SQL";
      select cal.id as cal_id, cal.org_id as org_id, cron.id as cron_id, min(user.id) as user_id, user.token
      from cron 
      join cal on cron.cal_id = cal.id
      join user on cal.org_id = user.org_id
      group by cron.id
   SQL

   my $cron_timers = $self->sqlite->db->query($cron_timers_sql);
   while ( my $a = $cron_timers->hash ) {
      my $count = $self->sqlite->db->query("select count(*) as count from cluster where cal_id = $a->{cal_id}")->hash->{count};
      next unless $count;
      #my $user = ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      my $user = ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      $self->request( $user, { token => $a->{token}, command => 'login_user' } );
      $self->_create_cron_object( $user, { id => $a->{cron_id} } );
   }

   # reset stale jobs
   # $self->sqlite->db->update('job', { state_id => $self->job_states->{failed} }, { state_id => $self->job_states->{retrying} };
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
         $response->{message} = 'permission denied';
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
            if ( $regex eq 's' && ref $params->{$param} eq 'ARRAY' ) {
               if (scalar @{ $params->{$param} } > 10000) {
                  $error      = 1;
                  $bad_option = $param;
                  last;
               }
               foreach my $item (@{ $params->{$param} }) {
                  unless ($item =~ /^\d+$/ && $item < 999999999 || ref $item eq 'HASH' && scalar keys %{ $item } < 100 ) {
                     $error      = 1;
                     $bad_option = $param;
                     last;
                  }
               }
            }
            else { 
               unless ( $params->{$param} =~ $regex ) {
                  $error      = 1;
                  $bad_option = $param;
                  last;
               }
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
   #return if defined $cluster_id && $cluster_id == 0;
   return unless $cluster_id;
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

   my @fields =
     qw(loops loop_delay loop_count fail_hook max_cpu max_cpu_hook max_mem max_mem_hook max_duration max_duration_hook id cal_id mode org_id user_id parent_id state_id name description started ended);

   my %rv = map { $_, $cluster->{$_} } @fields;
   $rv{jobstate}   = $self->sqlite->db->select( 'job_states', ['state'], { id => $rv{state_id} } )->hash->{state} if $rv{state_id};
   $rv{cal}        = $self->sqlite->db->select( 'cal',        ['name'],  { id => $rv{cal_id} } )->hash->{name}    if $rv{cal_id};
   $rv{jobs}       = $self->_find_jobs( $user, { cluster_id => $cluster_id } );
   $rv{needs}      = $self->_read_cluster_needs( $user, { id => $cluster_id } );
   $rv{next_start} = $self->_cal_next_start( $user, { id => $rv{cal_id} } ) if $rv{cal_id};
   return { success => 1, %rv };
}

sub _set_cluster_state {
   my ( $self, $user, $d ) = @_;

   # id state

   my $update_hash = {};

   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id} } )->hash;

   if ( $self->job_states->{ $d->{state} } && $cluster->{state_id} ne $self->job_states->{immutable} ) {
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
   }

   if ( $d->{state} eq 'running' ) {
      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      # max duration hook
   }
   elsif ( $d->{state} eq 'complete' || $d->{state} eq 'fake_complete' ) {

      # loops
      if ( $d->{state} eq 'complete' ) {
         if ( $cluster->{loops} && $cluster->{loops} > $cluster->{loop_count} ) {
            my $loop_count = $cluster->{loop_count} || 0;
            $loop_count++;
            $self->sqlite->db->update( 'cluster', { loop_count => $loop_count, state_id => $self->job_states->{looping} }, { id => $cluster->{id} } );

            $self->_start_cluster(
               $user,
               {
                  id        => $cluster->{id},
                  force     => 1,
                  origin    => 'loop',
                  origin_id => $cluster->{id}
               }
            );
            return 1;
         }
         elsif ( $cluster->{loop_count} ) {
            $self->sqlite->db->update( 'cluster', { loop_count => 0 }, { id => $cluster->{id} } );
         }
      }

      $update_hash->{ended} = time;

      # update cluster
      $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster->{id} } );

      # complete parent cluster if possible
      if ( $cluster->{parent_id} && $self->_cluster_is_complete( $user, { id => $cluster->{parent_id} } ) ) {
         $self->_set_cluster_state( $user, { state => 'complete', id => $cluster->{parent_id} } );
      }

      # start waiting clusters that just had last dependency met
      my $complete = $self->job_states->{complete};
      my $waiting  = $self->job_states->{waiting};
      my $ready    = $self->job_states->{ready};
      my $ice      = $self->job_states->{ice};

      my $depends_sql = <<~"SQL";
         select cn.cluster_id as id
         from cluster_needs cn
         join cluster c on cn.cluster_id = c.id
         where cn.needs_cluster_id = $cluster->{id}
         and c.state_id in ($ready, $waiting, $ice)
      SQL

      my $cneed = $self->sqlite->db->query($depends_sql);

      while ( my $c = $cneed->hash ) {

         print "STARTING CLUSTER: $c->{id}\n";

         # start cluster if all dependancies are complete or on ice

         my $cluster_sql = <<~"SQL";
            select cn.needs_cluster_id, c.state_id
            from cluster_needs cn
            join cluster c on cn.needs_cluster_id = c.id
            where cn.cluster_id = $c->{id}
            and c.state_id not in ($complete, $ice)
         SQL

         my $ret = $self->sqlite->db->query($cluster_sql);

         unless ( $ret->hash ) {
            $self->start_cluster( $user, { id => $c->{id}, origin => 'auto', force => 1 } );
         }
      }
   }
   elsif ( $d->{state} eq 'failed' ) {
      $update_hash->{ended} = time;

      # fail hook
      if ( $cluster->{fail_hook} ) {
         my $hook_cluster = $self->sqlite->db->select( 'cluster', ['id'], { id => $cluster->{fail_hook} } );
         if ( $hook_cluster->{id} ) {
            $self->_start_cluster( $user, { id => $hook_cluster->{id}, origin => 'fail', force => 1 } );
         }
      }
   }
   elsif ( $d->{state} eq 'ready' ) {
      unless ($cluster->{ended}) {
         $update_hash->{ended} = time;
      }
   }
      
   # update cluster
   $self->sqlite->db->update( 'cluster', $update_hash, { id => $d->{id} } ) if scalar keys %{ $update_hash };
   return 1;
}

sub start_cluster {
   my ( $self, $user, $d ) = @_;
   $d->{source}    = 'user';
   $d->{source_id} = $user->{id};
   $self->_start_cluster( $user, $d );
}

sub _start_cluster {
   my ( $self, $user, $d ) = @_;

   # private options
   # origin: user, cron, job_fail, cluster_fail, loops, auto
   # origin_id
   # loop_count

   my $cluster = $self->read_cluster( $user, $d );
   return $cluster if $cluster->{success} == 0;
   my $cluster_id = $cluster->{id};

   return { success => 0, message => 'cluster not found' } unless $cluster_id;

   # check jobs are in ready state
   my $complete = $self->job_states->{complete};
   my $waiting  = $self->job_states->{waiting};
   my $running  = $self->job_states->{running};
   my $failed   = $self->job_states->{failed};
   my $ready    = $self->job_states->{ready};
   my $hold     = $self->job_states->{hold};
   my $ice      = $self->job_states->{ice};

   # hard stop if cluster is running
   if ( $cluster->{state_id} == $self->job_states->{running} ) {
      return { success => 0, message => 'cluster already running' };
      # TODO: clone if clonable
   }

   elsif ( $cluster->{id} == $user->root_cluster_id ) {
      return { success => 0, message => 'root cluster cannot be started' };
   }
   elsif ( $cluster->{state_id} == $self->job_states->{hold} ) {
      return { success => 0, skipped => 1, message => 'cluster on hold' };
   }
   elsif ( $cluster->{state_id} == $self->job_states->{ice} ) {
      $self->_set_cluster_state( $user, { id => $cluster_id, state => 'fake_complete' } );
      return { success => 0, skipped => 1, message => 'cluster on ice' };
   }

   unless ( $d->{force} ) {

      #if ( $cluster->{state_id} == $self->job_states->{running} ) {
      #   return { success => 0, message => 'cluster already running' };
      #}

      if ( $cluster->{next_start} && $d->{origin} ne 'cron' ) {
         return { success => 0, waiting => 1, message => 'expecting cron start. use --force to start anyway' };
      }
      elsif ( !$self->_cluster_is_ready( $user, { id => $cluster_id } ) ) {
         return { success => 0, skipped => 1, message => 'cluster not ready. use --force to start anyway' };
      }

      # return if cluster needs not met
      while ( my ( $id, $state_id ) = each %{ $cluster->{needs} } ) {
         if ( !grep { $state_id == $self->job_states->{$_} } (qw(complete)) ) {
            return { success => 0, waiting => 1, message => "dependency not met. use --force to start anyway" };
         }
      }
   }

   $self->_reset_cluster( $user, { id => $cluster_id } );

   $self->_set_cluster_state( $user, { state => 'running', id => $cluster_id } );

   # start clusters in cluster
   my $clusters_started = 0;
   my $clusters_completed = 0;
   my $clusters_failed  = 0;
   my $clusters_waiting = 0;
   my $clusters_skipped = 0;

   my $clusters = $self->sqlite->db->select(
      'cluster',
      ['id'],
      {
         org_id    => $user->org_id,
         parent_id => $cluster_id,
         state_id  => { '=', [ $ready, $waiting ] }
      },
      { -desc => 'id' }
   )->hashes;

   foreach my $c ( @{ $clusters->to_array } ) {
      my $rv = $self->_start_cluster( $user, { id => $c->{id}, origin => 'auto1' } );
      if ( $rv->{started} ) {
         $clusters_started++;
      }
      elsif ( $rv->{waiting} ) {
         $clusters_waiting++;
      }
      elsif ( $rv->{skipped} ) {
         $clusters_skipped++;
      }
      elsif ( $rv->{completed} ) {
         $clusters_completed++;
      }
      elsif ( $rv->{failed} ) {
         $clusters_failed++;
      }
   }

   # start jobs in cluster
   my $jobs_started = 0;
   my $jobs_failed  = 0;
   my $jobs_waiting = 0;
   my $jobs_skipped = 0;
   my $job_error;

   my $results = $self->sqlite->db->select(
      'job',
      ['id'],
      {
         cluster_id => $cluster_id,
         state_id   => { '=', [ $ready, $waiting ] }
      },
      { -desc => 'id' }
   )->hashes;

   foreach my $j ( @{ $results->to_array } ) {
      my $rv = $self->_start_job( $user, { origin => 'auto', origin_id => $cluster_id, %$j } );
      if ( $rv->{success} ) {
         $jobs_started++;
      }
      elsif ( $rv->{waiting} ) {
         $jobs_waiting++;
      }

      elsif ( $rv->{skipped} ) {
         $jobs_skipped++;
      }
      else {
         $jobs_failed++;
         $job_error = $rv->{message};
      }
   }

   my $message = "$jobs_started $jobs_waiting $jobs_skipped $jobs_failed $clusters_started $clusters_completed $clusters_failed $clusters_waiting $clusters_skipped";
   if ( $jobs_failed || $clusters_failed ) {
      $self->_set_cluster_state( $user, { state => 'failed', id => $cluster_id } );
      return { success => 0, failed => 1, message => "$jobs_failed failed jobs $clusters_failed failed clusters" };
   }
   #elsif ( $jobs_started || $clusters_started ) {
   #   $self->_set_cluster_state( $user, { state => 'running', id => $cluster_id } );
   #   return { success => 1, message => "$jobs_started jobs started $clusters_started clusters started" };
   #}
   elsif ( $jobs_waiting || $clusters_waiting ) {
      $self->_set_cluster_state( $user, { state => 'waiting', id => $cluster_id } );
      return { success => 1, waiting => 1, message => "$clusters_waiting clusters waiting $jobs_waiting jobs waiting" };
   }
   elsif ( $self->_cluster_is_complete( $user, { id => $cluster_id } ) ) {
      $self->_set_cluster_state( $user, { state => 'complete', id => $cluster_id } );
      return { success => 1, completed => 1, message => "cluster complete $cluster_id" };
   }
   else {
      #$self->_set_cluster_state( $user, { state => 'failed', id => $cluster_id } );
      return { success => 1, started => 1, message => "$jobs_skipped jobs skipped $clusters_skipped clusters skipped" };
   }
}

sub _reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};
   my $hold         = $self->job_states->{hold};
   my $ice          = $self->job_states->{ice};

   my $needs = $self->_read_cluster_needs( $user, { id => $cluster_id } );
   my $cluster_state = $cluster_info->{next_start} || scalar keys %$needs ? 'waiting' : 'ready';

   print "HERE1\n";
   # set cluster state to ready or waiting
   $self->_set_cluster_state( $user, { id => $cluster_id, state => $cluster_state } );

   print "HERE2\n";
   # set child job states to ready or waiting
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $hold, $ice ) ] } } );
   while ( my $job = $jobs->hash ) {
      my $needs     = $self->_read_job_needs( $user, { id => $job->{id} } );
      my $job_state = ( $cluster_info->{next_start} || scalar keys %$needs || $cluster_state eq 'waiting' ) ? 'waiting' : 'ready';
      $self->_set_job_state( $user, { id => $job->{id}, state => $job_state } );
   }

   print "HERE2\n";
   # reset descendent clusters
   my $clusters = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster_id, state_id => { '!=', [ -and => ( $hold, $ice ) ] } } );
   while ( my $cluster = $clusters->hash ) {
      $self->_reset_cluster( $user, { id => $cluster->{id} } );
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
   #my $cluster_id = $cluster->{id};

   # undef = root cluster, 0 = cluster not found
   #return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my @clusters;

   #if ($cluster_id) {
      my $is_readable = $self->is_readable( $user, { id => $cluster->{id} } );
      return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;
      #$cluster->{jobs}  = $self->_find_jobs( $user, { cluster_id => $cluster_id } );
      #$cluster->{needs} = $self->_read_cluster_needs( $user, { id => $cluster_id } );
      push @clusters, $cluster;
   #}

   my $find_clusters = sub {
      my $id     = shift;
      my $org_id = $user->org_id;

      my $sql = <<~"SQL";
         select c.*, js.state as jobstate
         from cluster c
         left join job_states js on c.state_id = js.id
         where parent_id = $id
         and org_id = $org_id 
         order by c.id
      SQL

      my $children = $self->sqlite->db->query($sql);

      while ( my $c = $children->hash ) {
         $c->{jobs}       = $self->_find_jobs( $user, { cluster_id => $c->{id} } );
         $c->{needs}      = $self->_read_cluster_needs( $user, { id => $c->{id} } );
         $c->{next_start} = $self->_cal_next_start( $user, { id => $c->{cal_id} } ) if $c->{cal_id};

         push @clusters, $c;
         __SUB__->( $c->{id} );
      }
      return;
   };

   $find_clusters->($cluster->{id});
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

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description max_duration loops clonable)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   # verify that hook clusters actually exist
   for my $hook ( grep { exists $d->{$_} } (qw(fail_hook max_duration_hook)) ) {
      if ( $d->{$hook} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$hook}, org_id => $user->org_id } )->hash;
         $update_hash->{$hook} = $d->{$hook} if $res->{id};
      }
      else {
         $update_hash->{$hook} = undef;
      }
   }

   # add cal_id
   my $cal;
   my $success = 0;

   eval {
      #my $tx = $self->sqlite->db->begin;
      if ( scalar keys %{$update_hash} ) {
         $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster_id } );
         $success++;
      }
      $self->_write_cluster_needs( $user, { id => $cluster_id, needs => $d->{needs} } ) if $d->{needs};
      if ( $d->{needs} ) {
         $self->_write_cluster_needs( $user, { id => $cluster_id, needs => $d->{needs} } );
         $success++;
      }

      if ( exists $d->{cal_id} || exists $d->{cal} ) {
         my $new_cal    = $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
         my $new_cal_id = $new_cal->{id} if $new_cal;
         die unless $self->_set_cluster_cal_id( $user, { cluster_id => $cluster_id, cal_id => $new_cal_id } );
         $success++;
      }
      elsif ( exists $d->{cron} || exists $d->{at} ) {
         if ( $d->{cron} ) {
            $self->_add_cluster_cron( $user, { id => $cluster_id, tz => $d->{tz}, cron => $d->{cron} } ) or die;
         }
         elsif ( $d->{at} ) {
            $self->_add_cluster_cron( $user, { id => $cluster_id, tz => $d->{tz}, at => $d->{at} } ) or die;
         }
         else {
            $self->_set_cluster_cal_id( $user, { cluster_id => $cluster_id, cal_id => undef } ) or die;
         }

         $success++;
      }

      #$tx->commit;
   };
   return { success => 0, message => $@ } if $@;
   return { success => $success };
}

sub delete_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );
   return $cluster if $cluster->{success} == 0;

   return { success => 0, message => 'cluster not found' } unless $cluster->{id};
   return { success => 0, message => 'root cluster cannot be deleted' } if $user->root_cluster_id == $cluster->{id};

   if ($cluster->{id}) {
      my $is_writable = $self->is_writable( $user, { id => $cluster->{id} } );
      return { success => 0, message => 'no write permissions on this cluster' } unless $is_writable;
   }

   # delete cluster and all descendants

   my $clusters = $self->find_cluster( $user, { id => $cluster->{id} } )->{clusters};
   push @{ $clusters }, $cluster;
   
   my $delete_count = 0;
   foreach my $c ( @{$clusters} ) {

      # delete jobs
      my $jobs = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $c->{id} } );
      while ( my $j = $jobs->hash ) {
         my $rv = $self->delete_job( $user, { id => $j->{id}, force => 1 } );
      }

      # delete cluster
      my $rows = $self->sqlite->db->delete( 'cluster', { id => $c->{id} } )->rows;
      $delete_count += $rows;
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
   return { success => 0, message => $@ } if $@;
   return $delete_count ? { success => 1, deleted => $delete_count } : { success => 0 };
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

   #return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   return { success => 0, message => 'cluster not found' } unless $cluster_id;
   my $user_info = $self->read_user($user);

   my $is_writable = $self->is_writable( $user, { id => $cluster_id } );
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;

   my $insert_hash = {
      org_id    => $user_info->{org_id},
      user_id   => $user_info->{id},
      parent_id => $cluster_id,
      name      => $name,
   };

   for (qw(loops max_cpu max_mem max_duration id state_id description started ended)) {
      $insert_hash->{$_} = $d->{$_} if $d->{$_};
   }

   # verify that hook clusters actually exist
   for my $hook ( grep { exists $d->{$_} } (qw(fail_hook max_duration_hook)) ) {
      if ( $d->{$hook} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$hook}, org_id => $user->org_id } )->hash;
         $insert_hash->{$hook} = $d->{$hook} if $res->{id};
      }
      else {
         $insert_hash->{$hook} = undef;
      }
   }

   $insert_hash->{mode} =
       $d->{mode}         ? $d->{mode}
     : $user_info->{mode} ? $user_info->{mode}
     :                      770;

   my $id = $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id;
   $self->_write_cluster_needs( $user, { id => $id, needs => $d->{needs} } ) if $d->{needs};

   if ( $d->{cron} || $d->{at} ) {
      my $rv = $self->_add_cluster_cron( $user, { id => $id, tz => $d->{tz}, cron => $d->{cron}, at => $d->{at} } );
   }
   return $id ? { success => 1, id => $id } : { success => 0 };
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
   #return { success => 0, message => 'unable to locate cluster' } if defined $cluster_id && $cluster_id == 0;
   return { success => 0, message => 'unable to locate cluster' } unless $cluster_id;

   my $fullpath  = $self->id2path($user, { id => $cluster_id });
   my $user_info = $self->read_user($user);
   eval { $self->sqlite->db->update( 'user', { base_cluster_id => $cluster_id }, { id => $user_info->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { path => $fullpath, cluster_id => $cluster_id, success => $success };
}

sub path2id {
   my ( $self, $user, $path ) = @_;
   #my $user_info       = $self->read_user($user);
   #my $base_cluster_id = $user_info->{base_cluster_id};
   my $base_cluster_id = $user->base_cluster_id;
   my $base_path       = $self->id2path($user, { id => $base_cluster_id });

   my $fullpath =
       ( $path && substr( $path, 0, 1 ) eq '/' ) ? $path
     : $path && $base_path                       ? "/$base_path/$path"
     : $path                                     ? "/$path"
     : $base_path                                ? "/$base_path"
     :                                             '/';

   my @parts    = grep { $_ } split( '/', $fullpath );
   my @ups      = grep { $parts[$_] eq '..' } ( 1 .. $#parts );
   my $up_count = scalar @ups;
   if ($up_count) {
      @parts = grep { $_ ne '..' } @parts;
      my $offset = $ups[0] - $up_count;
      $offset = $offset > 0 ? $offset : 0;
      splice( @parts, $offset, $up_count );
   }
   #my $parent_id = $user->root_cluster_id;
   my $parent_id = undef;

   # verify path exists
   foreach my $part (@parts) {
      my $c = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $parent_id, name => $part, org_id => $user->org_id } )->hash;
      #$parent_id = $result->{id};

      # invalid path
      return unless $c->{id};
      $parent_id = $c->{id};
   }

   # return cluster_id only if path really exists
   return $parent_id;
}

sub id2path {
   #my ( $self, $user, $d $cluster_id ) = @_;
   my ( $self, $user, $d ) = @_;

   my $cluster = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{id} } )->hash;
   my $cluster_id = $cluster->{id};

   my @names;
   my $count = 0;

   while (defined $cluster_id) {
      my $c = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
      #last unless $c->{parent_id};
      last unless $c->{id};

      # max depth of 10
      $count++;
      return if $count > 10;

      unshift( @names, $c->{name} );
      $cluster_id = $c->{parent_id};
   }

   return unless scalar @names;

   my $path = join( '/', @names );
   return $path;
}

# user related subroutines

sub login_user {
   my ( $self, $user, $d ) = @_;

   my $results = $self->sqlite->db->select( 'user', ['*'], { token => $d->{token} } )->hash;
   my $org = $self->sqlite->db->select( 'org', ['root_cluster_id'], { id => $results->{org_id} } )->hash;

   my ( $message, $success, $path );
   my $host = hostname();

   if ( $results->{id} ) {
      $user->id( $results->{id} );
      $user->level( $results->{level} );
      $user->org_id( $results->{org_id} );
      $user->token( $results->{token} );
      $user->base_cluster_id( $results->{base_cluster_id} );
      $user->root_cluster_id( $org->{root_cluster_id} );
      $path = $self->id2path( $user, { id => $results->{base_cluster_id} } );
      $message = 'login success';
      $success = 1;
   }
   else {
      $message = 'login failed';
      $success = 0;
   }
   return { message => $message, success => $success, user_id => $user->id, host => $host, path => $path, level => $user->level };
}

sub register_user {
   my ( $self, $user, $d ) = @_;
   my $new_user = $self->create_user($user, { level => 0 });
   if ($new_user->{success}) {
      #$user->id ( $new_user->{id} );
      my $login = $self->login_user($user, { token => $new_user->{token} });
      if ($login->{success}) {
         return { success => 1, token => $new_user->{token}, message => "registered and awaiting confirmation" };
      }
      else {
         return { success => 0 };
      }
   }
   else {
      return { success => 0 };
   }
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

      # create org
      my $org_id;
      if ($d->{org_id}) {
         my $org = $self->sqlite->db->select( 'org', ['id'], { id => $d->{org_id} } )->hash;
         if ($org->{id}) {
            $org_id = $org->{id};
         }
         else {
            die 'no such org';
         }
      }
      else {
         $org_id = $db->query("INSERT INTO org DEFAULT VALUES")->last_insert_id;
      }

      die "unable to create org" unless $org_id;

      # create root cluster
      my $root_id;

      my $root = $db->select( 'cluster', ['id'], { org_id => $org_id, name => 'root', parent_id => undef } );
      if ($root->{id}) {
         $root_id = $root->{id};
      }
      else {
         $root_id = $db->insert( 'cluster', { org_id => $org_id, name => 'root', mode => 550, state_id => $self->job_states->{immutable} } )->last_insert_id;
      }

      die "unable to create root cluster" unless $root_id;

      $user_insert->{org_id}          = $org_id;
      $user_insert->{base_cluster_id} = $root_id;
      $user_insert->{mode}            = 770;
      $user_id                        = $db->insert( 'user', $user_insert )->last_insert_id;
      die unless $user_id;
      #$user->id($user_id);

      # TODO: firewall config
      # TODO: nginx config for reverse proxy with self-signed certificate 
      # TODO: move register_user to separate app
      $db->update( 'org',     { user_id => $user_id, root_cluster_id => $root_id }, { id => $org_id } );
      $db->update( 'cluster', { user_id => $user_id }, { id => $root_id } );
      $tx->commit;
   };

   my $token = $self->new_token($user);
   return $@ ? { message => $@, success => 0 } : { success => 1, id => $user_id, token => $token->{token}, message => "user $user_id created" };
}

sub new_token {
   my ( $self, $user ) = @_;
   my $uuid = create_uuid_as_string();
   my $token = hmac_sha1_hex( $uuid );
   $self->sqlite->db->update( 'user', { token => $token }, { id => $user->id } )->hash;
   return { success => 1, token => $token };
}

sub read_user {
   my ( $self, $user, $decoded ) = @_;

   my $info = $self->sqlite->db->select( 'user', ['*'], { id => $user->id } )->hash;
   my $path = $self->id2path( $user, { id => $info->{base_cluster_id} } );

   return {
      id              => $info->{id},
      org_id          => $info->{org_id},
      name            => $info->{name},
      #token           => $info->{token},
      level           => $info->{level},
      email           => $info->{email},
      base_cluster_id => $info->{base_cluster_id},
      mode            => $info->{mode},
      remote_address  => $user->remote_address,
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
   my $rows;
   eval { $rows = $self->sqlite->db->delete( 'user', { id => $decoded->{id} } )->rows };
   return { success => 0, message => $@ } if $@;
   return { success => $rows, id => $decoded->{id} };
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
   #unless ( defined $cluster_id && $cluster_id == 0 ) {
   if ( $cluster_id ) {
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

sub hold_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};
   return { success => 0, message => 'cluster is running' } if $cluster->{state_id} == $self->job_states->{running};

   my $running    = $self->job_states->{running};
   my $cluster_id = $cluster->{id};

   unless ( $self->_cluster_is_ready( $user, { id => $cluster->{id} } ) ) {
      return { success => 0, message => 'cluster not ready' };
   }

   # hold cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'hold' } );

   # hold child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'hold' } );
   }

   # hold child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $child = $children->hash ) {
      $self->hold_cluster( $user, { id => $child->{id}, state => 'hold' } );

      #$self->_set_cluster_state( $user, { id => $child->{id}, state => 'hold' } );
   }

   return { success => 1 };
}

sub release_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }   unless $cluster->{id};
   return { success => 0, message => 'cluster not on hold' } unless $cluster->{state_id} == $self->job_states->{hold};

   my $hold = $self->job_states->{hold};

   # release cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'ready' } );

   # release child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => $hold } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'ready' } );
   }

   # release child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => $hold } );
   while ( my $child = $children->hash ) {
      $self->release_cluster( $user, { id => $child->{id} } );
   }

   # start cluster if parent is running
   my $parent = $self->sqlite->db->select( 'cluster', ['state_id'], { id => $cluster->{parent_id} } )->hash;

   if ( $parent && $parent->{state_id} == $self->job_states->{running} ) {
      my $rv = $self->_start_cluster(
         $user,
         {
            id     => $cluster->{id},
            origin => 'auto2',
         }
      );
   }
   return { success => 1 };
}

sub ice_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};
   return { success => 0, message => 'cluster is running' } if $cluster->{state_id} == $self->job_states->{running};

   my $running    = $self->job_states->{running};
   my $cluster_id = $cluster->{id};

   unless ( $self->_cluster_is_ready( $user, { id => $cluster->{id} } ) ) {
      return { success => 0, message => 'cluster not ready' };
   }

   # ice cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'ice' } );

   # ice child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'ice' } );
   }

   # hold child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $child = $children->hash ) {
      $self->ice_cluster( $user, { id => $child->{id}, state => 'ice' } );
   }
   return { success => 1 };
}

sub melt_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }  unless $cluster->{id};
   return { success => 0, message => 'cluster not on ice' } unless $cluster->{state_id} == $self->job_states->{ice};

   my $ice = $self->job_states->{ice};

   # release cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'ready' } );

   # release child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => $ice } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'ready' } );
   }

   # release child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => $ice } );
   while ( my $child = $children->hash ) {
      $self->melt_cluster( $user, { id => $child->{id} } );
   }
   return { success => 1 };
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
   return { success => 0, message => 'jobs not allowed in the root cluster' } if $user->root_cluster_id == $j->{cluster_id};

   #return { success => 0, message => 'you do not have permission to write to this cluster' } unless $j->{is_writable};

   my $insert_hash = { cluster_id => $j->{cluster_id}, name => $j->{name} };
   $insert_hash->{loop_delay}  = $d->{loop_delay}  if $d->{loop_delay}  && $d->{loop_delay} <= 3600;
   $insert_hash->{retry_delay} = $d->{retry_delay} if $d->{retry_delay} && $d->{retry_delay} <= 3600;

   my @fields = qw(retrys loops fail max_cpu max_mem max_duration id state_id description started ended);

   for (@fields) {
      $insert_hash->{$_} = $d->{$_} if $d->{$_};
   }

   # verify that hook clusters actually exist
   for my $hook ( grep { exists $d->{$_} } (qw(fail_hook max_cpu_hook max_mem_hook max_duration_hook)) ) {
      if ( $d->{$hook} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$hook}, org_id => $user->org_id } )->hash;
         $insert_hash->{$hook} = $d->{$hook} if $res->{id};
      }
      else {
         $insert_hash->{$hook} = undef;
      }
   }

   if ( $d->{script} ) {
      $insert_hash->{script} = $d->{script};
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
   return { success => 0, message => 'job is running' } if $job->{state_id} == $self->job_states->{running};
   $self->_set_job_state( $user, { state => 'ice', id => $job->{id} } );
   return { success => 1 };
}

sub release_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' }   unless $job->{id};
   return { success => 0, message => 'job not on hold' } unless $job->{state_id} == $self->job_states->{hold};

   $self->_set_job_state( $user, { state => 'ready', id => $job->{id} } );

   my $cluster_state_id = $self->read_cluster( $user, { id => $job->{cluster_id} } )->{state_id};

   if ( scalar( grep { $cluster_state_id == $self->job_states->{$_} } (qw(running waiting)) ) ) {
      $self->_start_job(
         $user,
         {
            id        => $job->{id},
            origin    => 'auto',
            origin_id => $job->{cluster_id}
         }
      );
   }
   return { success => 1 };
}

sub hold_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   return { success => 0, message => 'job is running' } if $job->{state_id} == $self->job_states->{running};
   $self->_set_job_state( $user, { id => $job->{id}, state => 'hold' } );
   return { success => 1 };
}

# returns true if cluster is ready to start
sub _cluster_is_ready {
   my ( $self, $user, $d ) = @_;

   my $id = $d->{id};

   my $complete = $self->job_states->{complete};
   my $waiting  = $self->job_states->{waiting};
   my $ready    = $self->job_states->{ready};
   my $hold     = $self->job_states->{hold};
   my $ice      = $self->job_states->{ice};

   my $c = $self->sqlite->db->select( 'cluster', ['*'], { parent_id  => $id, state_id => { '!=', [ -and => ( $waiting, $complete, $ready, $ice, $hold ) ] } }, { limit => 1 } )->hash;
   my $j = $self->sqlite->db->select( 'job',     ['*'], { cluster_id => $id, state_id => { '!=', [ -and => ( $waiting, $complete, $ready, $ice, $hold ) ] } }, { limit => 1 } )->hash;

   return $c->{id} || $j->{id} ? 0 : 1;
}

# returns true if cluster is complete
sub _cluster_is_complete {
   my ( $self, $user, $d ) = @_;

   my $cluster_id = $d->{id};

   my $complete = $self->job_states->{complete};
   my $ready    = $self->job_states->{ready};
   my $ice      = $self->job_states->{ice};

   my $jb = $self->sqlite->db->select( 'job',     ['*'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $complete, $ice ) ] } }, { limit => 1 } );
   my $cl = $self->sqlite->db->select( 'cluster', ['*'], { parent_id  => $cluster_id, state_id => { '!=', [ -and => ( $complete, $ice ) ] } }, { limit => 1 } );

   return !$jb->hash && !$cl->hash ? 1 : 0;
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

   my $update_hash;

   if ( $self->job_states->{ $d->{state} } ) {
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
   }

   if ( $d->{state} eq 'starting' ) {
      $self->_reset_job_stats( $user, { id => $job->{id} } );
   }

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
            my $retry_count = $job->{retry_count} || 0;
            if ( $job->{retrys} > $retry_count ) {
               $retry_count++;
               $self->sqlite->db->update( 'job', { retry_count => $retry_count }, { id => $job->{id} } );

               my $rv = $self->_start_job(
                  $user,
                  {
                     id        => $job->{id},
                     force     => 1,
                     origin    => 'retry',
                     origin_id => $job->{cluster_id}
                  }
               );
            }
         }
         elsif ( $job->{retry_count} ) {
            $self->sqlite->db->update( 'job', { retry_count => 0 }, { id => $job->{id} } );
         }

         # fail hook
         if ( $job->{fail_hook} ) {
            my $cluster_hook = $self->sqlite->db->select( 'cluster', ['id'], { id => $job->{fail_hook} } )->hash;
            if ( $cluster_hook->{id} ) {
               my $rv = $self->_start_cluster(
                  $user,
                  {
                     id     => $cluster_hook->{id},
                     origin => 'fail',
                     force  => 1,
                  }
               );
            }
         }
      }
   }
   elsif ( $d->{state} eq 'complete' || $d->{state} eq 'fake_complete' ) {

      $self->sqlite->db->update( 'job', { state_id => $self->job_states->{complete} }, { id => $job->{id} } ) unless $d->{state} eq 'fake_complete';

      if ( $d->{state} eq 'complete' ) {

         # loops
         if ( $job->{loops} && $job->{loops} > $job->{loop_count} ) {
            my $loop_count = $job->{loop_count} || 0;
            $loop_count++;

            #$self->sqlite->db->update( 'job', { loop_count => $loop_count }, { id => $job->{id} } );
            $self->sqlite->db->update( 'job', { loop_count => $loop_count, state_id => $self->job_states->{looping} }, { id => $job->{id} } );

            $self->_start_job(
               $user,
               {
                  id        => $job->{id},
                  force     => 1,
                  origin    => 'loop',
                  origin_id => $job->{cluster_id}
               }
            );
         }
         elsif ( $job->{loop_count} ) {
            $self->sqlite->db->update( 'job', { loop_count => 0 }, { id => $job->{id} } );
         }
      }

      # find jobs in ready or waiting state that just had a dependency met
      my $depends_sql = <<~"SQL";
         select jn.job_id, j.state_id
         from job_needs jn
         join job j on jn.job_id = j.id
         where jn.needs_job_id = $job->{id}
         and j.state_id in ($ready, $waiting, $ice)
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

         if ( !$ret->hash ) {

            #unless ( $d->{state} eq 'fake_complete') {
            #   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
            #}
            my $rv = $self->_start_job(
               $user,
               {
                  id     => $j->{job_id},
                  origin => 'auto',
                  force  => 1,
               }
            );
         }
      }
      $update_hash->{ended} = time;
      $self->_reset_job_stats( $user, { id => $job->{id} } );

      if ( $self->_cluster_is_complete( $user, { id => $job->{cluster_id} } ) ) {
         $self->_set_cluster_state( $user, { state => 'complete', id => $job->{cluster_id} } );
      }
   }
   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   return 1;
}

sub update_job {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_update_job( $user, $d );
   return $rv;
}

sub _update_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless $job->{id};

   my $success = 0;
   my @fields  = qw(retrys loops max_cpu max_mem max_duration signal ppid pid exit_code id state_id description started ended server_id script);

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } @fields };

   # verify that hook clusters actually exist
   for my $hook ( grep { exists $d->{$_} } (qw(fail_hook max_cpu_hook max_mem_hook max_duration_hook)) ) {
      if ( $d->{$hook} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$hook}, org_id => $user->org_id } )->hash;
         $update_hash->{$hook} = $d->{$hook} if $res->{id};
      }
      else {
         $update_hash->{$hook} = undef;
      }
   }

   $update_hash->{loop_delay}  = $d->{loop_delay}  if $d->{loop_delay}  && $d->{loop_delay} <= 3600;
   $update_hash->{retry_delay} = $d->{retry_delay} if $d->{retry_delay} && $d->{retry_delay} <= 3600;

   if ( $d->{state} ) {
      my $rv = $self->_set_job_state( $user, { id => $job->{id}, state => $d->{state} } );
      $success++ if $rv;

      # job log
      if ( $d->{log_id} && $d->{ppid} ) {
         if ( $d->{state} eq 'running' ) {
            my $insert_hash = { map { $_ => $d->{$_} } grep { defined $d->{$_} } (qw(log_id ppid pid started)) };
            $insert_hash->{job_id} = $job->{id};
            my $rows = $self->sqlite->db->insert( 'job_log', $insert_hash )->rows;

            # delete oldest log
            if ($rows) {
               my $count = $self->sqlite->db->query("select count(*) as count from job_log where job_id = $d->{id}")->hash->{count};
               if ( $count > 10 ) {
                  my $dl = $self->sqlite->db->select( 'job_log', ['*'], { job_id => $job->{id} }, { order_by => 'id', limit => 1 } )->hash;
                  $self->sqlite->db->delete( 'job_log', { id => $dl->{id} } );

                  my $ssh = $self->ssh_connection->{ $job->{server_id} };
                  unless ( $ssh && $ssh->check_master ) {
                     $self->_connect_ssh( $user, { id => $job->{server_id} } );
                     $ssh = $self->ssh_connection->{ $job->{server_id} };
                  }
                  # TODO: multi-platform script
                  $ssh->spawn("rm cc_worker/logs/*\.$dl->{job_id}\.$dl->{ppid}\.$dl->{log_id}\.log");
               }
            }
         }
         else {
            my $update_hash = { map { $_ => $d->{$_} } grep { defined $d->{$_} } (qw(log_id ppid pid exit_code signal ended)) };
            $update_hash->{job_id} = $d->{id};
            $self->sqlite->db->update( 'job_log', $update_hash, { job_id => $job->{id}, log_id => $d->{log_id}, ppid => $d->{ppid} } );
         }
      }
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

   my $needs;
   my $success = 0;
   return 0 unless ref $d->{needs} eq 'ARRAY';
   my @n = grep { $_ =~ /^\d{1,10}$/ } @{ $d->{needs} };
   $needs = $self->sqlite->db->select( 'job', ['id'], { id => { '=', [@n] } } )->hashes->to_array;

   eval {
      my $tx   = $self->sqlite->db->begin;
      my $rows = $self->sqlite->db->delete( 'job_needs', { job_id => $d->{id} } )->rows;
      $success++ if $rows;

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
   $uh->{ping}        = $self->_ping( $server->{host} ) if $server->{host};
   $uh->{update_time} = time;
   my $running  = $self->job_states->{running};
   my $watching = $self->job_states->{watching};
   my $starting = $self->job_states->{starting};
   my $stopping = $self->job_states->{stopping};

   # receive pid info
   if ( $d->{pids} && ref $d->{pids} eq 'ARRAY' ) {
      foreach my $pid ( @{ $d->{pids} } ) {
         my $job = $self->sqlite->db->select( 'job', ['id'], { server_id => $server->{id}, pid => $pid->{pid} } )->hash;
         next unless $job->{id};
         my $update = { map { $_, $pid->{$_} } grep { exists $pid->{$_} } (qw(pctcpu pid time start size priority rss pctmem ppid state cmndline fname)) };
         $update->{last_update} = time;
         $self->sqlite->db->update( 'job', $update, { id => $job->{id} } );

         if ( $job->{stats} ) {
            my $js_insert = { map { $_, $update->{$_} } (qw(pctcpu pid time start size priority rss pctmem ppid state fname)) };
            $self->sqlite->db->insert( 'job_stats', $js_insert );
         }

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
   my $pids = $self->sqlite->db->select( 'job', ['pid'], { server_id => $d->{id}, pid => { '!=', undef }, state_id => [ $stopping, $starting, $running, $watching ] } );
   while ( my $next = $pids->hash ) {
      push @pids, $next->{pid};
   }

   if ( $server->{stats} ) {
      my $ss_insert = { map { $_, $uh->{$_} } (qw(total_memory used_memory cpu total_disk used_disk uptime)) };
      $self->sqlite->db->insert( 'server_stats', $ss_insert );
   }

   eval { $self->sqlite->db->update( 'server', $uh, { id => $d->{id} } ); };
   return $@ ? { success => 0 } : { success => 1, pids => \@pids };
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

sub complete_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};

   $self->_set_job_state( $user, { id => $job->{id}, state => 'complete' } );
   return { success => 1 };
}

sub start_job {
   my ( $self, $user, $d ) = @_;
   $d->{origin} = 'user';
   return $self->_start_job( $user, $d );
}

sub _start_job {
   my ( $self, $user, $d ) = @_;

   # custom options
   # origin: user, auto, loop, retry
   # origin_id
   # retry_count, loop_count

   my $job = $self->_job_info( $user, $d );
   return { success => 0, skipped => 1, message => 'job not found' } unless $job->{id};

   if ( scalar grep { $self->job_states->{$_} == $job->{state_id} } (qw(starting running)) ) {
      return { success => 0, skipped => 1, message => 'job is already running' };
   }

   # skip if job on ice
   if ( $job->{state_id} == $self->job_states->{ice} ) {

      # fake_complete does everything a complete would do except set the job state
      $self->_set_job_state( $user, { id => $job->{id}, state => 'fake_complete' } );
      return { success => 0, skipped => 1, message => 'job on ice' };
   }

   # don't start if dependencies not satisfied

   unless ( $d->{force} ) {
      if ( $job->{state_id} == $self->job_states->{waiting} ) {
         while ( my ( $id, $state_id ) = each %{ $job->{needs} } ) {
            if ( !grep { $state_id == $self->job_states->{$_} } (qw(complete)) ) {

               # dependency not met
               return { success => 0, waiting => 1, message => 'dependency not met. use --force to start anyway' };
            }
         }
      }

      elsif ( $job->{state_id} != $self->job_states->{ready} ) {
         return { success => 0, message => 'job not ready. use --force to start anyway' };
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

   # second try
   unless ( $ssh && $ssh->check_master ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'failed' } );
      return { success => 0, message => 'connection failed' };
   }

   my $token = $user->token;
   my $opts  = { token => $token, id => $job->{id}, cluster_id => $job->{cluster_id}, script => $job->{script} };
   $opts->{origin_id} = $d->{origin_id} if $d->{origin_id};
   if ( $d->{origin} eq 'retry' ) {
      $opts->{origin} = $d->{origin};
      $opts->{delay}  = $job->{retry_delay};
   }
   elsif ( $d->{origin} eq 'loop' ) {
      $opts->{origin} = $d->{origin};
      $opts->{delay}  = $job->{loop_delay};
   }

   my $json = encode_json($opts);

   # TODO: encode with MIME::Base64
   my $json_hex = unpack( 'H*', $json );
   my $cmd      = "perl cc_worker/script/launcher.pl $json_hex";

   $self->_set_job_state( $user, { id => $job->{id}, state => 'starting' } );

   $ssh->spawn($cmd);

   #$ssh->system($cmd);
   if ( $ssh->error ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'failed' } );
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
   $self->_set_job_state( $user, { id => $job->{id}, state => 'killed' } );

   return $rv ? { success => 1 } : { success => 0 };
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

   #my %update = map { $_ => undef } (qw(signal exit_code pctcpu time start size priority rss pctmem state cmndline fname));
   eval { $self->sqlite->db->update( 'job', \%update, { id => $job->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

# server related subroutines

sub ssh_copy {
   my ( $self, $user, $d ) = @_;
   my $success = $self->_ssh_copy( $user, $d );
   return { success => $success };
}

sub _ssh_copy {
   my ( $self, $user, $d ) = @_;

   my $s = $self->_server_info( $user, $d );
   return 0 unless $s;

   my $port = $s->{port} || 22;
   my $password = $d->{password} || $s->{password} || '';
   return 0 unless $password;

   # copy public ssh key to remote host
   my $copy_key  = "sshpass -p $password ssh-copy-id -p $port $s->{user}\@$s->{host}";
   print "COPY: $copy_key\n";
   system($copy_key);
   my $exit_code = $? >> 8;
   return $exit_code ? 0 : 1; 
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

      my $token = $user->token;
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
   my $token = $user->token;

   my $exit_code = $self->_ssh_copy( $user, $d ) if $d->{password};

   my $port        = $d->{port} || 22;
   my $insert_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(name user host password)) };
   $insert_hash->{port}   = $port;
   $insert_hash->{org_id} = $user->org_id;

   my ( $id, $json, $cwd );

   eval {
      my $tx = $self->sqlite->db->begin;

      # create monitor and start it
      $id = $self->sqlite->db->insert( 'server', $insert_hash )->last_insert_id or die;
      $self->_connect_ssh( $user, { id => $id } )     or die "connect failed";
      $self->_install_monitor( $user, { id => $id } ) or die "install failed";
      $self->_start_monitor( $user, { id => $id } )   or die "start failed";

      # create monitor cluster if it doesn't already exist
      my $monitors = $self->sqlite->db->select( 'cluster', ['id'], { org_id => $user->org_id, name => 'monitors', parent_id => $user->root_cluster_id } )->hash;
      unless ( $monitors->{id} ) {
         my $monitors = $self->create_cluster( $user, { name => '/root/monitors', mode => 550 } );
         die "create monitor cluster failed" unless $monitors->{success};
      }

      # create monitor job
      my $server = $self->_server_info( $user, { id => $id } );
      die "missing server" unless $server->{id};
      $json = encode_json( { token => $token, id => $id } );
      $cwd  = $server->{cwd} || '';
      my $rv = $self->_create_job( $user, { name => "/root/monitors/$d->{name}", script => "$cwd/cc_worker/script/sysinfo.pl $json", server_id => $id } );
      die "create monitor job failed" unless $rv->{success};
      my $sj = $self->_start_job(
         $user,
         {
            id        => $rv->{id},
            origin    => 'auto',
            origin_id => $monitors->{id},
            force     => 1,
         }
      );
      die "unable to start monitor" unless $sj->{success};
      $tx->commit;
   };

   return $@ ? { success => 0, message => $@, exit_code => $exit_code, %{$d} } : { success => 1, %{$d} };
}

sub read_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->sqlite->db->select( 'server', ['*'], { org_id => $user->org_id } );
   my @s;
   while ( my $server = $servers->hash ) {
      my $info = { map { $_, $server->{$_} } (qw(id os cwd home cores update_time ping user host name port total_memory used_memory cpu total_disk used_disk uptime)) };
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

   my $info = { map { $_, $server->{$_} } (qw(id os cwd home cores update_time ping user host name port total_memory used_memory cpu total_disk used_disk uptime)) };
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
   my $token = $user->token;
   my $s     = $self->_server_info( $user, $d );

   return unless $s && $s->{id} && $s->{user} && $s->{host};
   my $port    = $s->{port} || 22;
   my $old_ssh = $self->ssh_connection->{ $s->{id} };
   if ( $old_ssh && ref $old_ssh ) {
      $old_ssh->disconnect(0);
      undef $old_ssh;
      undef $self->ssh_connection->{ $s->{id} };
   }

   my %option = (
      user       => $s->{user},
      port       => $port,
      batch_mode => 1,
      timeout    => 3,

      #kill_ssh_on_timeout => 1,
      #master_opts => [-o => "ControlPersist=10m" ],
      master_opts => [ -o => "ControlMaster=auto" ],
   );

   my $ssh = Net::OpenSSH->new( $s->{host}, %option );

   return if $ssh->error || !$ssh->check_master;

   # add connection
   $self->ssh_connection->{ $s->{id} } = $ssh;

   return 1;
}

sub _start_monitor {
   my ( $self, $user, $d ) = @_;
   my $token = $user->token;
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

   my $job = $self->_job_info( $user, { name => "/root/monitors/$server->{name}" } );
   return { success => 0, message => 'monitor job not found' } unless $job->{id};

   my $rv = $self->_hard_kill_job( $user, { id => $job->{id} } );

   return $rv;
}

sub start_monitor {
   my ( $self, $user, $d ) = @_;
   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

   my $job = $self->_job_info( $user, { name => "/root/monitors/$server->{name}" } );

   return { success => 0, message => 'monitor job not found' } unless $job->{id};
   return $self->start_job( $user, { id => $job->{id}, force => 1, origin => 'auto', origin_id => $job->{cluster_id} } );
}

sub update_monitor {
   my ( $self, $user, $d ) = @_;

   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

   my $update_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(user host password)) };
   if (scalar keys %{ $update_hash }) {
      eval { $self->sqlite->db->update( 'server', $update_hash, { id => $server->{id} } ) };
      return  { success => 0, message => $@ } if $@;
   }

   my $exit_code = $self->_ssh_copy( $user, { id => $server->{id}, password => $d->{password} } ) if $d->{password};
   my $connection_ok = $self->_connect_ssh($user, { id => $server->{id} });
   return $connection_ok ?  { success => 1 } :  { success => 0, message => 'connection failed' };
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
   my $ci  = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $user->root_cluster_id, name => 'monitors', org_id => $user->org_id } )->hash;
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

# log related subroutines

sub read_log {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );

   return { success => 0, message => 'job not found' } unless $job->{id};

   my $log;
   if ($d->{log}) {
      $log = $self->sqlite->db->select( 'job_log', ['*'], { id => $d->{log} } )->hash;
   }
   else {
      $log = $self->sqlite->db->query("select * from job_log where job_id = $job->{id} order by id desc limit 1")->hash;
   }

   return { success => 0, message => 'log not found' } unless $log->{id};
   return { success => 0, message => 'server not found' } unless $job->{server_id};

   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $job->{server_id} } );
      $ssh = $self->ssh_connection->{ $job->{server_id} };
   }

   my $o = "cc_worker/logs/out.$log->{job_id}.$log->{ppid}.$log->{log_id}.log";
   #my $e = "cc_worker/logs/err.$log->{job_id}.$log->{ppid}.$log->{log_id}.log";

   # TODO: change to cross-platform script
   my $out = $ssh->capture("cat $o");
   #my $err = $ssh->capture("cat $e") if $log->{exit_code};

   return $ssh->error ? { success => 0, message => $ssh->error } : { success => 1, out => $out };
}

sub find_log {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );

   return { success => 0, message => 'job not found' } unless $job->{id};
   my @all;
   my $logs = $self->sqlite->db->select( 'job_log', ['*'], { job_id => $job->{id} } );

   while ( my $log = $logs->hash ) {
      push @all, $log;
   }
   my $path = $self->id2path($user, { id => $job->{cluster_id} });
   return scalar @all ? { success => 1, path => $path, name => $job->{name}, logs => \@all } : { success => 0, message => 'no logs found' };

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
            my $rv = $self->_start_cluster( $user, { id => $cluster_id, origin => 'cron' } );
            print "start cluster: $cluster_id " . localtime(time) . "\n";
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
      'read_user'   => [ \&read_user,   0, [ {},             {} ] ],
      'update_user' => [ \&update_user, 1, [ {},             { email => $e, name => $w } ] ],
      'delete_user' => [ \&delete_user, 3, [ { id => $i }, {} ] ],
      'login_user'  => [ \&login_user,  0, [ { token => $w }, {} ] ],
      'new_token'  => [ \&new_token,  3, [ {}, {} ] ],
      'register_user' => [ \&register_user,  0, [ {}, {} ] ],

      # job related
      'create_job' => [
         \&create_job,
         1,
         [
            { name => $p, script => $c, server => $w },
            {
               needs             => 's',
               description       => $d,
               retrys            => $i,
               retry_delay       => $i,
               loops             => $i,
               loop_delay        => $i,
               fail_hook         => $i,
               max_cpu           => $f,
               max_cpu_hook      => $i,
               max_mem           => $f,
               max_mem_hook      => $i,
               max_duration      => $i,
               max_duration_hook => $i,
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
               name              => $p,
               id                => $i,
               signal            => $i,
               exit_code         => $i,
               server_id         => $i,
               mem               => $f,
               cpu               => $f,
               newname           => $w,
               state             => $w,
               server            => $w,
               ppid              => $i,
               pid               => $i,
               script            => $c,
               started           => $i,
               needs             => 's',
               ended             => $i,
               retrys            => $i,
               retry_delay       => $i,
               loops             => $i,
               loop_delay        => $i,
               fail_hook         => $i,
               max_cpu           => $f,
               max_cpu_hook      => $i,
               max_mem           => $f,
               max_mem_hook      => $i,
               max_duration      => $i,
               max_duration_hook => $i,
               log_id            => $i,
            }
         ]
      ],
      'delete_job'   => [ \&delete_job,   1, [ {}, { name => $p, id => $i, force     => $i } ] ],
      'start_job'    => [ \&start_job,    1, [ {}, { name => $p, id => $i, force     => $i } ] ],
      'watch_job'    => [ \&watch_job,    1, [ {}, { name => $p, id => $i, server_id => $i, server => $w, pid => $i, match => $c } ] ],
      'kill_job'     => [ \&kill_job,     1, [ {}, { name => $p, id => $i } ] ],
      'nice_job'     => [ \&nice_job,     1, [ {}, { name => $p, id => $i } ] ],
      'hold_job'     => [ \&hold_job,     1, [ {}, { name => $p, id => $i } ] ],
      'release_job'  => [ \&release_job,  1, [ {}, { name => $p, id => $i } ] ],
      'ice_job'      => [ \&ice_job,      1, [ {}, { name => $p, id => $i } ] ],
      'melt_job'     => [ \&melt_job,     1, [ {}, { name => $p, id => $i } ] ],
      'complete_job' => [ \&complete_job, 1, [ {}, { name => $p, id => $i } ] ],

      # cluster related
      'create_cluster' => [
         \&create_cluster,
         1,
         [
            { name => $p },
            {
               needs             => 's',
               mode              => $i,
               description       => $d,
               cron              => $ct,
               at                => $at,
               cal               => $cal,
               cal_id            => $at,
               tz                => $p,
               clonable          => $i,
               loops             => $i,
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
               clonable          => $i,
               loops             => $i,
               fail_hook         => $i,
               max_duration      => $i,
               max_duration_hook => $i,
            }
         ]
      ],
      'delete_cluster'  => [ \&delete_cluster,  1, [ {}, { name => $p, id   => $i } ] ],
      'change_cluster'  => [ \&change_cluster,  1, [ {}, { name => $p, id   => $i } ] ],
      'find_cluster'    => [ \&find_cluster,    1, [ {}, { name => $p, id   => $i } ] ],
      'reset_cluster'   => [ \&reset_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'start_cluster'   => [ \&start_cluster,   1, [ {}, { id   => $i, name => $p, force     => $i } ] ],
      'clone_cluster'   => [ \&clone_cluster,   1, [ {}, { id   => $i, name => $p, parent_id => $i } ] ],
      'ice_cluster'     => [ \&ice_cluster,     1, [ {}, { id   => $i, name => $p } ] ],
      'melt_cluster'    => [ \&melt_cluster,    1, [ {}, { id   => $i, name => $p } ] ],
      'hold_cluster'    => [ \&hold_cluster,    1, [ {}, { id   => $i, name => $p } ] ],
      'release_cluster' => [ \&release_cluster, 1, [ {}, { id   => $i, name => $p } ] ],

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

      # logs
      'find_log'   => [ \&find_log,   1, [ {}, { name => $p, id => $i } ] ],
      'read_log'   => [ \&read_log,   1, [ {}, { name => $p, id => $i, log => $i } ] ],

      # monitor related
      'create_monitor' => [
         \&create_monitor,
         1,
         [
            { name => $w, user => $w, host => $p },
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
               user => $w,
               host => $p,
               password => $pw,
            }
         ]
      ],
      'delete_monitor'  => [ \&delete_monitor,  1, [ {},                                             { id       => $i, name => $p } ] ],
      'ssh_copy'        => [ \&ssh_copy,        1, [ { name => $w, user => $w, host => $p }, { password => $pw } ] ],
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
