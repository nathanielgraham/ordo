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
use Data::Dumper;

# TODO: inheritance, threshholds, dependencies, monitor time series stats
$SIG{CHLD} = sub {
   1 while ( ( waitpid( -1, WNOHANG ) ) > 0 );
};

has 'user' => sub {
   state $user = {};
};

has 'ssh_connection' => sub {
   state $user = {};
};

# This method will run once at server start
sub startup {

   my $self = shift;

   # Configure the application
   $self->secrets( [ 'gu$!$#UessM%#eI36#$fYo43@#$uC^%5an', '%!#GDA$#!gfds%#@sdf' ] );

   # Helpers
   $self->helper( request => \&request );
   $self->helper( routing => \&routing );
   $self->helper( sqlite  => sub { state $sql = Mojo::SQLite->new("$Bin/../db/ordo.db") } );

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
      where s.active = 1
      group by s.id;
   SQL
   my $results = $self->sqlite->db->query($monitor_sql);
   while ( my $s = $results->hash ) {
      my $user = ordo::Model::User->new( id => $s->{mid}, org_id => $s->{org_id} );
      $self->_install_monitor($user, { id => $s->{id} });
      $self->_start_monitor($user, { id => $s->{id} });
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
            unless ( $regex eq 's' || $params->{$param} =~ $regex ) {
               $error      = 1;
               $bad_option = $param;
               last;
            }

         }
         $response =
           $error
           ? { success => 0, message => "invalid option: $bad_option" }
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

   my $c           = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
   my $is_readable = $self->is_readable( $user, $c );
   return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;
   my @fields = qw(id mode org_id user_id parent_id server_id state_id name description started ended);
   my %rv     = map { $_, $c->{$_} } @fields;
   return { success => 1, %rv };
}

sub find_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;

   my @clusters;

   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
      my $is_readable = $self->is_readable( $user, $top );
      return { success => 0, message => 'you do not have permission to read this cluster' } unless $is_readable;

      my $jobs = $self->_job_info( $user, { cluster_id => $cluster_id } )->{jobs};
      $top->{jobs} = $jobs;
      push @clusters, $top;
   }

   my $find_clusters = sub {
      my $id      = shift;
      my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { parent_id => $id } );
      while ( my $c = $cluster->hash ) {
         my $jobs = $self->_job_info( $user, { cluster_id => $c->{id} } )->{jobs};
         $c->{jobs} = $jobs;
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
   my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );    # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
      my $is_writable = $self->is_writable( $user, $top );
      return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;
   }

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   eval { $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster_id } ); };
   my $fullpath = $self->id2path($cluster_id);
   my $success  = $@ ? 0 : 1;
   return { success => $success, id => $cluster_id, path => $fullpath };
}

sub delete_cluster {
   my ( $self, $user, $decoded ) = @_;
   my $cluster_id = $decoded->{id} || $self->path2id( $user, $decoded->{name} );

   # undef = root cluster, 0 = cluster not found
   return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
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
      eval { $self->sqlite->db->delete( 'cluster', { id => $c->{id} } ); };
   }

   my $fullpath = $self->id2path($cluster_id);
   my $success  = $@ ? 0 : 1;
   return { success => $success, id => $cluster_id, path => $fullpath };
}

sub create_cluster {
   my ( $self, $user, $decoded ) = @_;

   my ($root) = $decoded->{name} =~ /^(\/)/;
   my @parts  = split( '/', $decoded->{name} );
   my $name   = pop @parts;
   my $path   = join( '/', @parts );
   $path = $root . $path if $root;

   my $cluster_id = $self->path2id( $user, $path );
   my $job        = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, name => $name } )->hash;
   return { success => 0, message => 'a job by that name already exists' } if $job->{id};

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
      server_id => $decoded->{server_id},
      name      => $name,
   };

   my $id;
   eval { $id = $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id; };
   my $fullpath = $self->id2path($id);
   return $id ? { success => 1, id => $id, path => $fullpath } : { success => 0 };
}

