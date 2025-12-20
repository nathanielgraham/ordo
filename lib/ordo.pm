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
use Cron::Toolkit;
use MIME::Base64;
use UUID::Tiny ':std';
use IO::Socket::INET;
use Email::Valid;
use Mojo::JWT;
use Email::Simple;
use Email::Sender::Simple;
use Email::Sender::Transport::SMTP;
use Data::Dumper;

$ENV{EMAIL_SENDER_SMTP_USER} = 'nathanielgraham1@gmail.com';
$ENV{EMAIL_SENDER_SMTP_PASS} = 'sscy mwcr ybcg vxga';

# TODO: logs, time series stats, runtime alarms, state alarms, threshold alarms, eggs (lay, hatch, rezrov, blorb)
# TODO: add json column to cluster and job, and needs and needed env variables

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

has 'local_url' => sub {
   state $url = 'http://' . &get_local_ip_address() . ':3000';
};

# This method will run once at server start
sub startup {

   my $self = shift;

   # Configure the application
   $self->secrets( [ 'gu$!$#UessM%#eI36#$fYo43@#$uC^%5an', '%!#GDA$#!gfds%#@sdf' ] );

   # In-memory storage for emails
   #$self->attr( emails => sub { {} } );

   # Plugins
   $self->plugin( 'Minion' => { SQLite => "$Bin/../db/sqlite:minion.db" } );

   #my $log = Mojo::Log->new(path => '/tmp/mojo.log', level => 'fatal'); # new log instance
   #$self->log($log); # tell app to use new log instance

   # Helpers

   $self->helper(
      send_email => sub {
         my ( $c, $address, $subject, $body ) = @_;
         print " email: $address, $subject, $body \n";

         require Email::Simple;
         require Email::Sender::Simple;
         require Email::Sender::Transport::SMTP;

         my $email = Email::Simple->create(
            header => [
               To      => $address,
               From    => $ENV{EMAIL_SENDER_SMTP_USER} || 'noreply@example.com',
               Subject => $subject,
            ],
            body => $body,
         );

         my $transport = Email::Sender::Transport::SMTP->new(
            {
               host          => 'smtp.gmail.com',
               port          => 587,
               ssl           => 'starttls',
               sasl_username => $ENV{EMAIL_SENDER_SMTP_USER},
               sasl_password => $ENV{EMAIL_SENDER_SMTP_PASS},
            }
         );

         Email::Sender::Simple->send( $email, { transport => $transport } );
      }
   );

   $self->helper( jwt   => sub { Mojo::JWT->new( secret => shift->app->secrets->[0] || die ) } );
   $self->helper( email => sub { shift->minion->enqueue( email_task => [@_] ) } );

   # $self->helper( to_index => sub { shift->flash( message => shift )->redirect_to('index') } );

   $self->helper( request => \&request );
   $self->helper( routing => \&routing );
   $self->helper( sqlite  => sub { state $sql = Mojo::SQLite->new("$Bin/../db/ordo.db"); $sql->db->query('PRAGMA foreign_keys = ON;') } );

   state $states = $self->sqlite->db->select( 'job_states', ['*'] )->hashes->to_array;
   $self->helper(
      job_states => sub {
         state $states = { map { $_->{state}, $_->{id} } @{$states} };
      }
   );

   # Minion task
   $self->minion->add_task(
      email_task => sub {
         my ( $job, @args ) = @_;
         eval { shift->app->send_email(@args); };
         if ($@) { $job->fail($@); }
      }
   );

   # Router
   my $r = $self->routes;

   # Public routes
   $r->get(
      '/login' => sub {
         my $c = shift;
         $c->render( template => 'login' );
      }
   );

   $r->post(
      '/login' => sub {
         my $c     = shift;
         my $email = $c->param('email') || '';
         return $c->render( template => 'login', error => 'Invalid email' )
           unless $email && Email::Valid->address($email);

         state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );
         my $res = $self->request( $user, { command => 'register_user', email => $email } );

         if ( $res->{success} ) {
            $c->flash( message => "Login link sent to $email" );
            $c->redirect_to('/login');
         }
         else {
            $c->render( template => 'login', error => $res->{message} || 'Failed' );
         }
      }
   );

   $r->get(
      '/logout' => sub {
         my $c = shift;
         $c->cookie( ordo_token => '', { expires => 1, path => '/' } );
         $c->redirect_to('/login');
      }
   );

   # Confirmation
   $r->get(
      '/confirm' => sub {
         my $c   = shift;
         my $jwt = $c->param('jwt');
         unless ($jwt) {
            $c->render( text => 'Missing JWT', status => 400 );
            return;
         }

         my $payload;
         eval { $payload = $c->jwt->decode($jwt) };
         if ( $@ || !$payload || !$payload->{email} ) {
            $c->render( text => 'Invalid link', status => 400 );
            return;
         }

         my $email = $payload->{email};
         my $u     = $c->sqlite->db->select( 'user', ['*'], { email => $email } )->hash;

         unless ( $u && $u->{id} ) {
            $c->render( text => 'User not found', status => 404 );
            return;
         }

         # Confirm user
         $c->sqlite->db->update( 'user', { level => 1 }, { id => $u->{id} } );

         # Set cookie
         $c->cookie(
            ordo_token => $u->{token},
            {
               #http_only => 1,
               secure => $c->req->is_secure,  # auto: true on HTTPS, false on HTTP
               same_site => 'Lax',
               expires   => time + 10 * 365 * 24 * 3600,
               path      => '/',
            }
         );

         # DEBUG: Show what we're setting
         $c->app->log->debug("Setting cookie ordo_token = " . $u->{token});
         $c->app->log->debug("Cookie expires: " . (time + 10 * 365 * 24 * 3600));

         $c->stash( email => $email );
         $c->render( template => 'confirmed' );
      }
   );

   my $auth = $r->under(
      '/' => sub {
         my $c     = shift;
         my $token = $c->cookie('ordo_token');

         $c->app->log->debug("Received cookie ordo_token: " . ($token // 'MISSING'));

         unless ($token) {
            $c->redirect_to('/login');
            return undef;
         }

         state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );
         my $res = $c->app->request( $user, { command => 'login_user', token => $token } );

         if ( $res && $res->{success} ) {
            return 1;
         }
         else {
            $c->redirect_to('/login');
            return undef;
         }
      }
   );

   $auth->get(
      '/monitor' => sub {
         my $c = shift;
         $c->app->log->debug("Reached /monitor — user authenticated");
         $c->reply->static('monitor.html');
      }
   );

   $auth->get('/dashboard' => sub { shift->render(template => 'dashboard') });
   $auth->get('/calendars' => sub { shift->reply->static('calendars.html') });
   $auth->get('/servers' => sub { shift->reply->static('servers.html') });

   $r->websocket('/websocket')->to( controller => 'websocket', action => 'default' );

   # API — token in JSON
   $r->post(
      '/api' => sub {
         my $c       = shift;
         my $json    = $c->req->json    || {};
         my $command = $json->{command} || '';
         my $token   = $json->{token}   || '';

         state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );

         if ( $command eq 'register_user' || $command eq 'login_user' ) {
            my $res = $self->request( $user, $json );
            $c->render( json => $res );
            return;
         }

         my $auth = $self->request( $user, { command => 'login_user', token => $token } );
         unless ( $auth->{success} ) {
            $c->render( json => { success => 0, message => 'Unauthorized' }, status => 401 );
            return;
         }

         my $res = $self->request( $user, $json );
         $c->render( json => $res );
      }
   );

