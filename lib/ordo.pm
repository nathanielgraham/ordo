package ordo;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use ordo::Model::User;
use ordo::Model::UserHelper;
use ordo::Model::JobHelper;
use ordo::Model::BoxHelper;
use JSON;
use Digest::SHA qw(hmac_sha1_hex);
use FindBin     qw($Bin);
use Net::SSH::Perl;
use Net::OpenSSH;
use Sys::Hostname;
use Data::Dumper;

has 'user' => sub {
   state $user = {};
};

# This method will run once at server start
sub startup {

   my $self = shift;

   # Configure the application
   $self->secrets( [ 'gu$!$#UessM%#eI36#$fYo43@#$uC^%5an', '%!#GDA$#!gfds%#@sdf' ] );

   # Helpers
   $self->helper( request     => \&request );
   $self->helper( routing     => \&routing );
   $self->helper( sqlite      => sub { state $sql  = Mojo::SQLite->new("$Bin/../db/ordo.db") } );
   $self->helper( user_helper => sub { state $user = ordo::Model::UserHelper->new( sqlite => shift->sqlite ) } );
   $self->helper( job_helper  => sub { state $job  = ordo::Model::JobHelper->new( app => shift->app ) } );
   $self->helper( box_helper  => sub { state $box  = ordo::Model::BoxHelper->new( app => shift->app ) } );

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

   $r->get(
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
            unless ( $params->{$param} =~ $regex ) {
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
   my $clusters = $self->read_cluster( $user, { id => $cluster_id } )->{clusters};
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
      hostname        => hostname,
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
      }
   }

   # return value
   my $rval = {};

   unless ( defined $cluster_id && $cluster_id == 0 ) {
      my $sql = <<~"SQL";
      select j.*,  
      s.name as server_name, js.state
      from job j
      left join server s on j.server_id = s.id
      left join job_states js on j.state_id = js.id
      where
   SQL

      $sql .=
          $job_id     ? " j.id = $job_id"
        : $cluster_id ? " j.cluster_id = $cluster_id"
        :               "j.cluster_id is null";         # root

      my @jobs;
      my $results = $self->sqlite->db->query($sql);
      while ( my $next = $results->hash ) {
         my %info = map { $_, $next->{$_} } (qw(id start end pid mem cpu state name mode cluster_id server_id server_name shell_command description out_log_path err_log_path));
         push @jobs, \%info;
      }
      $rval->{jobs} = \@jobs;
   }

   $rval->{id}         = $job_id;
   $rval->{cluster_id} = $cluster_id;
   $rval->{name}       = $name;
   $rval->{path}       = $path if $path;
   return $rval;
}

sub create_job {
   my ( $self, $user, $d ) = @_;

   my $ji = $self->_job_info( $user, $d );

   return { success => 0, message => 'a job by that name already exists' } if $ji->{id};
   return { success => 0, message => 'a cluster by that name already exists' } unless $ji->{name};

   # undef = root cluster, 0 = cluster not found
   # jobs not allowed in root cluster

   my $user_info   = $self->read_user($user);
   my $top         = $self->sqlite->db->select( 'cluster', ['*'], { id => $ji->{cluster_id} } )->hash;
   my $is_writable = $self->is_writable( $user, $top );
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $is_writable;

   my $insert_hash = { cluster_id => $ji->{cluster_id}, name => $ji->{name}, shell_command => $d->{shell_command} };
   my $id;
   eval { $id = $self->sqlite->db->insert( 'job', $insert_hash )->last_insert_id; };
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $id, name => $ji->{name}, cluster_id => $ji->{cluster_id} };
}