sub change_cluster {
   my ( $self, $user, $decoded ) = @_;
   my $cluster_id = $decoded->{id} || $self->path2id( $user, $decoded->{name} );

   if ($cluster_id) {
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )->hash;
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
      my $result = $self->sqlite->db->select( 'cluster', ['*'], { parent_id => $parent_id, name => $part } )->hash;
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

   eval {
      my $tx = $db->begin;

      # generate org bookmark
      my $bookmark = hmac_sha1_hex( $d->{name}, $self->app->secrets->[1] );

      my $org_id     = $d->{org_id} || $db->insert( 'org', { bookmark => $bookmark } )->last_insert_id;
      my $cluster_id = $db->insert( 'cluster', { org_id => $org_id } )->last_insert_id;

      # generate login token
      my $token = hmac_sha1_hex( $d->{name}, $self->app->secrets->[0] );
      $user_insert->{org_id}          = $org_id;
      $user_insert->{base_cluster_id} = $cluster_id;
      $user_insert->{token}           = $token;
      my $user_id = $db->insert( 'user', $user_insert )->last_insert_id;
      $db->update( 'org',     { user_id => $user_id, name => "org_$user_id" },     { id => $org_id } );
      $db->update( 'cluster', { user_id => $user_id, name => "cluster_$user_id" }, { id => $cluster_id } );
      $tx->commit;
   };

   return $@
     ? { message => $@, success => 0 }
     : { success => 1 };
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

sub _job_info {
   my ( $self, $user, $d ) = @_;
   my $user_info = $self->read_user($user);
   my ( $job_id, $cluster_id, $name, $path );

   if ( $d->{id} ) {
      $job_id = $d->{id};
   }
   elsif ( $d->{cluster_id} ) {
      $cluster_id = $d->{cluster_id};
      $path       = $self->id2path($cluster_id);
   }
   elsif ( $d->{name} ) {
      $cluster_id = $self->path2id( $user, $d->{name} );

      # cluster does not exist
      if ( defined $cluster_id && $cluster_id == 0 ) {
         my ($root) = $d->{name} =~ /^(\/)/;
         my @parts = split( '/', $d->{name} );
         $name       = pop @parts;
         $path       = join( '/', @parts );
         $path       = '/' . $path if $root && substr( $path, 0, 1 ) ne '/';
         $cluster_id = $self->path2id( $user, $path );
         my $info = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster_id, name => $name } )->hash;
         $job_id = $info && $info->{id} ? $info->{id} : undef;
         return { success => 0, cluster_id => $cluster_id, name => $name, message => 'job not found' } unless $job_id;
      }
   }
   else {
      $cluster_id = $user_info->{base_cluster_id};
   }

   # return value
   my $rval = {};

   unless ( defined $cluster_id && $cluster_id == 0 ) {
      my $sql = <<~"SQL";
      select j.*, c.org_id,
      s.name as server_name, js.state as jobstate
      from job j
      join cluster c on j.cluster_id = c.id
      left join server s on j.server_id = s.id
      left join job_states js on j.state_id = js.id
      where c.org_id = $user_info->{org_id} and 
   SQL

      $sql .=
          $job_id     ? " j.id = $job_id"
        : $cluster_id ? " j.cluster_id = $cluster_id"
        :               "j.cluster_id is null";         # root

      my @jobs;
      my $results = $self->sqlite->db->query($sql);
      while ( my $next = $results->hash ) {
         my %info =
           map { $_, $next->{$_} }
           (
            qw(signal cmndline fname exit_code last_update pid ppid priority pctmem pctcpu rss size id start started ended jobstate state state_id name mode cluster_id server_id server_name shell_command description out_log_path err_log_path)
           );
         push @jobs, \%info;
      }
      $rval->{jobs} = \@jobs;
   }

   $rval->{success}    = scalar @{ $rval->{jobs} };
   $rval->{id}         = $job_id;
   $rval->{cluster_id} = $cluster_id;
   $rval->{name}       = $name;
   $rval->{path}       = $path if $path;
   return $rval;
}