=pod
   # Public routes
   $r->get(
      '/login' => sub {
         my $c = shift;
         $c->render( template => 'login' );
      }
   );

   $r->post(
      '/login' => sub {
         my $c     = shift;
         my $email = $c->param('email') || '';
         return $c->render( template => 'login', error => 'Invalid email' )
           unless $email && Email::Valid->address($email);

         state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );
         my $res = $self->request( $user, { command => 'register_user', email => $email } );

         #my $res = $c->api->call( 'register_user', { email => $email } );

         if ( $res->{success} ) {

            # Send email (your existing code does this)
            $c->flash( message => "Login link sent to $email" );
            $c->redirect_to('/login');
         }
         else {
            $c->render( template => 'login', error => $res->{message} || 'Failed' );
         }
      }
   );

   $r->get(
      '/logout' => sub {
         my $c = shift;
         $c->cookie( ordo_token => '', { expires => 1, path => '/' } );    # clear cookie
         $c->redirect_to('/login');
      }
   );

   # Confirmation link from email
   $r->get(
      '/confirm' => sub {
         my $c   = shift;
         my $jwt = $c->param('jwt');

         unless ($jwt) {
            $c->render( text => 'Missing confirmation token', status => 400 );
            return;
         }

         my $payload;
         eval { $payload = $c->jwt->decode($jwt) };
         if ( $@ || !$payload || !$payload->{email} ) {
            $c->render( text => 'Invalid or expired link', status => 400 );
            return;
         }

         my $email = $payload->{email};
         my $u     = $c->sqlite->db->select( 'user', ['*'], { email => $email } )->hash;

         unless ( $u && $u->{id} ) {
            $c->render( text => 'User not found', status => 404 );
            return;
         }

         # Confirm user
         $c->sqlite->db->update( 'user', { level => 1 }, { id => $u->{id} } );

         # Set long-lived secure cookie
         $c->cookie(
            ordo_token => $u->{token},
            {
               http_only => 1,
               secure    => 1,                              # Enable in production
               same_site => 'Lax',
               expires   => time + 10 * 365 * 24 * 3600,    # 10 years
               path      => '/',
            }
         );

         $c->stash( email => $email );
         $c->render( template => 'confirmed' );
      }
   );

   # Protected routes — require valid token
   my $auth = $r->under(
      '/' => sub {
         my $c = shift;

         my $token = $c->cookie('ordo_token');
         $token ||= $c->param('token');    # fallback for WS or direct access

         print Dumper($token);
         state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );
         return 1 if $token && $self->request( $user, { command => 'login_user', token => $token } )->{success};

         # Not authenticated
         if ( $c->req->is_xhr || $c->stash('format') eq 'json' ) {
            $c->render( json => { success => 0, message => 'Unauthorized' }, status => 401 );
         }
         else {
            $c->redirect_to('/login');
         }
         return undef;
      }
   );

   $auth->get(
      '/monitor' => sub {
         shift->reply->static('monitor.html');
      }
   );

   $r->websocket('/websocket')->to( controller => 'websocket', action => 'default' );

   $r->get(
      '/confirm' => sub {
         my $c  = shift;
         my $email = $self->jwt->decode( $c->param('jwt') )->{email};

         my $u = $self->sqlite->db->select( 'user', ['*'], { email => $email } )->hash;
         unless ( $u->{id} ) {
            $c->render(text => 'Email Not Found', status => 404);
            return;
         }
         $self->sqlite->db->update( 'user', { level => 1 }, { id => $u->{id} } )->hash;
         $c->session( expiration => 0, token => $u->{token}, email => $email, id => $u->{id} );
         $c->render('confirmed');
         #$c->to_index('Email confirmed, you are now logged in');
      }
   );

   # Normal route to controller
   # $r->get('/')->to( controller => 'landing', action => 'welcome' );
   # $r->websocket('/websocket')->to( controller => 'websocket', action => 'default' );

   # HTTP status codes
   # 200 OK: The request was successful.
   # 201 Created: A new resource has been created.
   # 400 BadRequest: The request was invalid or cannot be fulfilled.
   # 401 Unauthorized: Authentication is required and has failed or has not yet been provided.
   # 404 Not Found: The requested resource could not be found.
   # 500 Internal Server Error: The server encountered an unexpected condition.
   # https://www.perl.com/article/193/2015/9/18/How-to-send-verification-emails-using-Mojolicious/

   $r->any(
      '/api' => sub {
         my $c    = shift;
         my $body = $c->req->json;
         if ( ref $body ne 'HASH' || ( !$body->{token} && $body->{command} ne 'register_user' ) ) {
            $c->render( json => { success => 0, message => 'missing login token' }, status => 400 );
         }
         else {
            state $user = ordo::Model::User->new( remote_address => $c->tx->remote_address );
            if ( $body->{command} eq 'register_user' ) {
               my $reg = $self->request( $user, $body );
               $c->render( json => $reg );
               return;
            }
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
=cut

   # start monitors
   my $users_sql = <<~"SQL";
      select min(u.id), u.token, o.id as org_id
      from user u
      join org o on o.id = u.org_id
      join server s on o.id = s.org_id
      where u.token is not null
      group by o.id
   SQL

   my $users = $self->sqlite->db->query($users_sql);
   while ( my $u = $users->hash ) {
      my $user = ordo::Model::User->new();
      $self->request( $user, { token => $u->{token}, command => 'login_user' } );

      my $servers = $self->sqlite->db->select( 'server', ['id'], { org_id => $u->{org_id} } );
      while ( my $server = $servers->hash ) {
         my $connection_ok = $self->_connect_ssh( $user, { id => $server->{id} } );
         next unless $connection_ok;
         $self->_install_monitor( $user, { id => $server->{id} } );
         $self->_start_monitor( $user, { id => $server->{id} } );
      }

      # identify zombies
      $self->sync($user);

      # update stale job states

      my $running  = $self->job_states->{running};
      my $starting = $self->job_states->{starting};
      my $stopping = $self->job_states->{stopping};
      my $ready    = $self->job_states->{ready};

      # TODO: just user jobs
      my $jobs = $self->sqlite->db->select( 'job', ['*'], { state_id => { '=', [ ( $starting, $stopping ) ] } } );
      while ( my $job = $jobs->hash ) {
         $self->_set_job_state( $user, { id => $job->{id}, state => 'failed' } );
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
      my $user = ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      $self->request( $user, { token => $a->{token}, command => 'login_user' } );
      $self->_create_cron_object( $user, { id => $a->{cron_id} } );
   }
}

sub get_local_ip_address {
   my $socket = IO::Socket::INET->new(
      Proto    => 'udp',
      PeerAddr => '198.41.0.4',    # a.root-servers.net
      PeerPort => '53',
   );

   return unless $socket;
   my $local_ip = $socket->sockhost;
   $socket->close;
   return $local_ip;
}

sub request {
   my ( $self, $user, $decoded ) = @_;

   my $response = {};

   state $i = qr/^\d{1,20}$/;    # is integer
   state $w = qr/^\w{1,60}$/;    # is word

   die unless ref $decoded eq 'HASH';

   my ( $command, $params ) = ( delete $decoded->{command}, { map { $_, $decoded->{$_} } grep { defined $decoded->{$_} } keys %{$decoded} } );
   if ( exists $self->routing->{$command} ) {
      my $level = $user->level || 0;
      my ( $sub, $min_level, $legal_options ) = @{ $self->routing->{$command} };
      my ( $required, $optional ) = @{$legal_options};

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
               if ( scalar @{ $params->{$param} } > 1000 ) {
                  $error      = 1;
                  $bad_option = $param;
                  last;
               }

               #foreach my $item ( @{ $params->{$param} } ) {
               #   unless ( $item =~ /^\d+$/ && $item < 999999999 || ref $item eq 'HASH' && scalar keys %{$item} < 100 ) {
               #      $error      = 1;
               #      $bad_option = $param;
               #      last;
               #   }
               #}
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

sub _cluster_info {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );

   return unless $cluster_id;
   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
   return $cluster;
}

sub read_cluster {
   my ( $self, $user, $d ) = @_;

   my $cluster = $self->_cluster_info( $user, $d );

   return { success => 0, message => 'cluster not found' } unless $cluster && $cluster->{id};
   my $cluster_id = $cluster->{id};

   my @fields = qw(clone_cluster_id clonable json loops loop_count on_fail id cal_id mode org_id user_id parent_id state_id name description started ended creation_time);

   my %rv = map { $_, $cluster->{$_} } @fields;
   $rv{jobstate} = $self->sqlite->db->select( 'job_states', ['state'], { id => $rv{state_id} } )->hash->{state} if $rv{state_id};
   $rv{cal_name} = $self->sqlite->db->select( 'cal',        ['name'],  { id => $rv{cal_id} } )->hash->{name}    if $rv{cal_id};
   $rv{jobs}     = $self->_find_jobs( $user, { cluster_id => $cluster_id } );
   $rv{needs}    = $self->_read_cluster_needs( $user, { id => $cluster_id } );

   #$rv{needed}   = $self->sqlite->db->query("select cluster_id as id from cluster_needs where needs_cluster_id = $cluster_id")->hashes->to_array;
   $rv{next_start} = $self->_cal_next_start( $user, { id => $rv{cal_id} } ) if $rv{cal_id};

   # permissions
   my %permission = (
      read    => [qw(7 6 5 4)],
      write   => [qw(7 6 3 2)],
      execute => [qw(7 5 3 1)],
   );

   my $cbit =
       $user->{id} == $cluster->{user_id}    ? substr( $cluster->{mode}, 0, 1 )
     : $user->{org_id} == $cluster->{org_id} ? substr( $cluster->{mode}, 1, 1 )
     :                                         substr( $cluster->{mode}, 2, 1 );

   while ( my ( $rwx, $bit ) = each %permission ) {
      $rv{$rwx} = scalar( grep { $cbit == $_ } @{$bit} ) ? 1 : 0;
   }

   return { success => 0, message => 'missing read permission' } unless $rv{read};
   return { success => 1, %rv };
}

sub _set_cluster_state {
   my ( $self, $user, $d ) = @_;

   # id state

   my $update_hash = {};

   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id} } )->hash;
   return unless $cluster->{id};
   return if $cluster->{state_id} == $self->job_states->{immutable};

   if ( $d->{state} && $self->job_states->{ $d->{state} } ) {
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
   }

   my $killed = $self->job_states->{killed};
   my $failed = $self->job_states->{failed};
   my $zombie = $self->job_states->{zombie};

   if ( $d->{state} eq 'running' ) {
      return if $cluster->{state_id} == $self->job_states->{running};
      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      # set parent cluster to running if no failed jobs or failed clusters in parent cluster
      my $j = $self->sqlite->db->select( 'job',     ['id'], { cluster_id => $cluster->{parent_id}, state_id => { '=', [ ( $killed, $failed, $zombie ) ] } } );
      my $c = $self->sqlite->db->select( 'cluster', ['*'],  { parent_id  => $cluster->{parent_id}, id => { '!=', $cluster->{id} }, state_id => { '=', [ ( $killed, $failed, $zombie ) ] } } );
      unless ( $j->hash || $c->hash ) {
         $self->_set_cluster_state( $user, { state => 'running', id => $cluster->{parent_id} } ) if $cluster->{parent_id};
      }
   }

   # elsif ( $d->{state} eq 'complete' || $d->{state} eq 'ice_complete' ) {
   elsif ( scalar( grep { $d->{state} eq $_ } (qw( complete ice_complete pruned_complete)) ) ) {

      $update_hash->{state_id} = $self->job_states->{complete} if $d->{state} eq 'pruned_complete';

      #if ( $cluster->{clone_cluster_id} ) {
      #   $self->delete_cluster($user, { id => $cluster->{id} });
      #   return;
      #}
      if ( $d->{state} eq 'complete' ) {

         # loops
         if ( $cluster->{loops} && $cluster->{loops} > $cluster->{loop_count} ) {

            my $loop_count = $cluster->{loop_count} || 0;
            $loop_count++;

            $self->sqlite->db->update(
               'cluster',
               {
                  loop_count => $loop_count,
                  state_id   => $self->job_states->{looping}
               },
               { id => $cluster->{id} }
            );

            $self->_start_cluster(
               $user,
               {
                  id => $cluster->{id},

                  #force     => 1,
                  origin    => 'loop',
                  origin_id => $cluster->{id}
               }
            );

            #$self->sqlite->db->update( 'cluster', { state_id => $self->job_states->{looping} }, { id => $cluster->{id} } );

            return 1;
         }
         elsif ( $cluster->{loop_count} ) {
            $self->sqlite->db->update( 'cluster', { loop_count => 0 }, { id => $cluster->{id} } );
         }
      }

      #$update_hash->{json} = undef;
      $update_hash->{ended} = time;

      # update cluster
      $self->sqlite->db->update( 'cluster', $update_hash, { id => $cluster->{id} } );

      # complete parent cluster if possible
      if ( $cluster->{parent_id} && $self->_cluster_is_complete( $user, { id => $cluster->{parent_id} } ) ) {
         $self->_set_cluster_state( $user, { state => 'complete', id => $cluster->{parent_id} } );
      }

      # start waiting clusters that just had last dependency met
      my $complete = $self->job_states->{complete};
      my $pruned   = $self->job_states->{pruned};
      my $waiting  = $self->job_states->{waiting};
      my $ready    = $self->job_states->{ready};
      my $ice      = $self->job_states->{ice};

      my $depends_sql = <<~"SQL";
         select cn.cluster_id as id
         from cluster_needs cn
         join cluster c on cn.cluster_id = c.id
         where cn.needs_cluster_id = $cluster->{id}
         and c.state_id in ($ready, $waiting, $ice, $pruned)
      SQL

      my $cneed = $self->sqlite->db->query($depends_sql);

      while ( my $c = $cneed->hash ) {

         # start cluster if all dependancies are complete or on ice

         #my $cluster_sql = <<~"SQL";
         #   select cn.needs_cluster_id, c.state_id
         #   from cluster_needs cn
         #   join cluster c on cn.needs_cluster_id = c.id
         #   where cn.cluster_id = $c->{id}
         #   and c.state_id not in ($complete, $ice)
         #SQL

         #unless ( $ret->hash ) {
         #my $ret = $self->sqlite->db->query($cluster_sql);

         if ( $self->_cluster_needs_met( $user, { id => $c->{id} } ) ) {
            my $rv = $self->_start_cluster( $user, { id => $c->{id}, origin => 'auto', noreset => 1 } );
         }
      }
      if ( $cluster->{clone_cluster_id} ) {
         $self->delete_cluster( $user, { id => $cluster->{id} } );
         return;
      }
   }
   elsif ( $d->{state} eq 'failed' || $d->{state} eq 'killed' ) {
      $update_hash->{ended} = time;

      # fail parent cluster
      if ( $cluster->{parent_id} && $cluster->{parent_id} != $user->root_cluster_id ) {
         $self->_set_cluster_state( $user, { id => $cluster->{parent_id}, state => 'failed' } );
      }

      #TODO: change on_fail to take cluster name

      # fail alarm
      if ( $cluster->{on_fail} && $d->{state} eq 'failed' ) {
         my $fail_cluster = $self->sqlite->db->select( 'cluster', ['id'], { id => $cluster->{on_fail} } );
         if ( $fail_cluster->{id} ) {
            $self->_start_cluster( $user, { id => $fail_cluster->{id}, origin => 'fail', force => 1 } );
         }
      }
   }
   elsif ( $d->{state} eq 'ready' || $d->{state} eq 'waiting' ) {
      $update_hash->{json}    = undef;
      $update_hash->{started} = undef;
      $update_hash->{ended}   = undef;

      #unless ( $cluster->{ended} ) {
      #   $update_hash->{ended} = time;
      #}
   }

   # update cluster
   $self->sqlite->db->update( 'cluster', $update_hash, { id => $d->{id} } ) if scalar keys %{$update_hash};
   return 1;
}

sub start_cluster {
   my ( $self, $user, $d ) = @_;
   $d->{origin} = 'user';
   $self->_start_cluster( $user, $d );
}

sub _start_cluster {
   my ( $self, $user, $d ) = @_;

   #my $cluster = $self->_cluster_info( $user, $d );
   my $cluster    = $self->read_cluster( $user, $d );
   my $cluster_id = $cluster->{id};

   return { success => 0, message => 'cluster not found' } unless $cluster_id;

   # check jobs are in ready state
   my $complete = $self->job_states->{complete};
   my $pruned   = $self->job_states->{pruned};
   my $waiting  = $self->job_states->{waiting};
   my $running  = $self->job_states->{running};
   my $failed   = $self->job_states->{failed};
   my $ready    = $self->job_states->{ready};
   my $hold     = $self->job_states->{hold};
   my $ice      = $self->job_states->{ice};

   if ( $cluster->{id} == $user->root_cluster_id ) {
      return { success => 0, message => 'root cluster cannot be started' };
   }
   elsif ( $cluster->{state_id} == $self->job_states->{hold} ) {
      return { success => 0, skipped => 1, message => 'cluster on hold' };
   }
   elsif ( $cluster->{state_id} == $self->job_states->{pruned} ) {
      $self->complete_cluster( $user, { id => $cluster->{id} } );
      return { success => 0, skipped => 1, message => 'cluster pruned' };
   }

   #elsif ( scalar ( grep { $cluster->{state_id} == $self->job_states->{$_} } (qw(ice))) ) {
   elsif ( $cluster->{state_id} == $self->job_states->{ice} ) {
      $self->_set_cluster_state( $user, { id => $cluster_id, state => 'ice_complete' } );
      return { success => 0, skipped => 1, message => 'cluster on ice' };
   }
   elsif ( $cluster->{clonable} && $cluster->{state_id} == $self->job_states->{running} ) {
      my $response = $self->clone_cluster( $user, { id => $cluster_id } );
      return $response unless $response->{success} && $response->{clone_id};
      return $self->_start_cluster( $user, { id => $response->{clone_id}, force => 1 } );
   }
   elsif ( $cluster->{state_id} == $self->job_states->{running} ) {
      return { success => 0, message => 'cluster already running' };
   }

   unless ( $d->{force} ) {

      if ( $cluster->{next_start} && $d->{origin} ne 'cron' ) {
         return { success => 0, waiting => 1, message => 'expecting cron start. use --force to start anyway' };
      }

      # prevent cluster from running if needs not met
      if ( !$self->_cluster_needs_met( $user, { id => $cluster->{id} } ) ) {
         return { success => 0, waiting => 1, message => "dependency not met. use --force to start anyway" };

      }
   }

   unless ( $d->{origin} && $d->{origin} eq 'loop' ) {
      $self->sqlite->db->update( 'cluster', { loop_count => 0 }, { id => $cluster->{id} } );
   }

   $self->_reset_cluster( $user, { id => $cluster_id } ) unless $d->{noreset};
   $self->_set_cluster_state( $user, { state => 'running', id => $cluster_id } );

   # start clusters in cluster
   my $clusters_started   = 0;
   my $clusters_completed = 0;
   my $clusters_failed    = 0;
   my $clusters_waiting   = 0;
   my $clusters_skipped   = 0;

   my $clusters = $self->sqlite->db->select(
      'cluster',
      ['id'],
      {
         org_id    => $user->org_id,
         parent_id => $cluster_id,
         state_id  => { '=', [ $ready, $waiting, $pruned ] }
      },
      { -desc => 'id' }
   )->hashes;

   foreach my $c ( @{ $clusters->to_array } ) {
      my $rv = $self->_start_cluster( $user, { id => $c->{id}, origin => 'auto', noreset => 1 } );
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
      my $rv = $self->_start_job( $user, { origin => 'start', %$j } );
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

   if ( $jobs_failed || $clusters_failed ) {
      $self->_set_cluster_state( $user, { state => 'failed', id => $cluster_id } );
      return { success => 0, failed => 1, message => "cluster $cluster_id failed" };
   }
   elsif ( $jobs_waiting || $clusters_waiting ) {
      $self->_set_cluster_state( $user, { state => 'waiting', id => $cluster_id } );
      my $message = "cluster started.";
      $message .= " $clusters_waiting clusters waiting." if $clusters_waiting;
      $message .= " $jobs_waiting jobs waiting."         if $jobs_waiting;
      return { success => 1, waiting => 1, message => $message };
   }
   elsif ( $self->_cluster_is_complete( $user, { id => $cluster_id } ) ) {
      $self->_set_cluster_state( $user, { state => 'complete', id => $cluster_id } );
      return { success => 1, completed => 1, message => "cluster $cluster_id complete" };
   }
   else {
      return { success => 1, started => 1, message => "cluster $cluster_id started" };
   }
}

sub _reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};

   return unless $cluster_id;

   my $servers = $self->sqlite->db->query("select distinct(server_id) from job where cluster_id = $cluster_id");
   while ( my $s = $servers->hash ) {
      $self->_sync_server( $user, { id => $s->{id} } );
   }

   if ( $cluster_info->{state_id} == $self->job_states->{running} && !$self->_cluster_is_complete( $user, { id => $cluster_id } ) ) {
      return;
   }

   my $pruned = $self->job_states->{pruned};
   my $hold   = $self->job_states->{hold};
   my $ice    = $self->job_states->{ice};

   my $job_select     = { cluster_id => $cluster_id };
   my $cluster_select = { parent_id  => $cluster_id };

   unless ( $d->{all} ) {
      $job_select->{state_id}     = { '!=', [ -and => ( $hold, $ice, $pruned ) ] };
      $cluster_select->{state_id} = { '!=', [ -and => ( $hold, $ice, $pruned ) ] };
   }

   my $needs         = $self->_read_cluster_needs( $user, { id => $cluster_id } );
   my $cluster_state = $cluster_info->{next_start} || scalar keys %$needs ? 'waiting' : 'ready';

   # set cluster state to ready or waiting
   $self->_set_cluster_state( $user, { id => $cluster_id, state => $cluster_state } );

   my $jobs = $self->sqlite->db->select( 'job', ['*'], $job_select );
   while ( my $job = $jobs->hash ) {

      #next if scalar( grep { $job->{state_id} == $self->job_states->{$_} } (qw(running watching)) );
      #next if $job->{pid} || $job->{ppid};
      my $needs     = $self->_read_job_needs( $user, { id => $job->{id} } );
      my $job_state = scalar keys %$needs ? 'waiting' : 'ready';
      $self->_set_job_state( $user, { id => $job->{id}, state => $job_state } );
   }

   # reset descendent clusters
   my $clusters = $self->sqlite->db->select( 'cluster', ['id'], $cluster_select );
   while ( my $cluster = $clusters->hash ) {
      $self->_reset_cluster( $user, { id => $cluster->{id}, all => $d->{all} } );
   }

   return 1;
}

