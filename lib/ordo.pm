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
use Data::Dumper;

has 'user' => sub {
   state $user = {};
};

# This method will run once at server start
sub startup {

   my $self = shift;

   # Configure the application
   $self->secrets( ['gu$!$#UessM%#eI36#$fYo43@#$uC^%5an', '%!#GDA$#!gfds%#@sdf'] );

   # Helpers
   $self->helper( request     => \&request );
   $self->helper( routing     => \&routing );
   $self->helper( sqlite      => sub { state $sql    = Mojo::SQLite->new("$Bin/../db/ordo.db") } );
   $self->helper( user_helper => sub { state $user   = ordo::Model::UserHelper->new( sqlite => shift->sqlite ) } );
   $self->helper( job_helper  => sub { state $job    = ordo::Model::JobHelper->new( app => shift->app ) } );
   $self->helper( box_helper  => sub { state $box    = ordo::Model::BoxHelper->new( app => shift->app ) } );

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

   for my $k (keys %{ $self->routing }) {
      $r->get("/$k" => sub {
         my $c = shift;
         my $body = $c->req->json;
         if (ref $body ne 'HASH' || !$body->{token}) {
            $c->render(json => { error => 'missing login token' }, status => 400);
         }
         else {
            my $user = ordo::Model::User->new();
            my $auth = $self->request($user, { token => $body->{token}, command => 'login' });
            if ($auth->{success}) {
               my $result = $self->request($user, $body);
               $c->render(json => $result);
            }
            else {
               $c->render(json => { error => 'invalid login token' }, status => 401);
            }
         }
      });
   }
}

sub request {
   my ( $self, $user, $decoded ) = @_;
   #my ( $self, $connection_id, $decoded ) = @_;

   my $response = {};
   #my $user     = $self->app->user->{$connection_id};

   state $i = qr/^\d{1,20}$/;    # is integer
   state $w = qr/^\w{1,60}$/;    # is word

   die                unless ref $decoded eq 'HASH';

   my ($command, $params) = (delete $decoded->{command}, $decoded);
   if ( exists $self->routing->{ $command } ) {
      my $level = $user->level || 0;
      my ($sub, $min_level, $legal_options) = @{ $self->routing->{ $command } };
      #my ($sub, $min_level, $legal_options) = @{ $routing{ $command } };
      my ($required, $optional) =  @{ $legal_options };
      $optional->{request_id} = $i; # request_id added by client to every request
      $optional->{token} = $w; # token added for rest api
      my @unknown = grep { !exists $required->{$_} && !exists $optional->{$_} } keys %$params;
      my @missing = grep { !exists $params->{$_} } keys %$required;

      if ($user->level < $min_level) {
         $response->{error} = 'level too low';
      }
      elsif (scalar @unknown ) {
         $response->{error} = "unknown parameters: @unknown";
      }
      elsif (scalar @missing ) {
         $response->{error} = "missing parameters: @missing";
      }
      else {
         my $error = 0;
         my $bad_option;
         for my $param ( keys %$params ) {
            my $regex = $required->{$param} || $optional->{$param};

            # check that param matches regex
            unless ($params->{$param} =~ $regex) {
               $error = 1;
               $bad_option = $param;
               last;
            }
         }
         $response = $error ? { error => "invalid option: $bad_option" }
                   : &$sub( $self, $user, { %$params } );
      }
   }
   else {
      $response = { error => 'no such command' };
   }

   $response->{command_reply} = $command;
   $response->{request_id}    = $params->{request_id} if $params->{request_id};
   return $response;
}

#users

sub login {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->user_helper->login( $user, $decoded );
}

sub create_user {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->user_helper->add( $user, $decoded );
}

sub read_user {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->user_helper->info( $user, $decoded );
}

#jobs