sub create_job {
   my ( $self, $user, $d ) = @_;

   my $ji = $self->_job_info( $user, $d );

   return { ji => $ji, success => 0, message => 'a job or cluster by that name already exists' } if $ji->{success};

   # undef = root cluster, 0 = cluster not found
   # jobs not allowed in root cluster

   if ( $ji->{cluster_id} && $ji->{name} ) {
      my $user_info   = $self->read_user($user);
      my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $ji->{cluster_id} } )->hash;
      my $is_writable = $self->is_writable( $user, $top );
      return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;
   }
   else {
      return { success => 0, message => 'cluster not found' };
   }
   my $insert_hash = { cluster_id => $ji->{cluster_id}, name => $ji->{name}, shell_command => $d->{shell_command} };
   if ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'], { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' } unless $res->{id};
      $insert_hash->{server_id} = $res->{id};
   }
   my $id;
   eval { $id = $self->sqlite->db->insert( 'job', $insert_hash )->last_insert_id; };
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $id, name => $ji->{name}, cluster_id => $ji->{cluster_id} };
}

sub read_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );
   return { success => 0, message => 'bad path name' } if ( $job_info->{name} && !$job_info->{id} );
   return { success => 0, message => 'no jobs found' } unless $job_info->{jobs} && scalar @{ $job_info->{jobs} };
   return { success => 1, %{$job_info} };
}

sub delete_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job_info->{id};
   eval { $self->sqlite->db->delete( 'job', { id => $job_info->{id} } ); };
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $job_info->{id} };
}

sub update_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );    #job info
   my $job      = shift @{ $job_info->{jobs} };
   return { success => 0, message => 'job not found' } unless $job->{id};

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw( signal ppid pid started ended exit_code server_id shell_command)) };
   if ( $d->{state} ) {
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
      if ( $d->{state} eq 'running' ) {
         $update_hash->{started} = time;
         $update_hash->{ended}   = undef;
      }
      elsif ( grep { $d->{state} eq $_ } (qw(failed killed complete)) ) {
         $update_hash->{ended} = time;
         $self->_reset_job( $user, { id => $job->{id} } );
      }
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
   my $uh     = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(total_memory used_memory cpu total_disk used_disk uptime)) };
   my $result = $self->sqlite->db->select( 'server', ['*'], { id => $d->{id} } )->hash;
   my $ssh    = $self->ssh_connection->{ $result->{id} };
   return { success => 0, exit => 1 } unless $result->{id} && $ssh && $ssh->check_master;
   $uh->{ping}        = $self->_ping( $result->{hostname} ) if $result->{hostname};
   $uh->{update_time} = time;
   my $running = $self->job_states->{running};

   # receive pid info
   if ( $d->{pids} && ref $d->{pids} eq 'ARRAY' ) {
      foreach my $pid ( @{ $d->{pids} } ) {
         my $update = { map { $_, $pid->{$_} } grep { exists $pid->{$_} } (qw(pctcpu pid time start size priority rss pctmem ppid state cmndline fname)) };
         eval { $self->sqlite->db->update( 'job', $update, { pid => $pid->{pid} } ) };
         die $@ if $@;
      }
   }

   # identify zombies
   if ( $d->{zombies} && ref $d->{zombies} eq 'ARRAY' ) {
      my $ids = $self->sqlite->db->select( 'job', [ 'id', 'state_id' ], { pid => $d->{zombies}, state_id => $running } );
      while ( my $next = $ids->hash ) {
         $self->update_job( $user, { state => 'zombie', ended => time }, { id => $next->{id} } );
      }
   }

   # send pid request
   my @pids;
   my $pids = $self->sqlite->db->select( 'job', ['pid'], { server_id => $d->{id}, pid => { '!=', undef }, state_id => $running } );
   while ( my $next = $pids->hash ) {
      push @pids, $next->{pid};
   }

   eval { $self->sqlite->db->update( 'server', $uh, { id => $d->{id} } ) };
   return $@ ? { success => 0, message => $@ } : { success => 1, pids => \@pids };
}