sub reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_reset_cluster( $user, $d );
   return $rv ? { success => 1 } : { success => 0, message => 'cluster is running' };
}

sub find_cluster {
   my ( $self, $user, $d ) = @_;

   my $cluster = $self->read_cluster( $user, $d );

   #my $cluster_id = $cluster->{id};

   # undef = root cluster, 0 = cluster not found
   #return { success => 0, message => 'cluster not found' } if defined $cluster_id && $cluster_id == 0;
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my @clusters;

   return { success => 0, message => 'you do not have permission to read this cluster' } unless $cluster->{read};

   push @clusters, $cluster;

   my $find_clusters = sub {
      my $id     = shift;
      my $org_id = $user->org_id;

      my $sql = <<~"SQL";
         select c.*, cal.name as cal_name, js.state as jobstate
         from cluster c
         left join cal on c.cal_id = cal.id
         left join job_states js on c.state_id = js.id
         where c.parent_id = $id
         and c.org_id = $org_id 
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

   $find_clusters->( $cluster->{id} );
   return scalar @clusters ? { success => 1, clusters => \@clusters } : { success => 0, message => 'no clusters found' };
}

sub update_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );

   return $cluster unless $cluster->{id};
   my $cluster_id = $cluster->{id};

   return { success => 0, message => 'cluster not found' }                                   unless $cluster_id;
   return { success => 0, message => 'you do not have permission to write to this cluster' } unless $cluster->{write};

   my $needs_all = $self->_resolve_cluster_ids( $user, $d->{needs} );
   my $needs_any = $self->_resolve_cluster_ids( $user, $d->{needs_any} );

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(mode description loops clonable)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   # verify that alarm clusters actually exist
   for my $alarm ( grep { exists $d->{$_} } (qw(on_fail)) ) {
      if ( $d->{$alarm} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$alarm}, org_id => $user->org_id } )->hash;
         $update_hash->{$alarm} = $d->{$alarm} if $res->{id};
      }
      else {
         $update_hash->{$alarm} = undef;
      }
   }

   if ( $d->{json} ) {
      eval { my $data = decode_json( $d->{json} ); };
      if ($@) {
         return { success => 0, message => 'invalid json' };
      }
      else {
         $update_hash->{json} = $d->{json};
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
      if ( $needs_all || $needs_any ) {
         $self->_write_cluster_needs( $user, { needs_all => $needs_all, needs_any => $needs_any, id => $cluster_id, } );
         $success++;
      }

      #$self->_write_cluster_needs( $user, { id => $cluster_id, needs => $d->{needs} } ) if $d->{needs};
      #if ( $d->{needs} ) {
      #   $self->_write_cluster_needs( $user, { id => $cluster_id, needs => $d->{needs} } );
      #   $success++;
      #}

      if ( $d->{remove_needs} ) {
         $self->sqlite->db->delete( 'cluster_needs', { cluster_id => $cluster_id } ) if $d->{remove_needs};
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
   return { success => 0, message => 'missing write permission' } unless $cluster->{write};

   # delete cluster and all descendants

   my $clusters = $self->find_cluster( $user, { id => $cluster->{id} } )->{clusters};
   push @{$clusters}, $cluster;

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

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};
   return { success => 0, message => 'a job by that name already exists' } if $p->{job_id};
   return { success => 0, message => 'a cluster by that name exists' }     if $p->{cluster_id};

   my $cluster = $self->read_cluster( $user, { id => $p->{parent_cluster_id} } );

   return { success => 0, message => 'missing write permission' } unless $cluster->{write};

   my $needs_all = $d->{needs}     ? $self->_resolve_cluster_ids( $user, $d->{needs} )     : [];
   my $needs_any = $d->{needs_any} ? $self->_resolve_cluster_ids( $user, $d->{needs_any} ) : [];

   my $insert_hash = {
      org_id    => $user->org_id,
      user_id   => $user->id,
      parent_id => $p->{parent_cluster_id},
      name      => $p->{name},
   };

   for (qw(clonable mode loops state_id description started ended)) {
      $insert_hash->{$_} = $d->{$_} if $d->{$_};
   }

   if ( $d->{json} ) {
      eval { my $data = decode_json( $d->{json} ); };
      if ($@) {
         return { success => 0, message => 'invalid json' };
      }
      else {
         $insert_hash->{json} = $d->{json};
      }
   }

   # verify that alarm clusters actually exist
   for my $alarm ( grep { exists $d->{$_} } (qw(on_fail)) ) {
      if ( $d->{$alarm} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$alarm}, org_id => $user->org_id } )->hash;
         $insert_hash->{$alarm} = $d->{$alarm} if $res->{id};
      }
      else {
         $insert_hash->{$alarm} = undef;
      }
   }

   $insert_hash->{mode} =
       $d->{mode}    ? $d->{mode}
     : $user->{mode} ? $user->{mode}
     :                 770;

   my $id = $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id;

   if ( scalar @$needs_all || scalar @$needs_any ) {
      $self->_write_cluster_needs( $user, { needs_all => $needs_all, needs_any => $needs_any, id => $id, } );
   }

   #$self->_write_cluster_needs( $user, { id => $id, needs => $d->{needs} } ) if $d->{needs};

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
   my $cluster = $self->read_cluster( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $cluster_id = $cluster->{id};

   unless ( $cluster->{read} ) {
      return { success => 0, message => 'you do not have permission to read this cluster' };
   }

   # 0 = not found, undef = root cluster
   #return { success => 0, message => 'unable to locate cluster' } if defined $cluster_id && $cluster_id == 0;
   return { success => 0, message => 'unable to locate cluster' } unless $cluster_id;

   my $fullpath  = $self->id2path( $user, { id => $cluster_id } );
   my $user_info = $self->read_user($user);
   eval { $self->sqlite->db->update( 'user', { base_cluster_id => $cluster_id }, { id => $user_info->{id} } ); };
   my $success = $@ ? 0 : 1;
   return { path => $fullpath, cluster_id => $cluster_id, success => $success };
}

sub path2id {
   my ( $self, $user, $path ) = @_;

   my $base_cluster_id = $user->base_cluster_id;
   my $root_cluster_id = $user->root_cluster_id;
   my $base_path       = $self->id2path( $user, { id => $base_cluster_id } );
   my $root_path       = $self->id2path( $user, { id => $root_cluster_id } );

   my $absolute = ( $path && substr( $path, 0, 1 ) eq '/' ) ? 1 : 0;

   $path =~ s/^\/*root\/*// if $path;

   my $fullpath =
       $absolute && $path  ? "/$root_path/$path"
     : $absolute           ? "/$root_path"
     : $path && $base_path ? "/$base_path/$path"
     : $base_path          ? "/$base_path"
     :                       "/$root_path";

   #print "FULL: $fullpath\n";
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

   my ( $self, $user, $d ) = @_;

   my $cluster    = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{id} } )->hash;
   my $cluster_id = $cluster->{id};

   my @names;
   my $count = 0;

   while ( defined $cluster_id ) {
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

   my $results = $self->sqlite->db->select( 'user', ['*'],               { token => $d->{token} } )->hash;
   my $org     = $self->sqlite->db->select( 'org',  ['root_cluster_id'], { id    => $results->{org_id} } )->hash;

   my ( $message, $success, $path );
   my $host  = hostname()        || get_local_ip_address();
   my $login = $results->{email} || $results->{id};

   if ( $results->{id} ) {
      $user->id( $results->{id} );
      $user->level( $results->{level} );
      $user->org_id( $results->{org_id} );
      $user->token( $results->{token} );
      $user->base_cluster_id( $results->{base_cluster_id} );
      $user->root_cluster_id( $org->{root_cluster_id} );
      $path    = $self->id2path( $user, { id => $results->{base_cluster_id} } );
      $message = 'login success';
      $success = 1;
   }
   else {
      $message = 'login failed';
      $success = 0;
   }
   return { message => $message, success => $success, email => $login, user_id => $user->id, remote_address => $user->remote_address, token => $user->token, host => $host, path => $path, level => $user->level };
}

