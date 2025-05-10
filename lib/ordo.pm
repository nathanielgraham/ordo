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
   $r->get('/')->to( controller => 'landing', action => 'welcome' );
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
         $response->{nessage} = 'Level too low.';
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

sub read_cluster {
   my ( $self, $user, $decoded ) = @_;
   my $cluster_id    = $self->path2id( $user, $decoded->{name} );
   my $find_clusters = sub {
      my $id       = shift;
      my $clusters = $self->sqlite->db->select( 'cluster', ['*'], { parent_id => $id } );
      while ( my $c = $clusters->hash ) {
         say "CLUSTER: $c->{id} $c->{name} PARENT: $id";
         my $jobs = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $c->{id} } );
         while ( my $j = $jobs->hash ) {
            say "   JOB: $j->{id} $j->{name}";
         }
         __SUB__->( $c->{id} );
      }
      return;
   };

   $find_clusters->($cluster_id);
   return { success => 1 };
}

sub update_cluster {
   my ( $self, $user, $decoded ) = @_;
   my $cluster_id = $decoded->{name} =~ /^\d+$/ ? $decoded->{name} : $self->path2id( $user, $decoded->{name} );
   eval { $self->sqlite->db->update( 'cluster', {$decoded}, { id => $cluster_id } ); };
   my $fullpath = $self->id2path($cluster_id);
   my $success  = $@ ? 0 : 1;
   return { success => $success, id => $cluster_id, path => $fullpath };
}

sub delete_cluster {
   my ( $self, $user, $decoded ) = @_;
   my $cluster_id = $self->path2id( $user, $decoded->{name} );

   #my $cluster_id = $decoded->{name} =~ /^\d+$/ ? $decoded->{name} : $self->path2id($user, $decoded->{name});
   eval { $self->sqlite->db->delete( 'cluster', { id => $cluster_id } ); };
   my $fullpath = $self->id2path($cluster_id);
   my $success  = $@ ? 0 : 1;
   return { success => $success, id => $cluster_id, path => $fullpath };
}