sub start_job {
   my ( $self, $user, $d ) = @_;

   # arrayref of jobs in $job_info->{jobs}
   my $job_info = $self->_job_info( $user, $d );    #job info
   my $job      = shift @{ $job_info->{jobs} };
   return { success => 0, message => 'command not found' } unless ref $job && $job->{id} && $job->{shell_command};
   return { success => 0, message => 'job not found' }     unless $job_info->{success} && $job_info->{id};
   return { success => 0, message => 'job is already running' } if $self->job_states->{running} == $job->{state_id};

   # returns arrayref of servers
   my $server_info = $self->_server_info( $user, { id => $job->{server_id} } );
   return { success => 0, message => 'server not found' } unless scalar @{$server_info} == 1;

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $job->{server_id} } );
      $ssh = $self->ssh_connection->{ $job->{server_id} };
   }

   my $token = $self->read_user($user)->{token};
   my $json  = encode_json( { token => $token, id => $job->{id}, shell => $job->{shell_command} } );
   my $cmd   = "perl cc_worker/script/launcher.pl '$json'";

   $ssh->system($cmd);

   #$ssh->system({ async => 1 }, $cmd);
   if ( $ssh->error ) {
      return { success => 0, message => $ssh->error };
   }
   else {
      #$self->update_job( $user, { state => 'starting', started => time, ended => undef }, { id => $job->{id} } );
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
   my $job_info = $self->_job_info( $user, $d );    #job info
   my $job      = shift @{ $job_info->{jobs} };
   return { success => 0, message => 'job not found' }      unless ref $job && $job->{id};
   return { success => 0, message => 'job is not running' } unless $job->{state_id} == $self->job_states->{running};

   my $pid = $job->{pid};

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;

   $ssh->system("perl -e 'kill TERM, $job->{pid}'");
   return $ssh->error ? { success => 0, message => $ssh->error } : { success => 1 };
}

sub hold_job {
   my ( $self, $user, $d ) = @_;
}

sub ice_job {
   my ( $self, $user, $d ) = @_;
}

sub nice_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );    #job info
   my $job      = shift @{ $job_info->{jobs} };
   my $pid      = $job->{pid};
   return { success => 0, message => 'job not found' } unless ref $job && $job->{id};

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;

   $ssh->system("perl -e 'setpriority(0, $job->{pid}, $d->{level}) or die'");

   #$ssh->system("renice -n $d->{level} -p $job->{pid}");
   return $ssh->error ? { success => 0, message => $ssh->error } : { success => 1 };
}