sub register_user {
   my ( $self, $user, $d ) = @_;
   my $valid = Email::Valid->new;

   # Comment out the next line to disable MX record checking (requires network access)
   $valid->mxcheck(1);

   unless ( $d->{email} && $valid->address( $d->{email} ) ) {
      return { success => 0, message => 'invalid email' };
   }

   my $login_token;

   my $existing_user = $self->sqlite->db->select( 'user', ['*'], { email => $d->{email} } )->hash;
   if ( $existing_user && $existing_user->{email} ) {
      $login_token = $existing_user->{token};
      my $rows = $self->sqlite->db->update( 'user', { level => 0 }, { email => $d->{email} } )->rows;
      return { success => 0, message => 'email update error' } unless $rows;
   }
   else {
      # create new user
      $d->{level} = 0;
      my $new_user = $self->create_user( $user, $d );
      if ( $new_user->{success} ) {
         $login_token = $new_user->{token};
      }
      else {
         return $new_user;
      }
   }

   # send email
   my $jwt = $self->jwt->claims( { email => $d->{email} } )->encode;

   #my $url = $self->url_for('confirm')->to_abs->query(jwt => $jwt);
   my $url = $self->local_url . $self->url_for('confirm')->query( jwt => $jwt );

   my $confirm_message = <<~"MSG";
   Welcome to the Ordo job scheduler!

   Please click the following link to activate your account:
   $url
   MSG

   $self->email( $d->{email}, 'Ordo Registration', $confirm_message );

   my $register_message = <<~"MSG";
   A confirmation email has been sent to $d->{email}
   Click the link in the email to confirm and then run this script again.
   MSG

   # login new user
   my $login = $self->login_user( $user, { token => $login_token } );
   return $login->{success} ? { success => 1, token => $login_token, message => $register_message } : { success => 0, message => 'registration failed' };
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
   my ( $user_id, $user_token );

   eval {
      my $tx = $db->begin;

      # create org
      my $org_id;
      if ( $d->{org_id} ) {
         my $org = $self->sqlite->db->select( 'org', ['id'], { id => $d->{org_id} } )->hash;
         if ( $org->{id} ) {
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
      if ( $root->{id} ) {
         $root_id = $root->{id};
      }
      else {
         $root_id = $db->insert( 'cluster', { org_id => $org_id, name => 'root', mode => 770, state_id => $self->job_states->{immutable} } )->last_insert_id;
      }

      die "unable to create root cluster" unless $root_id;

      $user_token                     = $self->_new_token();
      $user_insert->{token}           = $user_token;
      $user_insert->{org_id}          = $org_id;
      $user_insert->{base_cluster_id} = $root_id;
      $user_insert->{mode}            = 770;
      $user_id                        = $db->insert( 'user', $user_insert )->last_insert_id;
      die unless $user_id;

      my $org_token = $self->_new_token();

      #$user->id($user_id);

      $db->update( 'org', { user_id => $user_id, token => $org_token, root_cluster_id => $root_id }, { id => $org_id } );
      $db->update( 'cluster', { user_id => $user_id }, { id => $root_id } );
      $tx->commit;
   };

   if ($@) {
      return { message => $@, success => 0 };
   }
   else {
      #my $token = $self->new_token( $user, { id => $user_id } );
      return { success => 1, id => $user_id, token => $user_token, message => "user $user_id created" };
   }
}

sub new_token {
   my ( $self, $user, $d ) = @_;
   my $user_id = $d->{id} || $user->id;
   my $token   = $self->_new_token();
   $self->sqlite->db->update( 'user', { token => $token }, { id => $user_id } )->hash;
   return { success => 1, token => $token };
}

sub _new_token {
   my $uuid  = create_uuid_as_string();
   my $token = hmac_sha1_hex($uuid);
   return $token;
}

sub read_user {
   my ( $self, $user, $decoded ) = @_;

   my $info = $self->sqlite->db->select( 'user', ['*'], { id => $user->id } )->hash;
   my $path = $self->id2path( $user, { id => $info->{base_cluster_id} } );

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

sub _path_info {
   my ( $self, $user, $path ) = @_;
   my $cluster_id = $self->path2id( $user, $path );

   return { cluster_id => $cluster_id, success => 1 } if $cluster_id;

   my ($root)  = $path =~ /^(\/)/;
   my @parts   = split( '/', $path );
   my $name    = pop @parts;
   my $newpath = join( '/', @parts );
   $newpath = $root . $newpath if $root;
   my $parent_cluster_id = $self->path2id( $user, $newpath );
   my $job               = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $parent_cluster_id, name => $name } )->hash;
   if ($parent_cluster_id) {
      my $rv = { success => 1 };
      $rv->{parent_cluster_id} = $parent_cluster_id;
      $rv->{job_id}            = $job->{id} if $job->{id};
      $rv->{name}              = $name      if $name;
      return $rv;
   }
   return { success => 0 };
}

sub _job_info {
   my ( $self, $user, $d ) = @_;

   my $org_id = $user->org_id;
   my $job_id;

   if ( $d->{id} ) {
      $job_id = $d->{id};
   }
   elsif ( $d->{name} ) {
      my $path_info = $self->_path_info( $user, $d->{name} );
      if ( $path_info->{success} && $path_info->{job_id} ) {
         $job_id = $path_info->{job_id};
      }
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

   $job->{needs}  = $self->_read_job_needs( $user, { id => $job_id } );
   $job->{needed} = $self->sqlite->db->query("select job_id as id from job_needs where needs_job_id = $job->{id}")->hashes->to_array;

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

      push @jobs, $j;
   }
   return \@jobs;
}

sub clone_cluster {
   my ( $self, $user, $d ) = @_;

   # id name parent_id

   my $cluster = $self->_cluster_info( $user, $d );

   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $parent_id = $d->{parent_id} || $cluster->{parent_id};

   my $clone_id = $self->_clone_cluster( $user, { id => $cluster->{id}, parent_id => $parent_id, origin => 1 } );
   return $clone_id ? { success => 1, clone_id => $clone_id } : { success => 0 };
}

sub _clone_cluster {
   my ( $self, $user, $d ) = @_;

   # id name parent_id

   my $running = $self->job_states->{running};
   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id}, org_id => $user->org_id } )->hash;

   return unless $cluster->{id};

   state( %job_map, %cluster_map, %cluster_needs, %job_needs );
   my $name;
   if ( $d->{origin} ) {
      $name = delete $cluster->{name};
   }

   $cluster->{parent_id}        = $d->{parent_id} || $cluster->{parent_id};
   $cluster->{clone_cluster_id} = delete $cluster->{id};
   $cluster->{clonable}         = undef;
   unless ( scalar( grep { $cluster->{state_id} == $self->job_states->{$_} } (qw(hold ice)) ) ) {
      $cluster->{state_id} = $self->job_states->{ready};
   }

   # cluster needs
   my $cn = $self->_read_cluster_needs( $user, { id => $cluster->{clone_cluster_id} } );
   $cluster_needs{ $cluster->{clone_cluster_id} } = [ keys %{$cn} ];

   my $cluster_id;
   eval {
      #my $tx = $self->sqlite->db->begin;
      $cluster_id = $self->sqlite->db->insert( 'cluster', $cluster )->last_insert_id;
      if ( $d->{origin} ) {
         my $new_name = $name .= "_$cluster_id";
         $self->sqlite->db->update( 'cluster', { name => $new_name }, { id => $cluster_id } );
      }

      $cluster_map{ $cluster->{clone_cluster_id} } = $cluster_id;

      my $jobs = $self->sqlite->db->select( 'job', ['*'], { cluster_id => $cluster->{clone_cluster_id} }, { order_by => 'id' } );
      while ( my $job = $jobs->hash ) {
         $job->{clone_job_id} = delete $job->{id};
         $job->{cluster_id}   = $cluster_id;

         # job needs
         my $jn = $self->_read_job_needs( $user, { id => $job->{clone_job_id} } );
         $job_needs{ $job->{clone_job_id} } = [ keys %{$jn} ] if scalar keys %{$jn};

         my $job_id = $self->sqlite->db->insert( 'job', $job )->last_insert_id;
         $self->_reset_job_stats( $user, { id => $job_id } );

         $job_map{ $job->{clone_job_id} } = $job_id;
      }

      #$self->_reset_cluster( $user, { id => $cluster_id } );

      # clone child clusters
      my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{clone_cluster_id} }, { order_by => 'id' } );
      while ( my $child = $children->hash ) {
         $self->_clone_cluster( $user, { id => $child->{id}, parent_id => $cluster_id } ) if $child->{id};
      }

      # update cluster needs
      # TODO: implement needs_any for jobs and clusters
      if ( $d->{origin} ) {
         my %new_job_needs = map {
            $job_map{$_},
              [ map { exists $job_map{$_} ? $job_map{$_} : $_ } @{ $job_needs{$_} } ]
         } keys %job_needs;
         while ( my ( $k, $v ) = each %new_job_needs ) {
            $self->_write_job_needs( $user, { needs_all => $v, id => $k } );
         }
         my %new_cluster_needs = map {
            $cluster_map{$_},
              [ map { exists $cluster_map{$_} ? $cluster_map{$_} : $_ } @{ $cluster_needs{$_} } ]
         } keys %cluster_needs;

         while ( my ( $k, $v ) = each %new_cluster_needs ) {
            $self->_write_cluster_needs( $user, { needs_all => $v, id => $k } );
         }
         $self->_reset_cluster( $user, { id => $cluster_id } );
      }

      #$tx->commit;
   };
   if ($@) {
      $self->delete_cluster( $user, { id => $cluster_id } );
      return;
   }
   else {
      return $cluster_id;
   }
}

sub kill_cluster {

   my ( $self, $user, $d ) = @_;
   my $cluster    = $self->_cluster_info( $user, $d );
   my $cluster_id = $cluster->{id};
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id} } );
   while ( my $job = $jobs->hash ) {
      $self->_hard_kill_job( $user, { id => $job->{id} } );
   }

   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'killed' } );

   # stop descendent clusters
   my $child_clusters = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id} } );
   while ( my $child_cluster = $child_clusters->hash ) {
      $self->kill_cluster( $user, { id => $child_cluster->{id} } );
   }

   return { success => 1 };
}

sub hold_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} } (qw(starting running immutable)) ) {
      return { success => 0, message => 'unable to hold cluster' };
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

sub complete_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $running = $self->job_states->{running};

   #if ( grep { $self->job_states->{$_} == $cluster->{state_id} } (qw(starting running immutable)) ) {
   if ( !$self->_cluster_is_complete( $user, { id => $cluster->{id} } ) ) {
      return { success => 0, message => 'unable to complete cluster' };
   }

   # complete cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'complete' } );

   # complete child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'complete' } );
   }

   # complete child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $child = $children->hash ) {
      $self->complete_cluster( $user, { id => $child->{id}, state => 'complete' } );

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
   $self->_reset_cluster( $user, { id => $cluster->{id}, all => 1 } );

   # start cluster if parent is running
   my $parent = $self->sqlite->db->select( 'cluster', ['state_id'], { id => $cluster->{parent_id} } )->hash;

   if ( $parent && $parent->{state_id} == $self->job_states->{running} ) {
      my $rv = $self->_start_cluster(
         $user,
         {
            id      => $cluster->{id},
            noreset => 1,
            origin  => 'auto',
         }
      );
   }
   return { success => 1 };
}

sub ice_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} } (qw(starting running immutable)) ) {
      return { success => 0, message => 'cluster cannot be iced' };
   }

   # ice cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'ice' } );

   # ice child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'ice' } );
   }

   # ice child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $child = $children->hash ) {
      $self->ice_cluster( $user, { id => $child->{id}, state => 'ice' } );
   }
   return { success => 1 };
}

sub prune_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' } unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} } (qw(starting running immutable)) ) {
      return { success => 0, message => 'cluster cannot be pruned' };
   }

   # prune cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'pruned' } );

   # prune child jobs
   my $jobs = $self->sqlite->db->select( 'job', ['id'], { cluster_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'pruned' } );
   }

   # prune child clusters
   my $children = $self->sqlite->db->select( 'cluster', ['id'], { parent_id => $cluster->{id}, state_id => { '!=', [ -and => ($running) ] } } );
   while ( my $child = $children->hash ) {
      $self->prune_cluster( $user, { id => $child->{id}, state => 'prune' } );
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
   $self->_reset_cluster( $user, { id => $cluster->{id}, all => 1 } );

   return { success => 1 };
}