sub job_info {
   my ( $self, $param ) = @_;
   my $cluster_id = $param->{cluster_id};
   my $job_id     = $param->{job_id};

   my $sql = <<~"SQL";
      select j.*,  
      s.name as server_name, js.state
      from job j
      left join server s on j.server_id = s.id
      left join job_states js on j.state_id = js.id
      where
   SQL

   $sql .=
       $job_id     ? " j.id = $job_id"
     : $cluster_id ? " j.cluster_id = $cluster_id"
     :               "j.cluster_id is null";         # root

   my @jobs;
   my $results = $self->sqlite->db->query($sql);
   while ( my $next = $results->hash ) {

      # say $next->{name};
      my %info = map { $_, $next->{$_} } (qw(id start end state name mode cluster_id server_id server_name shell_command description out_log_path err_log_path));
      push @jobs, \%info;
   }
   return \@jobs;
}

sub read_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );
   return { success => 1, %{$job_info} };
}

sub update_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job_info->{id};

   my $update_hash = { map { $_, $d->{$_} } grep { defined $d->{$_} } (qw( pid server_id state_id shell_command )) };
   $update_hash->{name} = $d->{newname} if $d->{newname};
   eval { $self->sqlite->db->update( 'job', $update_hash, { id => $job_info->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { success => $success, id => $job_info->{id}, %{$update_hash} };
}

sub delete_job {
   my ( $self, $user, $d ) = @_;
   my $job_info = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job_info->{id};
   eval { $self->sqlite->db->delete( 'job', { id => $job_info->{id} } ); };
   return $@ ? { success => 0, message => $@ } : { success => 1, id => $job_info->{id} }
}

sub start_job {
   my ( $self, $user, $d ) = @_;
   return {};
}

sub finish_job {
   my ( $self, $user, $d ) = @_;
   return {};
}

sub kill_job {
   my ( $self, $user, $d ) = @_;
   return {};
}

sub hold_job {
   my ( $self, $user, $d ) = @_;
   return {};
}

sub ice_job {
   my ( $self, $user, $d ) = @_;
   return {};
}

sub nice_job {
   my ( $self, $user, $d ) = @_;
   return {};
}

# server related subroutines

sub create_server {
   my ( $self, $user, $d ) = @_;

   my $port = $d->{port} || 22;

   # test connection
   my $ssh = Net::OpenSSH->new( $d->{hostname}, port => $port );
   return { success => 0, message => $ssh->error } if $ssh->error;

   # copy public ssh key to remote host
   my $copy_key  = 'sshpass -p ' . $d->{password} . ' ssh-copy-id ' . $d->{username} . '@' . $d->{hostname};
   my $exit_code = system($copy_key);
   return { success => 0, exit_code => $exit_code, message => 'ssh-copy-id error' } if $exit_code;

   my $insert_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(name username hostname password port)) };
   $insert_hash->{port}   = $port;
   $insert_hash->{org_id} = $user->org_id;

   my $id;
   eval { $id = $self->app->sqlite->db->insert( 'server', $insert_hash )->last_insert_id; };
   return $@ ? { success => 0, message => $@ } : { id => $id, success => 1, %$insert_hash };
}

sub read_server {
   my ( $self, $user, $d ) = @_;
   my $id =
       $d->{id}                            ? $d->{id}
     : $d->{name} && $d->{name} =~ /^\d+$/ ? $d->{name}
     :                                       undef;

   my @rows;
   if ($id) {
      my $r = $self->sqlite->db->select( 'server', [qw(id username hostname name port)], { id => $id } )->hash;
      push @rows, $r if $r;
   }
   elsif ( $d->{name} ) {
      my $r = $self->sqlite->db->select( 'server', [qw(id username hostname name port)], { name => $d->{name} } )->hash;
      push @rows, $r if $r;
   }
   else {
      my $results = $self->sqlite->db->query('select id, username, hostname, name, port from server');
      while ( my $next = $results->hash ) {
         push @rows, { map { $_, $next->{$_} } (qw(id username hostname name port)) };
      }
   }
   return scalar @rows ? { success => 1, servers => \@rows } : { success => 0 };
}