sub create_cluster {
   my ( $self, $user, $decoded ) = @_;

   my ($name)     = $decoded->{name} =~ /\/(\w+)$/;
   my $cluster_id = $self->path2id( $user, $decoded->{name} );
   my $user_info  = $self->user_helper->info($user);

   my $insert_hash = {
      org_id    => $user_info->{org_id},
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
   my $cluster_id = $self->path2id( $user, $decoded->{name} );
   my $fullpath   = $self->id2path($cluster_id);
   my $user_info  = $self->user_helper->info($user);
   print "CLID: $cluster_id\n";
   print Dumper($user_info);
   eval { $self->sqlite->db->update( 'user', { base_cluster_id => $cluster_id }, { id => $user_info->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { path => $fullpath, cluster_id => $cluster_id, success => $success };
}

sub path2id {
   my ( $self, $user, $path ) = @_;
   my $user_info       = $self->app->user_helper->info($user);
   my $base_cluster_id = $user_info->{base_cluster_id};
   my $base_path       = $self->id2path($base_cluster_id);
   my $fullpath =
       ( $path && substr( $path, 0, 1 ) eq '/' ) ? $path
     : $path && $base_path                       ? "/$base_path/$path"
     : $path                                     ? "/$path"
     : $base_path                                ? "/$base_path"
     :                                             '/';

   my @parts     = split( '/', $fullpath );
   my $parent_id = undef;

   foreach my $part (@parts) {
      my $result = $self->sqlite->db->select( 'cluster', ['*'], { parent_id => $parent_id, name => $part } )->hash;
      $parent_id = $result->{id};
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
   my ( $self, $user, $decoded ) = @_;
   return $self->app->user_helper->login( $user, $decoded );
}

sub create_user {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->user_helper->add( $user, $decoded );
}

sub read_user {
   my ( $self, $user, $decoded ) = @_;
   my $r    = $self->app->user_helper->info( $user, $decoded );
   my $path = $self->id2path( $r->{base_cluster_id} );
   $r->{path}    = $path;
   $r->{success} = 1;
   return $r;
}

sub update_user {
   my ( $self, $user, $decoded ) = @_;
}

sub delete_user {
   my ( $self, $user, $decoded ) = @_;
}

# job related subroutines

sub create_job {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->job_helper->add( $user, $decoded );
}

sub read_job {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->job_helper->add( $user, $decoded );
}

sub update_job {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->job_helper->add( $user, $decoded );
}

sub delete_job {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->job_helper->add( $user, $decoded );
}

sub start_job {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->job_helper->start( $user, $decoded );
}

sub finish_job {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->job_helper->finish( $user, $decoded );
}

sub kill_job {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub hold_job {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub ice_job {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub nice_job {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

# server related subroutines

sub create_server {
   my ( $self, $user, $decoded ) = @_;
   my @missing = grep { !$decoded->{$_} } qw(username hostname);
   return { success => 0, message => "missing parameters: @missing" } unless $decoded->{username} && $decoded->{hostname};
   my $response = $self->test_server( $user, $decoded );
   if ( $response->{success} ) {
      my $insert_hash = { map { $_ => $decoded->{$_} } grep { $decoded->{$_} } qw(username hostname password) };
      my $id          = $self->app->sqlite->db->insert( 'server', $insert_hash )->last_insert_id;
      $response->{id} = $id;
   }
   return $response;
}

sub test_server {
   my ( $self, $user, $decoded ) = @_;
   my @missing = grep { !$decoded->{$_} } qw(username hostname);
   return { success => 0, message => "missing parameters: @missing" } unless $decoded->{username} && $decoded->{hostname};
   eval {
      my @login_details = ( $decoded->{username} );
      push( @login_details, $decoded->{password} ) if $decoded->{password};
      my $ssh = Net::SSH::Perl->new( $decoded->{hostname} );
      $ssh->login(@login_details);
      $ssh->sock;
   };
   my $message = $@ ? 'refused' : 'established';
   my $success = $@ ? 0         : 1;
   return { success => $success, message => "connection $message" };
}

sub delete_server {
   my ( $self, $user, $decoded ) = @_;
   my $success;
   if ( $decoded->{id} ) {
      $self->app->sqlite->db->delete( 'server', { id => $decoded->{id} } );
      $success = 1;
   }
   else {
      $success = 0;
   }
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

sub start_continer {
   my ( $self, $connection_id, $decoded ) = @_;
   my $db = $self->app->sqlite->db;
   $db->update( 'container', { status => 'R' }, { id => $decoded->{crontainer_id} } );

   # start all jobs in container
}

# command routing

sub routing {
   state $i = qr/^\d{1,20}$/;        # integer
   state $w = qr/^\w{1,50}$/;        # word
   state $p = qr/^[\w\/]{1,50}$/;    # path
   state $e = qr/^[\w\.\@]{1,50}$/;  # email

   state %routing = (

      # CRUD operations

      # user related
      'create_user' => [ \&create_user, 3, [ { username => $w }, { org_id => $i, password => $w, email => $w, level => $i } ] ],
      'read_user'   => [ \&read_user,   1, [ {},                 {} ] ],
      'update_user' => [ \&update_user, 1, [ {},                 { email => $e, username => $w } ] ],
      'delete_user' => [ \&delete_user, 3, [ { id => $i }, {} ],
      'login_user'  => [ \&login_user, 0, [ { token => $w }, { } ] ],

      # job related
      'create_job' => [ \&create_job, 1, [ { cluster_id => $i, name => $w, shell_command => $i }, { description => $w, out_log_path => $w, err_log_path => $w } ] ],
      'read_job'   => [ \&read_job,   1 ],
      'update_job' => [ \&update_job, 1, [ { job_id => $i }, { cluster_id => $i, server_id => $i, pid => $i, state_id => $i, remote_command => $w } ] ],
      'delete_job' => [ \&delete_job, 1 ],
      'copy_job'   => [ \&copy_job,   1 ],
      'kill_job'   => [ \&kill_job,   1 ],
      'hold_job'   => [ \&kill_job,   1 ],
      'ice_job'    => [ \&ice_job,    1 ],
      'finish_job' => [ \&finish_job, 1 ],
      'copy_job'   => [ \&copy_job,   1 ],

      # cluster related
      'create_cluster' => [ \&create_cluster, 1, [ { name => $w }, { description => $w, cluster_id => $i } ] ],
      'read_cluster'   => [ \&read_cluster,   1, [ {},             { name        => $p } ] ],
      'update_cluster' => [ \&update_cluster, 1 ],
      'delete_cluster' => [ \&delete_cluster, 1 ],
      'use_cluster'    => [ \&change_cluster, 1, [ {}, { name => $p } ] ],
      'start_cluster'  => [ \&start_cluster,  1 ],
      'copy_cluster'   => [ \&copy_cluster,   1 ],

      # server related
      'create_server' => [ \&create_server, 1, [ { username => $w, hostname => $w }, { password => $w } ] ],
      'read_server'   => [ \&read_server,   1 ],
      'update_server' => [ \&update_server, 1 ],
      'delete_server' => [ \&delete_server, 1 ],
      'test_server'   => [ \&test_server,   1 ],
   );
   return \%routing;
}

1;