sub create_job {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_create_job( $user, $d );
   return $rv;
}

sub _create_job {
   my ( $self, $user, $d ) = @_;

   my $j = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $j->{success};
   return { success => 0, message => 'a job by that name already exists' }    if $j->{job_id};
   return { success => 0, message => 'a cluster by that name exists' }        if $j->{cluster_id};
   return { success => 0, message => 'jobs not allowed in the root cluster' } if $user->root_cluster_id == $j->{parent_cluster_id};

   my $needs_all = $d->{needs}     ? $self->_resolve_job_ids( $user, $d->{needs} )     : [];
   my $needs_any = $d->{needs_any} ? $self->_resolve_job_ids( $user, $d->{needs_any} ) : [];

   my $insert_hash = { cluster_id => $j->{parent_cluster_id}, name => $j->{name} };
   $insert_hash->{delay} = $d->{delay} if $d->{delay} && $d->{delay} <= 3600;

   #my @fields = qw(clonable retrys loops delay pid id state_id description started ended);
   my @fields = qw(clonable retrys loops delay state_id description started ended);

   for (@fields) {
      $insert_hash->{$_} = $d->{$_} if $d->{$_};
   }

   if ( $d->{json} ) {
      eval { my $data = decode_json( $d->{json} ); };
      if ($@) {
         return { success => 0, message => 'invalid json' };
      }
      else {
         $insert_hash->{json} = $d->{json};
      }
   }

   # verify that alarm clusters actually exist
   for my $alarm ( grep { exists $d->{$_} } (qw(on_fail)) ) {
      if ( $d->{$alarm} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$alarm}, org_id => $user->org_id } )->hash;
         $insert_hash->{$alarm} = $d->{$alarm} if $res->{id};
      }
      else {
         $insert_hash->{$alarm} = undef;
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
   $self->_write_job_needs( $user, { needs_all => $needs_all, needs_any => $needs_any, id => $id, cluster_id => $j->{cluster_id} } );

   #elsif ( $d->{needs} ) {
   #   $self->_write_job_needs( $user, { needs => $d->{needs}, id => $id, cluster_id => $j->{cluster_id} } );
   #}

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

   #return { success => 0, message => 'job is running' } if $job->{state_id} == $self->job_states->{running};

   if ( scalar( grep { $self->job_states->{$_} == $job->{state_id} } (qw(starting running immutable)) ) ) {
      return { success => 0, message => 'job cannot be iced' };
   }

   $self->_set_job_state( $user, { state => 'ice', id => $job->{id} } );
   return { success => 1 };
}

sub prune_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};

   if ( scalar( grep { $self->job_states->{$_} == $job->{state_id} } (qw(starting running immutable)) ) ) {
      return { success => 0, message => 'job cannot be pruned' };
   }

   $self->_set_job_state( $user, { state => 'pruned', id => $job->{id} } );
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
            id     => $job->{id},
            origin => 'auto',
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

# returns true if cluster is complete
sub _cluster_is_complete {
   my ( $self, $user, $d ) = @_;

   my $cluster_id = $d->{id};

   my $complete = $self->job_states->{complete};
   my $pruned   = $self->job_states->{pruned};
   my $ice      = $self->job_states->{ice};

   my $jb = $self->sqlite->db->select( 'job',     ['*'], { cluster_id => $cluster_id, state_id => { '!=', [ -and => ( $complete, $ice, $pruned ) ] } }, { limit => 1 } );
   my $cl = $self->sqlite->db->select( 'cluster', ['*'], { parent_id  => $cluster_id, state_id => { '!=', [ -and => ( $complete, $ice, $pruned ) ] } }, { limit => 1 } );

   return $jb->hash || $cl->hash ? 0 : 1;
}