sub update_server {
   my ( $self, $user, $d ) = @_;
   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(username hostname)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   return { success => 0, message => 'nothing to update' } unless scalar keys(%$update_hash);

   my $id =
       $d->{id}                            ? $d->{id}
     : $d->{name} && $d->{name} =~ /^\d+$/ ? $d->{name}
     :                                       undef;

   if ($id) {
      eval { $self->sqlite->db->update( 'server', $update_hash, { id => $id } ); };
   }
   elsif ( $d->{name} ) {
      eval { $self->sqlite->db->update( 'server', $update_hash, { name => $d->{name} } ); };
   }
   else {
      return { success => 0, message => 'server id or name required' };
   }

   return { success => 0, message => $@ } if $@;
   return { success => 1, %$update_hash };
}

sub delete_server {
   my ( $self, $user, $d ) = @_;
   my $id =
       $d->{id}                                ? $d->{id}
     : ( $d->{name} && $d->{name} =~ /^\d+$/ ) ? $d->{name}
     :                                           undef;

   if ($id) {
      eval { $self->sqlite->db->delete( 'server', { id => $id } ); };
   }
   elsif ( $d->{name} ) {
      eval { $self->sqlite->db->delete( 'server', { name => $d->{name} } ); };
   }
   else {
      return { success => 0, message => 'server id or name required' };
   }

   my $return_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(id name)) };
   return { success => 0, message => $@ } if $@;
   return { success => 1, %$return_hash };
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

sub start_continer {
   my ( $self, $connection_id, $decoded ) = @_;
   my $db = $self->app->sqlite->db;
   $db->update( 'container', { status => 'R' }, { id => $decoded->{crontainer_id} } );

   # start all jobs in container
}

# command routing

sub routing {
   state $i = qr/^\d{1,20}$/;                # integer
   state $w = qr/^\w{1,50}$/;                # word
   state $p = qr/^[\w\/\@\:\.]{1,50}$/;      # path
   state $e = qr/^[\w\.\@]{1,50}$/;          # email
   state $c = qr/^[\w\/\@\:\.\s]{1,50}$/;    # shell command

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
      'update_job' => [ \&update_job, 1, [ {}, { name => $p, id => $i, newname    => $w, server_id => $i, pid => $i, state_id => $i, shell_command => $p } ] ],
      'delete_job' => [ \&delete_job, 1, [ {}, { name => $p, id => $i } ] ],
      'start_job'   => [ \&start_job, 1, [ {}, { name => $p, id => $i } ] ],
      'kill_job'   => [ \&kill_job,   1, [ {}, { name => $p, id => $i } ] ],
      'hold_job'   => [ \&hold_job,   1, [ {}, { name => $p, id => $i } ] ],
      'ice_job'    => [ \&ice_job,    1, [ {}, { name => $p, id => $i } ] ],
      'finish_job' => [ \&finish_job, 1, [ {}, { name => $p, id => $i } ] ],
      'copy_job'   => [ \&copy_job,   1, [ {}, { name => $p, id => $i, to => $p } ] ],

      # cluster related
      'create_cluster' => [ \&create_cluster, 1, [ { name => $p }, { description => $w } ] ],
      'read_cluster'   => [ \&read_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'update_cluster' => [ \&update_cluster, 1, [ {}, { id   => $i, name => $p, newname => $w, description => $w } ] ],
      'delete_cluster' => [ \&delete_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      'change_cluster' => [ \&change_cluster, 1, [ {}, { name => $p, id   => $i } ] ],
      #'start_cluster'  => [ \&start_cluster,  1, [ {}, {} ] ],
      #'copy_cluster'   => [ \&copy_cluster,   1, [ {}, { name => $p, id => $i, to => $p } ] ],

      # server related
      'create_server' => [ \&create_server, 1, [ { name => $w, username => $w, hostname => $w, password => $w }, {} ] ],
      'read_server'   => [ \&read_server,   1, [ {}, { id => $i, name => $w } ] ],
      'update_server' => [ \&update_server, 1, [ {}, { id => $i, name => $w, newname => $w, username => $w, hostname => $w } ] ],
      'delete_server' => [ \&delete_server, 1, [ {}, { id => $i, name => $w } ] ],
   );
   return \%routing;
}

1;