sub _reset_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );    #job info
   my $job      = shift @{ $job_info->{jobs} };
   return { success => 0, message => 'job not found' } unless ref $job && $job->{id};
   my %update = map { $_ => undef } (qw(signal ppid pid exit_code pctcpu time start size priority rss pctmem state cmndline fname));
   eval { $self->sqlite->db->update( 'job', \%update, { id => $job->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

# server related subroutines

sub ssh_copy {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless scalar @{$servers};
   foreach my $s (@$servers) {
      $s->{password} = $d->{password} if $d->{password};
      next unless $s->{password} && $s->{username} && $s->{hostname};
      $self->_ssh_copy($user, $s);
   }
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
   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless scalar @{$servers};
   foreach my $s (@$servers) {

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
      return { success => 0, message => $@ } if $@;
   }
   return { success => 1 };
}

sub create_monitor {
   my ( $self, $user, $d ) = @_;

   $self->_ssh_copy($user, $d) if $d->{password};

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
      return { id => $id, success => 1, message => 'connected' };
   }
}

sub read_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->_server_info( $user, $d );
   return scalar @$servers ? { success => 1, servers => $servers } : { success => 0 };
}

sub _server_info {
   my ( $self, $user, $d ) = @_;
   my $select =
       $d->{id}   ? { id => $d->{id}, org_id => $user->org_id }
     : $d->{name} ? { org_id => $user->org_id, name => $d->{name} }
     :              { org_id => $user->org_id };

   my @rows;
   my $results = $self->sqlite->db->select( 'server', ['*'], $select );
   while ( my $next = $results->hash ) {
      my $ssh       = $self->ssh_connection->{ $next->{id} };
      my $connected = $ssh && $ssh->check_master ? 1 : 0;
      my $row       = { map { $_, $next->{$_} } (qw(id active os cwd home cores update_time ping username hostname name port total_memory used_memory cpu total_disk used_disk uptime)) };
      $row->{connected} = $connected;
      push @rows, $row;
   }
   return \@rows;
}

sub _disconnect_ssh {
   my ( $self, $user, $d ) = @_;

   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless scalar @{$servers};
   foreach my $s (@$servers) {

      eval { $self->sqlite->db->update( 'server', { active => 0 }, { id => $s->{id} } ) };
      return { success => 0, message => "unable to update server id $s->{id}: $@" } if $@;

      my $ssh = $self->ssh_connection->{ $s->{id} };
      if ($ssh) {
         $ssh->system( { async => 1, stdout_discard => 1, stderr_discard => 1 }, "perl cc_worker/script/sysinfo.pl stop" );
         $ssh->disconnect(0);
      }
   }
   return { success => 1 };
}

# refresh ssh connection
sub _connect_ssh {
   my ( $self, $user, $d ) = @_;
   my $token   = $self->read_user( $user )->{token};
   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless scalar @{$servers};
   foreach my $s (@$servers) {
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
   }

   return { success => 1 };
}

sub _start_monitor {
   my ( $self, $user, $d ) = @_;
   my $token   = $self->read_user( $user )->{token};
   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless scalar @{$servers};
   foreach my $s (@$servers) {
      my $ssh = $self->ssh_connection->{ $s->{id} };
      $self->_connect_ssh( $user, { id => $d->{id} } ) unless ( $ssh && $ssh->check_master );
      $ssh = $self->ssh_connection->{ $s->{id} };
      my $json = encode_json( { token => $token, id => $s->{id} } );
      $ssh->system( { stdout_discard => 1, stderr_discard => 1 }, "perl cc_worker/script/sysinfo.pl stop" );
      $ssh->system( { stdout_discard => 1, stderr_discard => 1 }, "perl cc_worker/script/sysinfo.pl start '$json'" );
   }
   return { success => 1, message => 'monitor started' };
}

# refresh ssh session and start sysinfo
sub start_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'no servers found' } unless scalar @{$servers};
   foreach my $s (@$servers) {
      eval { $self->sqlite->db->update( 'server', { active => 1 }, { id => $s->{id} } ) };
      return { success => 0, message => "unable to update server id $s->{id}" } if $@;
      $self->_start_monitor( $user, { id => $s->{id} } );
   }
   return { success => 1 };
}

# disconnect ssh session
sub stop_monitor {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_disconnect_ssh( $user, $d );
   return $rv;
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
   my $servers = $self->_server_info( $user, $d );
   return { success => 0, message => 'multiple servers found' } if scalar @$servers > 1;

   my $id = $servers->[0]->{id};

   my $rows    = $self->sqlite->db->delete( 'server', { id => $id } )->rows;
   my $success = $rows ? 1 : 0;
   $self->_disconnect_ssh( $user, { id => $id } );
   delete $self->ssh_connection->{$id};
   return { success => $success };
}

sub addcron {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
   my $set  = DateTime::Event::Cron->from_cron( cron => $decoded->{crontab}, after => DateTime->now );
   my $db   = $self->app->sqlite->db;
   $db->update( 'container', { crontab => $decoded->{crontab} }, { id => $decoded->{crontainer_id} } );

   my $w = EV::periodic_ns(
      0, 0,
      sub {
         my ( $w, $now ) = @_;
         my $set  = DateTime::Event::Cron->new( $decoded->{crontab} );
         my $iter = $set->iterator( after => DateTime->from_epoch( epoch => $now ) );
         return $iter->next( DateTime->from_epoch( epoch => $now ) )->epoch;

         #return $iter->next(DateTime->from_epoch(epoch => $now, time_zone => $local_TZ))->epoch;
      },
      sub {
         # start container if status = A
         my ( $w, $now ) = @_;
         my $status = $db->select( 'container', ['status'], { id => $decoded->{crontainer_id} } )->hash->{id};
         if ( $status eq 'A' ) {

            #$w->start;
            $self->start_container( container_id => $decoded->{crontainer_id} );
         }

         # start timer if container status = A
         # $w->start;
      }
   );
   $self->app->timers->{ $decoded->{container_id} } = $w;
   $user->tx->send( encode_json( { response => 'crontab installed', crontab => $decoded->{crontab} } ) );
}