sub _set_job_state {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );    #job info

   my $failed    = $self->job_states->{failed};
   my $killed    = $self->job_states->{killed};
   my $ready     = $self->job_states->{ready};
   my $waiting   = $self->job_states->{waiting};
   my $completed = $self->job_states->{complete};
   my $pruned    = $self->job_states->{pruned};
   my $ice       = $self->job_states->{ice};
   my $zombie    = $self->job_states->{zombie};

   my $update_hash;

   if ( $self->job_states->{ $d->{state} } ) {
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
   }

   my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $job->{cluster_id} } )->hash;

   if ( $d->{state} eq 'starting' ) {
      $self->_reset_job_stats( $user, { id => $job->{id} } );
   }

   #if ( $d->{state} eq 'running' && scalar( grep { $d->{state} == $self->job_states->{$_} } (qw(starting running))  $cluster->{state_id} ne $self->job_states->{running} ) {
   if ( scalar( grep { $d->{state} eq $_ } (qw(sleeping running)) ) ) {

      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      # set cluster to running if no failed jobs or clusters in cluster
      my $j = $self->sqlite->db->select( 'job',     ['*'], { cluster_id => $job->{cluster_id}, id => { '!=', $job->{id} },     state_id => { '=', [ ( $killed, $failed, $zombie ) ] } } );
      my $c = $self->sqlite->db->select( 'cluster', ['*'], { parent_id  => $cluster->{id},     id => { '!=', $cluster->{id} }, state_id => { '=', [ ( $killed, $failed ) ] } } );
      unless ( $j->hash || $c->hash ) {
         $self->_set_cluster_state( $user, { state => 'running', id => $job->{cluster_id} } ) unless $cluster->{state_id} == $self->job_states->{running};
      }
   }
   elsif ( grep { $d->{state} eq $_ } (qw(failed killed zombie)) ) {

      $self->sqlite->db->update( 'job', { state_id => $self->job_states->{ $d->{state} } }, { id => $job->{id} } );
      $update_hash->{ended} = time;
      $self->_reset_job_stats( $user, { id => $job->{id} } ) unless $d->{state} eq 'zombie';
      $self->_set_cluster_state( $user, { state => 'failed', id => $job->{cluster_id} } );

      #if ( $d->{state} eq 'failed' || $d->{state} eq 'zombie' ) {
      if ( $d->{state} eq 'failed' ) {

         #if ( $job->{retrys} && $job->{retrys} > $job->{retry_count} && $cluster->{state_id} == $self->job_states->{running} ) {
         if ( $job->{retrys} && $job->{retrys} > $job->{retry_count} ) {
            my $retry_count = $job->{retry_count} || 0;
            $retry_count++;
            $self->sqlite->db->update( 'job', { retry_count => $retry_count }, { id => $job->{id} } );
            $self->_set_job_state( $user, { state => 'retrying', id => $job->{id} } );

            my $rv = $self->_start_job(
               $user,
               {
                  id     => $job->{id},
                  origin => 'retry',
                  force  => 1,
               }
            );
         }

         # fail alarm
         if ( $job->{on_fail} ) {
            my $cluster_alarm = $self->sqlite->db->select( 'cluster', ['id'], { id => $job->{on_fail} } )->hash;
            if ( $cluster_alarm->{id} ) {
               my $rv = $self->_start_cluster(
                  $user,
                  {
                     id                => $cluster_alarm->{id},
                     origin            => 'fail',
                     origin_job_id     => $job->{id},
                     origin_cluster_id => $cluster->{id},
                     force             => 1,
                  }
               );
            }
         }
      }
   }

   #elsif ( $d->{state} eq 'complete' || $d->{state} eq 'ice_complete' ) {
   elsif ( scalar( grep { $d->{state} eq $_ } (qw( complete ice_complete pruned_complete)) ) ) {

      $update_hash->{state_id} = $self->job_states->{complete} if $d->{state} eq 'pruned_complete';

      if ( $d->{state} eq 'complete' ) {

         # only loop if cluster is running
         #if ( $job->{loops} && $job->{loops} > $job->{loop_count} && $cluster->{state_id} == $self->job_states->{running} ) {
         if ( $job->{loops} && $job->{loops} > $job->{loop_count} ) {
            my $loop_count = $job->{loop_count} || 0;
            $loop_count++;

            $self->sqlite->db->update( 'job', { loop_count => $loop_count, state_id => $self->job_states->{looping} }, { id => $job->{id} } );

            $self->_start_job(
               $user,
               {
                  id     => $job->{id},
                  origin => 'loop',

                  #force    => 1,
               }
            );
            $update_hash->{state_id} = $self->job_states->{looping};
         }

         #elsif ( $job->{loop_count} ) {
         else {
            #$self->sqlite->db->update( 'job', { loop_count => 0 }, { id => $job->{id} } );
            $self->sqlite->db->update( 'job', { loop_count => 0, state_id => $self->job_states->{complete} }, { id => $job->{id} } );
         }
      }

      # find jobs in ready or waiting state that just had a dependency met
      my $depends_sql = <<~"SQL";
         select jn.job_id, j.state_id, jn.needs_any_mode
         from job_needs jn
         join job j on jn.job_id = j.id
         where jn.needs_job_id = $job->{id}
         and j.state_id in ($ready, $waiting, $ice, $pruned)
      SQL

      my $need = $self->sqlite->db->query($depends_sql);
      while ( my $j = $need->hash ) {

         if ( $self->_job_needs_met( $user, { id => $j->{job_id} } ) ) {
            my $rv = $self->_start_job(
               $user,
               {
                  id                => $j->{job_id},
                  origin            => 'auto',
                  origin_job_id     => $job->{id},
                  origin_cluster_id => $cluster->{id},
                  force             => 1,
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
   elsif ( $d->{state} eq 'retrying' ) {
      return if scalar( grep { $job->{state_id} == $self->job_states->{$_} } (qw(starting running)) );
   }
   elsif ( $d->{state} eq 'looping' ) {
      return if scalar( grep { $job->{state_id} == $self->job_states->{$_} } (qw(starting running)) );
   }
   elsif ( $d->{state} eq 'ready' || $d->{state} eq 'waiting' ) {
      $update_hash->{loop_count}  = 0;
      $update_hash->{retry_count} = 0;
      $update_hash->{json}        = undef;
      $update_hash->{started}     = undef;
      $update_hash->{ended}       = undef;
   }

   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   return 1;
}

sub update_job {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_update_job( $user, $d );
   return $rv;
}

sub _resolve_job_ids {
   my ( $self, $user, $needs ) = @_;
   return unless $needs && ref $needs eq 'ARRAY';
   my @need_ids;
   for my $need ( @{$needs} ) {
      my $path_info = $self->_path_info( $user, $need );
      push @need_ids, $path_info->{job_id} if $path_info->{success} && $path_info->{job_id};
   }
   return \@need_ids;
}

sub _resolve_cluster_ids {
   my ( $self, $user, $needs ) = @_;
   return unless $needs && ref $needs eq 'ARRAY';
   my @need_ids;
   for my $need ( @{$needs} ) {
      my $path_info = $self->_path_info( $user, $need );
      push @need_ids, $path_info->{cluster_id} if $path_info->{success} && $path_info->{cluster_id};
   }
   return \@need_ids;
}

sub _update_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless $job->{id};

   my $needs_all = $d->{needs}     ? $self->_resolve_job_ids( $user, $d->{needs} )     : [];
   my $needs_any = $d->{needs_any} ? $self->_resolve_job_ids( $user, $d->{needs_any} ) : [];

   my @fields = qw(clonable retrys loops delay pctcpu pid start priority rss pctmem fname signal exit_code state_id description started ended server_id script);
   push( @fields, 'ppid' ) if $d->{state} && $d->{state} eq 'running';

   my $update_hash = { map { $_, $d->{$_} } grep { exists $d->{$_} } @fields };

   if ( $d->{json} ) {
      eval { my $data = decode_json( $d->{json} ); };
      if ($@) {
         return { success => 0, message => 'invalid json' };
      }
      else {
         $update_hash->{json} = $d->{json};
      }
   }

   # verify that alarm clusters actually exist
   for my $alarm ( grep { exists $d->{$_} } (qw(on_fail)) ) {
      if ( $d->{$alarm} ) {
         my $res = $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{$alarm}, org_id => $user->org_id } )->hash;
         $update_hash->{$alarm} = $d->{$alarm} if $res->{id};
      }
      else {
         $update_hash->{$alarm} = undef;
      }
   }

   $update_hash->{delay} = $d->{delay} if $d->{delay} && $d->{delay} <= 3600;

   if ( $d->{state} ) {
      my $rv = $self->_set_job_state( $user, { id => $job->{id}, state => $d->{state} } );

      # job log
      if ( $d->{log_id} && $d->{ppid} ) {
         if ( $d->{state} eq 'running' ) {
            my $insert_hash = { map { $_ => $d->{$_} } grep { defined $d->{$_} } (qw(log_id ppid pid started)) };
            $insert_hash->{job_id} = $job->{id};
            my $rows = $self->sqlite->db->insert( 'job_log', $insert_hash )->rows;

            # delete oldest log
            if ($rows) {
               my $count = $self->sqlite->db->query("select count(*) as count from job_log where job_id = $d->{id}")->hash->{count};
               if ( $count > 12 ) {
                  my $dl = $self->sqlite->db->select( 'job_log', ['*'], { job_id => $job->{id} }, { order_by => 'id', limit => 1 } )->hash;
                  $self->sqlite->db->delete( 'job_log', { id => $dl->{id} } );

                  my $ssh = $self->ssh_connection->{ $job->{server_id} };
                  unless ( $ssh && $ssh->check_master ) {
                     $self->_connect_ssh( $user, { id => $job->{server_id} } );
                     $ssh = $self->ssh_connection->{ $job->{server_id} };
                  }

                  # TODO: multi-platform script
                  $ssh->spawn("rm ordo_node/logs/*\.$dl->{job_id}\.$dl->{ppid}\.$dl->{log_id}\.log");
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

   if ( scalar @$needs_all || scalar @$needs_any ) {
      $self->_write_job_needs( $user, { needs_all => $needs_all, needs_any => $needs_any, id => $job->{id}, cluster_id => $job->{cluster_id} } );
   }

   #if ( $d->{needs} ) {
   #   my $rv = $self->_write_job_needs( $user, { needs => $d->{needs}, id => $job->{id}, cluster_id => $job->{cluster_id} } );
   #}

   if ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'], { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' } unless $res->{id};
      $update_hash->{server_id} = $res->{id};
   }
   $update_hash->{name}        = $d->{newname} if $d->{newname};
   $update_hash->{last_update} = time;

   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   $self->sqlite->db->delete( 'job_needs', { job_id => $job->{id} } ) if $d->{remove_needs};

   return { success => 1 };
}

sub _read_job_needs {
   my ( $self, $user, $d ) = @_;
   my $job_id = $d->{id};

   my $sql = <<~"SQL";
        SELECT needs_job_id, needs_any_mode
        FROM job_needs
        WHERE job_id = ?
    SQL

   my $rows = $self->sqlite->db->query( $sql, $job_id );
   my %needs;

   while ( my $row = $rows->hash ) {
      my $target_id = $row->{needs_job_id};
      my $mode      = $row->{needs_any_mode} || 0;    # 0 = AND, 1 = OR

      # Also fetch the state of the target job
      my $target = $self->sqlite->db->select( 'job', ['state_id'], { id => $target_id } )->hash;

      $needs{$target_id} = {
         state_id => $target->{state_id} || 0,
         mode     => $mode,                      # 0 = all, 1 = any
      };
   }

   return \%needs;
}

sub _read_job_needs2 {
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
   my $job_id    = $d->{id};
   my $needs_all = $d->{needs_all} || [];    # AND dependencies
   my $needs_any = $d->{needs_any} || [];    # OR dependencies

   return unless ( scalar @$needs_all || scalar @$needs_any );

   my $tx = $self->sqlite->db->begin;

   # Clear old dependencies
   $self->sqlite->db->query( 'DELETE FROM job_needs WHERE job_id = ?', $job_id );

   # Insert AND deps (needs_any_mode = 0)
   for my $target_id (@$needs_all) {
      next unless $target_id =~ /^\d+$/;
      $self->sqlite->db->query( 'INSERT OR IGNORE INTO job_needs (job_id, needs_job_id, needs_any_mode) VALUES (?, ?, 0)', $job_id, $target_id );
   }

   # Insert OR deps (needs_any_mode = 1)
   for my $target_id (@$needs_any) {
      next unless $target_id =~ /^\d+$/;
      $self->sqlite->db->query( 'INSERT OR IGNORE INTO job_needs (job_id, needs_job_id, needs_any_mode) VALUES (?, ?, 1)', $job_id, $target_id );
   }

   $tx->commit;
   return 1;
}

sub _write_job_needs2 {
   my ( $self, $user, $d ) = @_;

   my $job = $self->sqlite->db->select( 'job', ['cluster_id'], { id => $d->{id} } )->hash;
   return 0 unless $job->{cluster_id};
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

         #if ( $d->{cluster_id} == $need_cluster_id ) {
         if ( $job->{cluster_id} == $need_cluster_id ) {
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
   my $cluster_id = $d->{id};
   my $needs_all  = $d->{needs_all};
   my $needs_any  = $d->{needs_any};

   return unless $needs_all || $needs_any;

   my $tx = $self->sqlite->db->begin;

   $self->sqlite->db->query( 'DELETE FROM cluster_needs WHERE cluster_id = ?', $cluster_id );

   for my $target_id (@$needs_all) {
      next unless $target_id =~ /^\d+$/;
      $self->sqlite->db->query(

         #'INSERT OR IGNORE INTO cluster_needs (cluster_id, needs_cluster_id, needs_any_mode) VALUES (?, ?, 0)',
         'INSERT INTO cluster_needs (cluster_id, needs_cluster_id, needs_any_mode) VALUES (?, ?, 0)',
         $cluster_id, $target_id
      );
   }

   for my $target_id (@$needs_any) {
      next unless $target_id =~ /^\d+$/;
      $self->sqlite->db->query( 'INSERT INTO cluster_needs (cluster_id, needs_cluster_id, needs_any_mode) VALUES (?, ?, 1)', $cluster_id, $target_id );
   }

   $tx->commit;
   return 1;
}

sub _read_cluster_needs {
   my ( $self, $user, $d ) = @_;
   my $job_id = $d->{id};

   my $sql = <<~"SQL";
        SELECT needs_cluster_id, needs_any_mode
        FROM cluster_needs
        WHERE cluster_id = ?
    SQL

   my $rows = $self->sqlite->db->query( $sql, $job_id );
   my %needs;

   while ( my $row = $rows->hash ) {
      my $target_id = $row->{needs_cluster_id};
      my $mode      = $row->{needs_any_mode} || 0;    # 0 = AND, 1 = OR

      # Also fetch the state of the target job
      my $target = $self->sqlite->db->select( 'cluster', ['state_id'], { id => $target_id } )->hash;

      $needs{$target_id} = {
         state_id => $target->{state_id} || 0,
         mode     => $mode,                      # 0 = all, 1 = any
      };
   }
   return \%needs;
}

sub _read_cluster_needs2 {
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
         my $update = { map { $_, $pid->{$_} } grep { exists $pid->{$_} } (qw(pctcpu pid start priority rss pctmem ppid fname)) };
         $update->{last_update} = time;
         $self->sqlite->db->update( 'job', $update, { id => $job->{id} } );

         if ( $job->{stats} ) {
            my $js_insert = { map { $_, $update->{$_} } (qw(pctcpu pid start priority rss pctmem ppid fname)) };
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

   eval { $self->sqlite->db->update( 'server', $uh, { id => $d->{id} } ) };
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
     ? "perl ordo_node/bin/find_pid.pl $d->{pid}"
     : "perl ordo_node/bin/find_match.pl $d->{match}";

   my ( $out, $err ) = $ssh->capture2($cmd);
   return { success => 0, message => $ssh->error } if $ssh->error;

   my ($pid) = $out =~ /^(\d+)$/;
   return { success => 0, message => 'pid not found' } unless $pid;

   $d->{pid}      = $pid;
   $d->{state_id} = $self->job_states->{watching};
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

sub start_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->start_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->start_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub kill_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->kill_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->kill_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub read_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->read_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      my $rv = $self->read_cluster( $user, $d );
      return $rv;
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub hold_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->hold_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->hold_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub release_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->release_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->release_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub ice_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->ice_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->ice_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub melt_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->melt_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->melt_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub delete_path {
   my ( $self, $user, $d ) = @_;

   my $p = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $p->{success};

   if ( $p->{job_id} ) {
      $d->{id} = $p->{job_id};
      return $self->delete_job( $user, $d );
   }
   elsif ( $p->{cluster_id} ) {
      $d->{id} = $p->{cluster_id};
      return $self->delete_cluster( $user, $d );
   }
   return { success => 0, message => 'job or cluster not found' } if $p->{job_id};
}

sub _cluster_needs_met {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, { id => $d->{id} } );
   return 1 unless $cluster->{needs} && scalar keys %{ $cluster->{needs} };

   my $complete   = 0;
   my $incomplete = 0;

   while ( my ( $need_id, $meta ) = each %{ $cluster->{needs} } ) {
      if (  $meta->{state_id} == $self->job_states->{complete}
         || $meta->{state_id} == $self->job_states->{ice}
         || $meta->{state_id} == $self->job_states->{pruned} )
      {
         $complete++;
      }
      else {
         $incomplete++;
      }
   }

   # If ANY dependency has needs_any_mode = 1 → OR logic
   my $has_or = $self->sqlite->db->query( "SELECT 1 FROM job_needs WHERE job_id = ? AND needs_any_mode = 1 LIMIT 1", $d->{id} )->hash;

   return $has_or ? ( $complete > 0 ) : ( $incomplete == 0 );
}

sub _job_needs_met {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, { id => $d->{id} } );
   return 1 unless $job->{needs} && keys %{ $job->{needs} };

   my $complete   = 0;
   my $incomplete = 0;

   while ( my ( $need_id, $meta ) = each %{ $job->{needs} } ) {
      if (  $meta->{state_id} == $self->job_states->{complete}
         || $meta->{state_id} == $self->job_states->{ice}
         || $meta->{state_id} == $self->job_states->{pruned} )
      {
         $complete++;
      }
      else {
         $incomplete++;
      }
   }

   # If ANY dependency has needs_any_mode = 1 → OR logic

   my $has_or = $self->sqlite->db->query( "SELECT 1 FROM job_needs WHERE job_id = ? AND needs_any_mode = 1 LIMIT 1", $d->{id} )->hash;

   return $has_or ? ( $complete > 0 ) : ( $incomplete == 0 );
}

sub start_job {
   my ( $self, $user, $d ) = @_;
   $d->{origin} = 'user';
   return $self->_start_job( $user, $d );
}

sub _start_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );
   return { success => 0, skipped => 1, message => 'job not found' } unless $job->{id};

   if ( ( $job->{pid} || $job->{ppid} ) && scalar grep { $self->job_states->{$_} == $job->{state_id} } (qw(starting running)) ) {
      return { success => 0, skipped => 1, message => 'job is already running' };
   }

   # skip if job on ice
   if ( $job->{state_id} == $self->job_states->{ice} ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'ice_complete' } );
      return { success => 0, skipped => 1, message => 'job on ice' };
   }

   # skip if job pruned
   if ( $job->{state_id} == $self->job_states->{pruned} ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'pruned_complete' } );
      return { success => 0, skipped => 1, message => 'job pruned' };
   }

   # don't start if dependencies not satisfied

   unless ( $d->{force} ) {
      if ( $job->{state_id} == $self->job_states->{waiting} && !$self->_job_needs_met( $user, { id => $job->{id} } ) ) {
         return { success => 0, waiting => 1, message => 'dependency not met. use --force to start anyway' };
      }

      #   while ( my ( $id, $state_id ) = each %{ $job->{needs} } ) {
      #      unless ( ($job->{needs_any} && grep { $state_id == $self->job_states->{$_} } (qw(complete ice)))  ) {

      #      if ( !grep { $state_id == $self->job_states->{$_} } (qw(complete ice)) ) {

      # dependency not met
      #         return { success => 0, waiting => 1, message => 'dependency not met. use --force to start anyway' };
      #      }
      #   }
      #}
      elsif ( !scalar( grep { $job->{state_id} == $self->job_states->{$_} } (qw(ready looping retrying)) ) ) {
         unless ( $d->{origin} eq 'user' ) {
            return { success => 0, message => 'job not ready. use --force to start anyway' };
         }
      }
   }

   # reset counters on user start
   if ( $d->{origin} eq 'user' ) {
      $self->sqlite->db->update( 'job', { loop_count => 0, retry_count => 0 }, { id => $job->{id} } );
   }

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
      return { success => 0, message => 'server unreachable' };
   }

   my $needs  = join( ' ', keys %{ $job->{needs} } ) if $job->{needs};
   my $needed = join( ' ', @{ $job->{needed} } )     if $job->{needed};

   my $token = $user->token;
   my $opts  = {
      token      => $token,
      id         => $job->{id},
      cluster_id => $job->{cluster_id},
      server_id  => $job->{server_id},
      script     => $job->{script},
      api        => $self->local_url . '/api',
   };
   $opts->{origin}            = $d->{origin}            if $d->{origin};
   $opts->{origin_job_id}     = $d->{origin_job_id}     if $d->{origin_job_id};
   $opts->{origin_cluster_id} = $d->{origin_cluster_id} if $d->{origin_cluster_id};

   $opts->{delay}  = $job->{delay} if $job->{delay};
   $opts->{json}   = $job->{delay} if $job->{delay};
   $opts->{needs}  = $needs        if $needs;
   $opts->{needed} = $needed       if $needed;

   my $json = encode_json($opts);

   # TODO: encode with MIME::Base64
   my $json_hex = unpack( 'H*', $json );
   my $cmd      = "perl ordo_node/bin/launcher.pl $json_hex";

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
   return { success => 0, message => 'hk job not found' } unless $job && $job->{id};
   return { success => 0, message => 'hk pid not found' } unless $job->{pid} || $job->{ppid};
   return { success => 0, message => 'watcher jobs cannot be killed. unwatch or delete it instead' } if $job->{state_id} == $self->job_states->{watching};

   my $server = $self->_server_info( $user, { id => $job->{server_id} } );
   return { success => 0, message => 'server not found' } unless $server && $server->{id};

   my @pids;
   unshift @pids, $job->{pid}  if $job->{pid};
   unshift @pids, $job->{ppid} if $job->{ppid};

   my $pid_list = join( ', ', @pids );

   # check connection
   my $ssh = $self->ssh_connection->{ $server->{id} };
   $self->_connect_ssh( $user, { id => $server->{id} } ) unless $ssh && $ssh->check_master;
   $ssh = $self->ssh_connection->{ $server->{id} };
   return { success => 0, message => 'server not connected' } unless $ssh && $ssh->check_master;

   my $rv = $ssh->system("perl -e 'kill KILL, $pid_list'");
   if ($rv) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'killed' } );
      return { success => 1 };
   }
   return { success => 0 };
}