sub add_job {
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

#boxes

sub add_box {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->box_helper->add( $user, $decoded );
}

sub start_box {
   my ( $self, $user, $decoded ) = @_;
   return $self->app->box_helper->start( $user, $decoded );
}

#servers

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

sub addcontainer {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
   my $db   = $self->app->sqlite->db;
   unless ( $user->level ) {
      $user->tx->send( encode_json( { response => 'insufficient access' } ) );
      return;
   }

   # container name required
   my $insert_hash = { map { $_ => $decoded->{$_} } grep { exists $decoded->{$_} } qw(crontab name description start) };
   $insert_hash->{user_id} = $user->id;
   my $id = $db->insert( 'container', $insert_hash )->last_insert_id;

   $user->tx->send( encode_json( { response => 'container added' } ) ) if $id;
   if ( $insert_hash->{crontab} ) {
      $self->addcron( $connection_id, { crontab => $insert_hash->{crontab}, container_id => $id } );
   }

   #$self->app->container->add( $params );
   #$user->tx->send( encode_json( { response => 'container added' }));

   #my $results     = $db->select( 'user', ['*'], { username => $decoded->{username} } )->hash;
   #$deconded->{crontab}
   #$crontab = '*/3 15 1-10 3,4,5 */2';
   #$set = DateTime::Event::Cron->from_cron($crontab);
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

sub deltimer {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub addjob {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub deljob {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

#sub addcontainer {
#   my ( $self, $connection_id, $decoded ) = @_;
#   my $user = $self->app->user->{$connection_id};
#}

sub delcontainer {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub startjob {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub killjob {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub holdjob {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub icejob {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
}

sub foop {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->user->{$connection_id};
   my $r    = $self->app->foo->baz;
   $user->tx->send( encode_json($r) );
}

sub routing {
   state $i = qr/^\d{1,20}$/;    # integer
   state $w = qr/^\w{1,60}$/;    # word

   state %routing = (

      # CRUD operations

      #create
      'create_user'      => [ \&create_user,      3, [ { username => $w }, { org_id => $i, password => $w, email => $w, level => $i } ] ],
      'create_workspace' => [ \&create_workspace, 1, [ {}, {} ] ],
      'create_server'    => [ \&create_server,    1, [ { username => $w, hostname => $w }, { password => $w } ] ],
      'create_job'       => [ \&create_job,       1, [ { cluster_id => $i, name => $w, shell_command => $i }, { description => $i, out_log_path => $w, err_log_path => $w } ] ],
      'create_cluster'   => [ \&create_cluster,   1, [ {}, {} ] ],

      #read
      'read_user'      => [ \&read_user,      1, [ {}, {} ] ],    #whoami
      'read_workspace' => [ \&read_workspace, 1 ],
      'read_server'    => [ \&read_server,    1 ],
      'read_job'       => [ \&read_job,       1 ],
      'read_cluster'   => [ \&read_cluster,   1 ],

      #update
      'update_user'      => [ \&update_user,      1 ],
      'update_workspace' => [ \&update_workspace, 1 ],
      'update_server'    => [ \&update_server,    1 ],
      'update_job'       => [ \&update_job,       1, [ { job_id => $i }, { cluster_id => $i, server_id => $i, pid => $i, state_id => $i, remote_command => $w } ] ],
      'update_cluster'   => [ \&update_cluster,   1 ],

      #delete
      'delete_user'      => [ \&delete_user ],
      'delete_workspace' => [ \&delete_workspace, 1 ],
      'delete_server'    => [ \&delete_server,    1 ],
      'delete_job'       => [ \&delete_job,       1 ],
      'delete_cluster'   => [ \&delete_cluster,   1 ],

      #copy
      'copy_job'     => [ \&copy_job, 1 ],
      'copy_cluster' => [ \&copy_cluster, 1 ],

      #login
      'login' => [ \&login, 0, [ {}, { username => $w, password => $w, token => $w } ] ],

      #start
      'start_job'     => [ \&start_job,     1, [ { job_id => $i }, {} ] ],
      'start_cluster' => [ \&start_cluster, 1 ],

      #kill
      'kill_job' => [ \&kill_job, 1 ],

      #hold
      'hold_job'     => [ \&kill_job,      1 ],
      'hold_cluster' => [ \&start_cluster, 1 ],

      #skip
      'skip_job'     => [ \&skip_job,     1 ],
      'skip_cluster' => [ \&skip_cluster, 1 ],

      #finish
      'finish_job'     => [ \&finish_job,     1 ],
      'finish_cluster' => [ \&finish_cluster, 1 ],

      #misc
      'test_server' => [ \&test_server, 1 ],
   );
   return \%routing;
}

1;