# command routing

sub routing {
   state $i  = qr/^\d{1,20}$/;                        # integer
   state $w  = qr/^\w{1,50}$/;                        # word
   state $f  = qr/^[\d\.]{1,20}$/;                    # float
   state $p  = qr/^[\w\/\@\:\.]{1,50}$/;              # path
   state $e  = qr/^[\w\.\@]{1,50}$/;                  # email
   state $c  = qr/^[\w\/\@\:\.\s\-\(\)\"]{1,50}$/;    # shell command
   state $pw = qr/^.{8,20}$/;                         # password

   state %routing = (

      # user related
      'create_user' => [ \&create_user, 3, [ { name => $w }, { org_id => $i, email => $w, level => $i } ] ],
      'read_user'   => [ \&read_user,   1, [ {},             {} ] ],
      'update_user' => [ \&update_user, 1, [ {},             { email => $e, name => $w, newname => $w, id => $i } ] ],
      'delete_user' => [ \&delete_user, 3, [ { id => $i }, {} ] ],
      'login_user'  => [ \&login_user,  0, [ { token => $w }, {} ] ],

      # job related
      'create_job' => [ \&create_job, 1, [ { name => $p, shell_command => $c }, { server => $w, description => $w, out_log_path => $w, err_log_path => $w } ] ],
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
               ended         => $i
            }
         ]
      ],
      'delete_job' => [ \&delete_job, 1, [ {},              { name => $p, id => $i } ] ],
      'start_job'  => [ \&start_job,  1, [ {},              { name => $p, id => $i } ] ],
      'kill_job'   => [ \&kill_job,   1, [ {},              { name => $p, id => $i } ] ],
      'nice_job'   => [ \&nice_job,   1, [ { level => $i }, { name => $p, id => $i } ] ],
      'hold_job'   => [ \&hold_job,   1, [ {},              { name => $p, id => $i } ] ],
      'ice_job'    => [ \&ice_job,    1, [ {},              { name => $p, id => $i } ] ],
      'finish_job' => [ \&finish_job, 1, [ {},              { name => $p, id => $i } ] ],
      'copy_job'   => [ \&copy_job,   1, [ {},              { name => $p, id => $i, to => $p } ] ],

      # cluster related
      'create_cluster' => [ \&create_cluster, 1, [ { name => $p }, { description => $w } ] ],
      'read_cluster'   => [ \&read_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'update_cluster' => [ \&update_cluster, 1, [ {}, { id   => $i, name => $p, newname => $w, description => $w } ] ],
      'delete_cluster' => [ \&delete_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'change_cluster' => [ \&change_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'find_cluster'   => [ \&find_cluster,   1, [ {}, { name => $p, id   => $i } ] ],

      #'start_cluster'  => [ \&start_cluster,  1, [ {}, {} ] ],
      #'copy_cluster'   => [ \&copy_cluster,   1, [ {}, { name => $p, id => $i, to => $p } ] ],

      # monitor related
      'create_monitor'  => [ \&create_monitor, 1, [ { name => $w, username => $w, hostname => $p }, { password => $pw } ] ],
      'read_monitor'    => [ \&read_monitor,   1, [ {},                                                              { id => $i, name => $w } ] ],
      'update_monitor'  => [ \&update_monitor, 1, [ {}, { id => $i, name => $w, newname => $w, username => $w, hostname => $p } ] ],
      'delete_monitor'  => [ \&delete_monitor, 1, [ {},                                                              { id => $i, name => $w } ] ],
      'start_monitor'  => [ \&start_monitor, 1, [ {},                                                              { id => $i, name => $w } ] ],
      'ssh_copy'       => [ \&ssh_copy,     1, [ { name => $w, username => $w, hostname => $p }, { password => $pw } ] ],
      'stop_monitor'   => [ \&stop_monitor,  1, [ {},                                                              { id => $i, name => $w } ] ],
      'upgrade_monitor'  => [ \&upgrade_monitor, 1, [ {}, { id => $i, name => $w } ] ],
      'update_sysinfo' => [
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
1;