#sub kill_job {
#   my ( $self, $user, $d ) = @_;
#   $self->_hard_kill_job($user, $d);
#}

sub kill_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   return { success => 0, message => 'pid not found' }                                               if !$job->{pid} && !$job->{ppid};
   return { success => 0, message => 'watcher jobs cannot be killed. unwatch or delete it instead' } if $job->{state_id} == $self->job_states->{watching};

   if ( scalar grep { $job->{state_id} == $self->job_states->{$_} } (qw(waiting looping retrying)) ) {
      return $self->_hard_kill_job( $user, { id => $job->{id} } );
   }

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } ) unless $ssh && $ssh->check_master;
   $ssh = $self->ssh_connection->{ $job->{server_id} };

   my @pids;
   unshift @pids, $job->{pid} if $job->{pid};

   # unshift @pids, $job->{ppid} if $job->{ppid};
   my $pid_list = join( ', ', @pids );

   $self->_set_job_state( $user, { id => $job->{id}, state => 'stopping' } );
   my $rv      = $ssh->system("perl -e 'kill TERM, $pid_list'");
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

   my %update = map { $_ => undef } (qw(signal pid ppid exit_code pctcpu start priority rss pctmem fname));

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

   #my $s = $self->_server_info( $user, $d );
   return 0 unless $d->{password} && $d->{user} && $d->{host};
   my $port = $d->{port} || 22;

   #my $password = $d->{password} || $s->{password} || '';
   #return 0 unless $password;

   # copy public ssh key to remote host
   my $copy_key  = "sshpass -p $d->{password} ssh-copy-id -p $port $d->{user}\@$d->{host}";
   my $exit_code = system($copy_key);
   $exit_code = $? >> 8;
   return $exit_code ? 0 : 1;
}

# install
sub _install_monitor {
   my ( $self, $user, $d ) = @_;
   my $s = $self->_server_info( $user, $d );
   return unless $s;

   # check connection
   my $ssh = $self->ssh_connection->{ $s->{id} };

   #$self->_connect_ssh( $user, { id => $s->{id} } ) unless ( $ssh && $ssh->check_master );
   #$ssh = $self->ssh_connection->{ $s->{id} };

   # install
   eval {
      # copy ordo_node directory to remote server
      $ssh->scp_put( { recursive => 1 }, "$Bin/../ordo_node" );

      #or die "scp failed: " . $ssh->error;

      my $json = encode_json( { token => $user->token, id => $s->{id} } );

      # install nice-to-have modules in the background
      #my $install_core = "perl ordo_node/bin/install.pl";
      #$ssh->spawn($install_core);
      #die $! if $ssh->error || !$ssh->check_master;

      # gather basic info about the remote system
      my ( $out, $err ) = $ssh->capture2("perl ordo_node/bin/basicinfo.pl");
      my $error = $ssh->error || $err;
      return if $error;
      my $basicinfo = decode_json($out);
      my $update    = { map { $_, $basicinfo->{$_} } grep { $basicinfo->{$_} } (qw(home os cores cwd ip_address)) };
      $self->sqlite->db->update( 'server', $update, { id => $s->{id} } );
   };
   return $@ ? 0 : 1;
}

sub create_monitor {
   my ( $self, $user, $d ) = @_;

   my $id = $self->_new_connection( $user, $d );
   return { success => 0, message => "unable to create connection" } unless $id;

   # create monitor and start it
   my $installed = $self->_install_monitor( $user, { id => $id } ) or die "install failed";
   return { success => 0, message => "install failed" } unless $installed;

   $self->_start_monitor( $user, { id => $id } ) or die "start failed";
   return { success => 1 };
}

sub read_monitor {
   my ( $self, $user, $d ) = @_;
   my $server = $self->_server_info( $user, $d );
   return $server->{id} ? { success => 1, %$server } : { success => 0, message => 'monitor not found' };
}

sub find_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers = $self->sqlite->db->select( 'server', ['id'], { org_id => $user->org_id } );
   my @server_list;
   while ( my $server = $servers->hash ) {
      my $s = $self->read_monitor( $user, { id => $server->{id} } );
      next unless $s->{success};
      push @server_list, $s;
   }
   return scalar @server_list ? { success => 1, servers => \@server_list } : { success => 0, message => 'no monitors found' };
}

sub _server_info {
   my ( $self, $user, $d ) = @_;
   my $select =
       $d->{id}   ? { id => $d->{id}, org_id => $user->org_id }
     : $d->{name} ? { org_id => $user->org_id, name => $d->{name} }
     :              undef;

   return unless $select;
   my $server = $self->sqlite->db->select( 'server', ['*'], $select )->hash;
   return $server->{id} ? $server : undef;

   #my $info = { map { $_, $server->{$_} } (qw(id os cwd home cores update_time ping user host name port total_memory used_memory cpu total_disk used_disk uptime)) };
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

sub _new_connection {
   my ( $self, $user, $d ) = @_;

   return unless $d->{user} && $d->{host};

   my $port = $d->{port} || 22;

   my %option = (
      user        => $d->{user},
      port        => $port,
      batch_mode  => 1,
      timeout     => 3,
      master_opts => [ -o => "ControlMaster=auto" ],
   );

   $option{password} = $d->{password} if $d->{password};
   my $ssh = Net::OpenSSH->new( $d->{host}, %option );

   return if $ssh->error || !$ssh->check_master;

   # set up ssh keys
   if ( $d->{password} ) {
      my $key_update = {
         password => $d->{password},
         user     => $d->{user},
         host     => $d->{host},
         port     => $port,
      };
      my $exit_code = $self->_ssh_copy( $user, $key_update );
      return if $exit_code;
   }

   my $insert_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(name user host)) };
   $insert_hash->{org_id} = $user->org_id;

   my $id;
   eval { $id = $self->sqlite->db->insert( 'server', $insert_hash )->last_insert_id; };

   if ($id) {
      $self->ssh_connection->{$id} = $ssh;
      return $id;
   }
   else {
      return;
   }
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

sub update_monitor {
   my ( $self, $user, $d ) = @_;

   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

   my $update_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(user host password total_memory used_memory cpu total_disk used_disk uptime)) };
   $update_hash->{ping}        = $self->_ping( $server->{host} ) if $server->{host};
   $update_hash->{update_time} = time;

   if ( scalar keys %{$update_hash} ) {
      eval { $self->sqlite->db->update( 'server', $update_hash, { id => $server->{id} } ) };
      return { success => 0, message => $@ } if $@;
   }

   my $connection_ok = 1;
   if ( $d->{password} ) {
      $self->_ssh_copy( $user, { user => $server->{user}, host => $server->{host}, password => $d->{password} } ) if $d->{password};
      $connection_ok = $self->_connect_ssh( $user, { id => $server->{id} } );
   }
   return $connection_ok ? { success => 1 } : { success => 0, message => 'connection failed' };
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
   return { success => 0, message => 'server not found' } unless $server && $server->{name};

   eval {
      $self->sqlite->db->delete( 'server', { id => $server->{id} } );
      $self->_disconnect_ssh( $user, { id => $server->{id} } );
      delete $self->ssh_connection->{ $server->{id} };
   };
   return $@ ? { success => 0, message => $@ } : { success => 1 };
}

sub active_pids {
   my ( $self, $user, $d ) = @_;

   my $server = $self->sqlite->db->select( 'server', ['*'], { id => $d->{id}, org_id => $user->org_id } )->hash;
   return { success => 0, message => 'server not found' } unless $server->{id};

   my $jobs = $self->sqlite->db->select( 'job', [ 'id', 'pid', 'state_id' ], { pid => { '!=', undef }, server_id => $server->{id} } )->hashes->to_array;
   return { success => 0, message => 'no pids found' } unless scalar @$jobs;

   my %pid_map = map { $_->{pid} => $_ } @$jobs;
   return { success => 1, server_id => $server->{id}, pids => \%pid_map };
}

sub _sync_server {
   my ( $self, $user, $d ) = @_;

   #my $server = $self->_server_info( $user, $d );
   return unless $d->{id};

   my $zombie_count  = 0;
   my $revived_count = 0;

   my $jobs = $self->sqlite->db->query("select * from job where (pid is not null or ppid is not null) and server_id = $d->{id}")->hashes->to_array;

   return unless scalar @$jobs;
   my %pid_map;
   for my $j ( grep { $_->{pid} } @$jobs ) {
      $pid_map{ $j->{pid} } = $j;
   }

   for my $j ( grep { $_->{ppid} } @$jobs ) {
      $pid_map{ $j->{ppid} } = $j;
   }

   # check connection
   my $ssh = $self->ssh_connection->{ $d->{id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $d->{id} } );
   }
   $ssh = $self->ssh_connection->{ $d->{id} };
   unless ( $ssh && $ssh->check_master ) {
      for my $job_id ( map { $_->{id} } values %pid_map ) {
         $self->_set_job_state( $user, { id => $job_id, state => 'zombie' } );
         $zombie_count++;
      }
      return;
   }
   my $json     = encode_json( [ keys %pid_map ] );
   my $json_hex = unpack( 'H*', $json );
   my $cmd      = "perl ordo_node/bin/sync.pl $json_hex";
   my ( $out, $err ) = $ssh->capture2($cmd);
   return if $err || $ssh->error;
   my $found = decode_json($out);
   return unless ref $found eq 'HASH' && exists $found->{alive} && exists $found->{zombies};
   my @alive   = @{ $found->{alive} }   if ref $found->{alive} eq 'ARRAY';
   my @zombies = @{ $found->{zombies} } if ref $found->{zombies} eq 'ARRAY';

   foreach my $zombie ( grep { exists $pid_map{$_} } @zombies ) {
      $self->_set_job_state( $user, { id => $pid_map{$zombie}->{id}, state => 'zombie' } );
      $zombie_count++;
   }
   foreach my $life ( grep { exists $pid_map{$_} } @alive ) {
      if ( $pid_map{$life}->{state_id} != $self->job_states->{running} ) {
         $self->_set_job_state( $user, { id => $pid_map{$life}->{id}, state => 'running' } );
         $revived_count++;
      }
   }
   return 1;
}

sub sync {
   my ( $self, $user, $d ) = @_;

   my $zombie_count  = 0;
   my $revived_count = 0;
   my $servers       = $self->sqlite->db->select( 'server', ['*'], { org_id => $user->org_id } );
   while ( my $server = $servers->hash ) {

      my $jobs = $self->sqlite->db->query("select * from job where (pid is not null or ppid is not null) and server_id = $server->{id}")->hashes->to_array;

      #my $jobs = $self->sqlite->db->select('job', ['id','pid','ppid','state_id'], { pid => { '!=', undef }, server_id => $server->{id} } )->hashes->to_array;
      next unless scalar @$jobs;
      my %pid_map;
      for my $j ( grep { $_->{pid} } @$jobs ) {
         $pid_map{ $j->{pid} } = $j;
      }

      for my $j ( grep { $_->{ppid} } @$jobs ) {
         $pid_map{ $j->{ppid} } = $j;
      }

      # check connection
      my $ssh = $self->ssh_connection->{ $server->{id} };
      unless ( $ssh && $ssh->check_master ) {
         $self->_connect_ssh( $user, { id => $server->{id} } );
      }
      $ssh = $self->ssh_connection->{ $server->{id} };
      unless ( $ssh && $ssh->check_master ) {
         for my $job_id ( map { $_->{id} } values %pid_map ) {
            $self->_set_job_state( $user, { id => $job_id, state => 'zombie' } );
            $zombie_count++;
         }
         next;
      }
      my $json     = encode_json( [ keys %pid_map ] );
      my $json_hex = unpack( 'H*', $json );
      my $cmd      = "perl ordo_node/bin/sync.pl $json_hex";
      my ( $out, $err ) = $ssh->capture2($cmd);
      next if $err || $ssh->error;
      my $found = decode_json($out);
      next unless ref $found eq 'HASH' && exists $found->{alive} && exists $found->{zombies};
      my @alive   = @{ $found->{alive} }   if ref $found->{alive} eq 'ARRAY';
      my @zombies = @{ $found->{zombies} } if ref $found->{zombies} eq 'ARRAY';

      foreach my $zombie ( grep { exists $pid_map{$_} } @zombies ) {
         $self->_set_job_state( $user, { id => $pid_map{$zombie}->{id}, state => 'zombie' } );
         $zombie_count++;
      }
      foreach my $life ( grep { exists $pid_map{$_} } @alive ) {
         if ( $pid_map{$life}->{state_id} != $self->job_states->{running} ) {
            $self->_set_job_state( $user, { id => $pid_map{$life}->{id}, state => 'running' } );
            $revived_count++;
         }
      }
   }
   return { success => 1, message => "$zombie_count zombies found $revived_count revived" };
}

# log related subroutines

sub read_log {
   my ( $self, $user, $d ) = @_;

   my $j = $self->_path_info( $user, $d->{name} );
   return { success => 0, message => 'cluster not found' } unless $j->{success};
   return { success => 0, message => 'job not found' }     unless $j->{job_id};

   my $job = $self->sqlite->db->select( 'job', ['server_id'], { id => $j->{job_id} } )->hash;
   return { success => 0, message => 'server not found' } unless $job->{server_id};

   my $log;
   if ( $d->{id} ) {
      $log = $self->sqlite->db->select( 'job_log', ['*'], { id => $d->{id} } )->hash;
   }
   else {
      $log = $self->sqlite->db->query("select * from job_log where job_id = $j->{job_id} order by id desc limit 1")->hash;
   }

   return { success => 0, message => 'log not found' }    unless $log->{id};
   return { success => 0, message => 'server not found' } unless $job->{server_id};

   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $job->{server_id} } );
      $ssh = $self->ssh_connection->{ $job->{server_id} };
   }
   $ssh = $self->ssh_connection->{ $job->{server_id} };
   return { success => 0, message => 'server unreachable' } unless $ssh && $ssh->check_master;

   my $o = "ordo_node/logs/out.$log->{job_id}.$log->{ppid}.$log->{log_id}.log";

   #my $e = "ordo_node/logs/err.$log->{job_id}.$log->{ppid}.$log->{log_id}.log";

   # TODO: change to cross-platform script

   #my ( $out, $err ) = $ssh->capture2("cat $o");

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
   my $path = $self->id2path( $user, { id => $job->{cluster_id} } );
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

   #my @units = split( /\s+/, $d->{name} );
   #return if scalar @units < 5 || scalar @units > 7;

   # convert unix cron to quartz cron
   #unshift( @units, '0' ) if scalar @units == 5;
   #if ( $units[3] =~ /\?/ ) {
   #   return if $units[5] =~ /\?/;
   #}
   #else {
   #   $units[5] = '?';
   #}

   #my $crontab = join( ' ', @units );

   my ( $cron_string, $begin, $expire, $english, $next );
   eval {
      my $cron = Cron::Toolkit->new(
         expression => $d->{name},
         time_zone  => $tz,
      );
      $cron->begin_epoch( $d->{begin} ) if $d->{begin};
      $cron->end_epoch( $d->{expire} )  if $d->{expire};
      $cron_string = $cron->as_string;
      $begin       = $cron->begin_epoch;
      $expire      = $cron->end_epoch;
      $english     = $cron->describe;
      $next        = $cron->next;
   };

   return if $@;
   return unless $next;

   my $id;
   eval {
      $id = $self->sqlite->db->insert(
         'cron',
         {
            name        => $cron_string,
            cal_id      => $d->{cal_id},
            begin       => $begin,
            expire      => $expire,
            description => $d->{description},
            english     => $english,
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
   return { success => 1, %$cron_row };
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

   my $cal = $self->sqlite->db->query("select cal.name from cron join cal on cron.cal_id = cal.id where cron.id = $d->{id}")->hash;
   my $rv  = $self->_delete_cron( $user, { id => $d->{id} } );
   return $rv ? { success => $rv, cal => $cal->{name} } : { success => 0, message => 'cron not found' };
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

   my $next;
   eval {
      my $cron = Cron::Toolkit->new(
         expression => $c->{name},
         time_zone  => $tz,
      );
      $cron->begin_epoch( $c->{begin} ) if $c->{begin};
      $cron->end_epoch( $c->{expire} )  if $c->{expire};
      $next = $cron->next;
   };
   return if $@;

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

   return { success => 0, message => 'invalid or an identical cron already exists in that calendar' } unless $id;

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
   return { success => $success, %$cal };
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
                                                                                 #state $ct   = qr/^((\S{1,12}\s+){4}(\S{1,12}\s+){0,2}(\S{1,12}\s*)|\s*)$/;    # cron
   state $ct   = qr/^((\S{1,12}\s+){4}(\S{1,12}\s+){0,2}(\S{1,12}\s*)|\s*)$/;    # cron
                                                                                 #state $ct = qr/./;
   state $at   = qr/^(\d+|\s*)$/;                                                # at
   state $cal  = qr/^(\w+|\s*)$/;                                                # cal
   state $flag = qr/^(\d+|\s*)$/;
   state $json = qr/^["',:\[\]\}\{\w]+$/;

   state %routing = (

      # path related
      'start_path'   => [ \&start_path,   1, [ {}, { name => $p, id => $i, force => $i } ] ],
      'kill_path'    => [ \&kill_path,    1, [ {}, { name => $p, id => $i } ] ],
      'read_path'    => [ \&read_path,    1, [ {}, { name => $p, id => $i } ] ],
      'hold_path'    => [ \&hold_path,    1, [ {}, { name => $p, id => $i } ] ],
      'release_path' => [ \&release_path, 1, [ {}, { name => $p, id => $i } ] ],
      'ice_path'     => [ \&ice_path,     1, [ {}, { name => $p, id => $i } ] ],
      'melt_path'    => [ \&melt_path,    1, [ {}, { name => $p, id => $i } ] ],
      'delete_path'  => [ \&delete_path,  1, [ {}, { name => $p, id => $i } ] ],

      # user related
      'create_user'   => [ \&create_user,   3, [ { name => $w }, { org_id => $i, email => $w, level => $i } ] ],
      'read_user'     => [ \&read_user,     0, [ {},             {} ] ],
      'update_user'   => [ \&update_user,   1, [ {},             { email => $e, name => $w } ] ],
      'delete_user'   => [ \&delete_user,   3, [ { id => $i }, {} ] ],
      'login_user'    => [ \&login_user,    0, [ { token => $w }, {} ] ],
      'new_token'     => [ \&new_token,     1, [ {}, {} ] ],
      'register_user' => [ \&register_user, 0, [ { email => $e }, {} ] ],

      # job related
      'create_job' => [
         \&create_job,
         1,
         [
            { name => $p, script => $c, server => $w },
            {
               needs       => 's',
               json        => $json,
               description => $d,
               retrys      => $i,
               loops       => $i,
               delay       => $i,
               script      => $c,
               needs_any   => 's',
               clonable    => $i,
               on_fail     => $i,
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
               name         => $p,
               json         => $json,
               id           => $i,
               signal       => $i,
               exit_code    => $i,
               server_id    => $i,
               mem          => $f,
               cpu          => $f,
               newname      => $w,
               state        => $w,
               server       => $w,
               ppid         => $i,
               pid          => $i,
               script       => $c,
               started      => $i,
               description  => $d,
               needs        => 's',
               ended        => $i,
               retrys       => $i,
               log_id       => $i,
               loops        => $i,
               delay        => $i,
               needs_any    => 's',
               on_fail      => $i,
               clonable     => $i,
               remove_needs => $i,
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
      'prune_job'    => [ \&prune_job,    1, [ {}, { name => $p, id => $i } ] ],
      'melt_job'     => [ \&melt_job,     1, [ {}, { name => $p, id => $i } ] ],
      'complete_job' => [ \&complete_job, 1, [ {}, { name => $p, id => $i } ] ],

      # cluster related
      'create_cluster' => [
         \&create_cluster,
         1,
         [
            { name => $p },
            {
               needs       => 's',
               json        => $json,
               mode        => $i,
               description => $d,
               cron        => $ct,
               at          => $at,
               cal         => $cal,
               cal_id      => $at,
               tz          => $p,
               clonable    => $i,
               mode        => $i,
               loops       => $i,
               needs_any   => 's',
               on_fail     => $i,
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
               id           => $i,
               name         => $p,
               needs        => 's',
               json         => $json,
               newname      => $w,
               description  => $d,
               cron         => $ct,
               at           => $at,
               cal          => $cal,
               cal_id       => $at,
               tz           => $p,
               mode         => $i,
               clonable     => $i,
               loops        => $i,
               needs_any    => 's',
               on_fail      => $i,
               remove_needs => $i,
            }
         ]
      ],
      'delete_cluster'   => [ \&delete_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'change_cluster'   => [ \&change_cluster,   1, [ {}, { name => $p, id   => $i } ] ],
      'find_cluster'     => [ \&find_cluster,     1, [ {}, { name => $p, id   => $i } ] ],
      'reset_cluster'    => [ \&reset_cluster,    1, [ {}, { name => $p, id   => $i } ] ],
      'start_cluster'    => [ \&start_cluster,    1, [ {}, { id   => $i, name => $p, force     => $i } ] ],
      'clone_cluster'    => [ \&clone_cluster,    1, [ {}, { id   => $i, name => $p, parent_id => $i } ] ],
      'ice_cluster'      => [ \&ice_cluster,      1, [ {}, { id   => $i, name => $p } ] ],
      'prune_cluster'    => [ \&prune_cluster,    1, [ {}, { id   => $i, name => $p } ] ],
      'melt_cluster'     => [ \&melt_cluster,     1, [ {}, { id   => $i, name => $p } ] ],
      'hold_cluster'     => [ \&hold_cluster,     1, [ {}, { id   => $i, name => $p } ] ],
      'kill_cluster'     => [ \&kill_cluster,     1, [ {}, { id   => $i, name => $p } ] ],
      'release_cluster'  => [ \&release_cluster,  1, [ {}, { id   => $i, name => $p } ] ],
      'complete_cluster' => [ \&complete_cluster, 1, [ {}, { id   => $i, name => $p } ] ],

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
      'find_log' => [ \&find_log, 1, [ {}, { name => $p, id => $i } ] ],
      'read_log' => [ \&read_log, 1, [ {}, { name => $p, id => $i, log => $i } ] ],

      # monitor related
      'create_monitor' => [
         \&create_monitor,
         1,
         [
            { name => $w, user => $w, host => $p },
            {
               password => $pw,
               port     => $i,
            }
         ]
      ],
      'find_monitor'   => [ \&find_monitor, 1, [ {}, { id => $i, name => $p } ] ],
      'read_monitor'   => [ \&read_monitor, 1, [ {}, { id => $i, name => $p } ] ],
      'update_monitor' => [
         \&update_monitor,
         1,
         [
            {},
            {
               id       => $i,
               name     => $p,
               user     => $w,
               host     => $p,
               password => $pw,
            }
         ]
      ],
      'delete_monitor'  => [ \&delete_monitor,  1, [ {},                                     { id       => $i, name => $p } ] ],
      'ssh_copy'        => [ \&ssh_copy,        1, [ { name => $w, user => $w, host => $p }, { password => $pw } ] ],
      'stop_monitor'    => [ \&stop_monitor,    1, [ {}, { id => $i, name => $p } ] ],
      'start_monitor'   => [ \&start_monitor,   1, [ {}, { id => $i, name => $p } ] ],
      'upgrade_monitor' => [ \&upgrade_monitor, 1, [ {}, { id => $i, name => $p } ] ],
      'active_pids'     => [ \&active_pids,     1, [ { id => $i }, {} ] ],
      'sync'            => [ \&sync,            1, [ {},           {} ] ],
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
