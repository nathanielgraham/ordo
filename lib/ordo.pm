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
use Email::MIME;
use Email::Sender::Simple;
use Email::Sender::Transport::SMTP;
use POSIX       qw(strftime);
use Time::Local qw(timelocal);
use ordo::MCP::Tools;
use Encode 'decode';
use Data::Dumper;

$ENV{EMAIL_SENDER_SMTP_USER} = 'nathanielgraham1@gmail.com';
$ENV{EMAIL_SENDER_SMTP_PASS} = 'sscy mwcr ybcg vxga';

# TODO: logs, time series stats, runtime alarms, state alarms, threshold alarms, eggs (lay, hatch, rezrov, blorb)
# TODO: add json column to cluster and job, and needs and needed env variables

$SIG{CHLD} = sub {
   1 while ( ( waitpid( -1, WNOHANG ) ) > 0 );
};

# Cache for documentation (documents change rarely)
has 'doc_cache' => sub {
   state $doc_cache = {};
};

has 'user' => sub {
   state $user = {};
};

has clients_by_org => sub {
   state $org = {};
};    # org_id => [ $tx1, $tx2, ... ]

has 'ssh_connection' => sub {
   state $ssh = {};
};

has 'cron' => sub {
   state $timer = {};
};

# pre-filter
has 'quartz_rx' => sub {
   state $quartz = qr{
  ^\s*
  (?:[A-Z0-9,\/\-\*\?\#LW]{1,11})            # field 1 (seconds)
  (?:\s+[A-Z0-9,\/\-\*\?\#LW]{1,11}){3,5}    # next 5 fields (minutes,hours,DOM,month,DOW)
  (?:\s+[A-Z0-9,\/\-\*\?\#LW]{1,11})         # optional year field
  \s*$
  }ix
};

has 'at' => sub {
   state $timer = {};
};

has 'local_url' => sub {
   state $url = 'http://' . &get_local_ip_address() . ':3000';
};

has 'last_warning_cache' => sub {
   state $cache = {};
   return $cache;
};

# This method will run once at server start
sub startup {

   my $self = shift;

   # Configure the application
   $self->secrets(
      [ 'gu$!$#UessM%#eI36#$fYo43@#$uC^%5an', '%!#GDA$#!gfds%#@sdf' ] );

   # In-memory storage for emails
   #$self->attr( emails => sub { {} } );

   # Add this to your main app class
   has 'last_warning_cache' => sub {
      state $cache = {};
      return $cache;
   };

   $self->_preload_documents();

   # Plugins
   $self->plugin( 'Minion' => { SQLite => "$Bin/../db/sqlite:minion.db" } );

#my $log = Mojo::Log->new(path => '/tmp/mojo.log', level => 'fatal'); # new log instance
#$self->log($log); # tell app to use new log instance

   # Helpers

   $self->helper(
      jwt => sub { Mojo::JWT->new( secret => shift->app->secrets->[0] || die ) }
   );

   #$self->helper(
   #   email => sub { shift->minion->enqueue( email_task => [@_] ) } );

# $self->helper( to_index => sub { shift->flash( message => shift )->redirect_to('index') } );

   $self->helper( request => \&request );
   $self->helper( routing => \&routing );

#$self->helper( sqlite  => sub { state $sql = Mojo::SQLite->new("$Bin/../db/ordo.db"); $sql->db->query('PRAGMA foreign_keys = ON;') } );

   $self->helper(
      sqlite => sub {
         state $sql = do {
            my $sqlite = Mojo::SQLite->new("$Bin/../db/ordo.db");
            $sqlite->db->query('PRAGMA foreign_keys = ON;');
            $sqlite->db->query('PRAGMA journal_mode = WAL;')
              ;    # concurrency + speed
            $sqlite->db->query('PRAGMA synchronous = NORMAL;'); # faster commits
            $sqlite->db->query('PRAGMA busy_timeout = 5000;')
              ;    # wait up to 5s on lock
            $sqlite->db->query('PRAGMA temp_store = MEMORY;')
              ;    # temp objects in RAM
            $sqlite->db->query('PRAGMA wal_autocheckpoint = 1000;')
              ;    # checkpoint after ~1 MB WAL
            $sqlite->db->query('PRAGMA cache_size = -20000;')
              ;    # 20 MB page cache
            $sqlite->db->query('PRAGMA foreign_keys = ON;'); # keep your setting
         };

         #$sql->db;
      }
   );

   state $states =
     $self->sqlite->db->select( 'job_states', ['*'] )->hashes->to_array;
   $self->helper(
      job_states => sub {
         state $states = { map { $_->{state}, $_->{id} } @{$states} };
      }
   );

   # Minion task
   #$self->minion->add_task(
   #   email_task => sub {
   #      my ( $job, @args ) = @_;
   #      eval { shift->app->send_email(@args); };
   #      if ($@) { $job->fail($@); }
   #   }
   #);

   # ==================== MINION EMAIL SETUP ====================
   # Minion Task - Background Email Sender
   $self->minion->add_task(
      email_task => sub {
         my ( $job, $to, $subject, $html_body, $plain_text ) = @_;

         $plain_text //= $html_body;

         eval {
            $job->app->send_email( $to, $subject, $html_body, $plain_text );
            $job->finish("Email sent to $to");
         } or do {
            my $error = $@ || 'Unknown error';
            $job->app->log->error("Minion email_task failed for $to: $error");
            $job->fail($error);
         };
      }
   );

   $self->helper(
      email => sub {
         my ( $c, $to, $subject, $html_body, $plain_text ) = @_;

         $c->minion->enqueue( 'email_task',
            [ $to, $subject, $html_body, $plain_text ] );

         $c->log->debug("Enqueued email to $to: $subject");
      }
   );

=pod
$self->helper(
   send_email => sub {
      my ($c, $to, $subject, $html_body, $plain_text) = @_;

      $plain_text //= $html_body;

      require Email::MIME;
      require Email::Sender::Simple;
      require Email::Sender::Transport::SMTP;

      my $transport = Email::Sender::Transport::SMTP->new({
         host          => 'smtp.gmail.com',
         port          => 587,
         ssl           => 'starttls',
         sasl_username => $ENV{EMAIL_SENDER_SMTP_USER},
         sasl_password => $ENV{EMAIL_SENDER_SMTP_PASS},
      });

      my $email = Email::MIME->create(
         header_str => [
            From    => 'Ordo Machinae <ordosched@proton.me>',
            To      => $to,
            Subject => $subject,
         ],
         parts => [
            # HTML version FIRST (preferred by modern clients)
            Email::MIME->create(
               attributes => {
                  content_type => 'text/html',
                  encoding     => 'quoted-printable',
                  charset      => 'UTF-8',
               },
               body => $html_body,
            ),
            # Plain text fallback
            Email::MIME->create(
               attributes => {
                  content_type => 'text/plain',
                  encoding     => 'quoted-printable',
                  charset      => 'UTF-8',
               },
               body => $plain_text,
            ),
         ],
      );

      eval {
         Email::Sender::Simple->send($email, { transport => $transport });
         $c->log->info("Email sent successfully to $to");
      } or do {
         $c->log->error("Failed to send email to $to: $@");
      };
   }
);
=cut

   $self->helper(
      send_email => sub {
         my ( $c, $to, $subject, $html_body, $plain_text ) = @_;

         $plain_text //= $html_body;

         require Email::MIME;
         require Email::Sender::Simple;
         require Email::Sender::Transport::Sendmail;

         my $transport = Email::Sender::Transport::Sendmail->new();

         my $email = Email::MIME->create(
            header_str => [
               From    => 'Ordo Machinae <ordosched@proton.me>',
               To      => $to,
               Subject => $subject,
            ],
            parts => [

               # HTML version first (preferred by modern clients)
               Email::MIME->create(
                  attributes => {
                     content_type => 'text/html',
                     encoding     => 'quoted-printable',
                     charset      => 'UTF-8',
                  },
                  body => $html_body,
               ),

               # Plain text fallback
               Email::MIME->create(
                  attributes => {
                     content_type => 'text/plain',
                     encoding     => 'quoted-printable',
                     charset      => 'UTF-8',
                  },
                  body => $plain_text,
               ),
            ],
         );

         eval {
            Email::Sender::Simple->send( $email, { transport => $transport } );
            $c->log->info("Email sent successfully to $to");
         } or do {
            $c->log->error("Failed to send email to $to: $@");
         };
      }
   );

   # Router
   my $r = $self->routes;

   $r->get('/terms')->to('pages#terms');
   $r->get('/privacy')->to('pages#privacy');

   # Login / Invite Route (reused for both)
   $r->post(
      '/login' => sub {
         my $c = shift;

         my $email       = $c->param('email') || '';
         my $team_member = $c->param('team_member') ? 1 : 0;    # ← New

         my $valid = Email::Valid->new;
         $valid->mxcheck(1);

         # Early validation
         unless ( $email && $valid->address($email) ) {
            return $c->render(
               json => {
                  success => 0,
                  message => 'Please enter a valid email address'
               }
            );
         }

         # Create user model

         #my $user_model = $c->app->_make_user( { email => $email } );

         my $user_model = ordo::Model::User->new(
             remote_address => $c->tx->remote_address
         );

         # Call register_user with team_member flag when needed
         my $result = $c->app->request(
            $user_model,
            {
               command     => 'register_user',
               email       => $email,
               team_member => $team_member       # ← Passed to register_user
            }
         );

         $c->render( json => $result );
      }
   );

   $r->get(
      '/logout' => sub {
         my $c = shift;
         $c->cookie( ordo_token => '', { expires => 1, path => '/' } );
         $c->redirect_to('/login');
      }
   );

   # Confirmation - Magic Link (works for both normal login and team invites)
   $r->get(
      '/confirm' => sub {
         my $c   = shift;
         my $jwt = $c->param('jwt');

         unless ($jwt) {
            $c->render( text => 'Missing confirmation link', status => 400 );
            return;
         }

         my $payload;
         eval { $payload = $c->jwt->decode($jwt); };

         if ( $@ || !$payload || !$payload->{email} ) {
            $c->render( text => 'Invalid or expired link', status => 400 );
            return;
         }

         my $email = $payload->{email};

         # Get or refresh user
         my $user = $c->app->_make_user( { email => $email } );
         unless ( $user && $user->id ) {
            $c->render( text => 'User not found', status => 404 );
            return;
         }

         # Auto-rotate token (security best practice)
         my $rotate_result = $c->app->new_token( $user, { id => $user->id } );
         my $token_to_use  = $rotate_result->{token} || $user->token;

         $c->sqlite->db->update( 'user', { level => 1 }, { id => $user->id } );

         # Set cookie
         $c->cookie(
            ordo_token => $token_to_use,
            {
               secure    => $c->req->is_secure,
               same_site => 'Lax',
               expires   => time + 10 * 365 * 24 * 3600,
               path      => '/',
            }
         );

         # Smart redirect
         if ( !$user->{update_time} || $user->{creation_time} > time - 86400 ) {
            $c->redirect_to('/#docs/quickstart');    # New user experience
         }
         else {
            $c->redirect_to('/#dashboard');
         }
      }
   );

   my $auth = $r->under(
      '/' => sub {
         my $c     = shift;
         my $token = $c->cookie('ordo_token');

         $c->app->log->debug(
            "Received cookie ordo_token: " . ( $token // 'MISSING' ) );

         #unless ($token) {
         #    $c->redirect_to('/login');
         #    return undef;
         #}

         my $user = $c->app->_make_user( { token => $token } );

         #  ordo::Model::User->new( remote_address => $c->tx->remote_address );
         my $res = $c->app->request( $user,
            { command => 'login_user', token => $token } );

         if ( $res && $res->{success} ) {
            return 1;
         }
         else {
            #$c->redirect_to('/login');
            return undef;
         }
      }
   );

   # Public SPA (anyone can load the HTML/JS)
   $r->get( '/app' => sub { shift->render( template => 'app' ); } );

   # Root redirects to public SPA
   $r->get( '/' => sub { shift->redirect_to('/app'); } );

   # MCP Connect Page
   $r->get(
      '/mcp_connect' => sub {
         my $c = shift;
         $c->render( template => 'mcp_connect' );
      }
   );

   # ==================== MCP CONNECTOR ====================

   my $tools = ordo::MCP::Tools->get_tools();

   $r->any(
      '/mcp' => sub {
         my $c = shift;

         my $json  = $c->req->json // {};
         my $token = $json->{token};

         unless ($token) {
            return $c->render(
               json => {
                  error   => 'Missing token in request body',
                  success => 0
               },
               status => 401
            );
         }

         # Authenticate
         #my $temp_user =
         #  ordo::Model::User->new( remote_address => $c->tx->remote_address, );

         my $mcp_user = $self->_make_user( { token => $token } );

         #my $auth = $c->app->request(
         #   $temp_user,
         #   {
         #      command => 'login_user',
         #      token   => $token
         #   }
         #);

         #unless ( $auth->{success} && ( $auth->{level} // 0 ) >= 1 ) {
         unless ( $mcp_user && ( $mcp_user->level // 0 ) >= 1 ) {
            return $c->render(
               json => {
                  error =>
                    'Unauthorized - valid token with level >= 1 required',
                  success => 0
               },
               status => 401
            );
         }

         #my $user = ordo::Model::User->new(
         #   id              => $auth->{user_id} || $auth->{id},
         #   level           => $auth->{level},
         #   org_id          => $auth->{org_id},
         #   token           => $auth->{token},
         #   remote_address  => $c->tx->remote_address,
         #   base_cluster_id => $auth->{base_cluster_id},
         #   root_cluster_id => $auth->{root_cluster_id},
         #);

         $c->stash( user => $mcp_user );

         # Discovery
         my $tool_name = $json->{tool} // $json->{method};

         if ( !$tool_name ) {
            my @tool_list = map {
               {
                  name        => $_,
                  description => $tools->{$_}{description} // 'No description',
                  params      => $tools->{$_}{params}      // {},
                  examples    => $tools->{$_}{examples}    // [],
               }
            } sort keys %$tools;

            return $c->render(
               json => {
                  success => 1,
                  message => 'Available MCP tools for Ordo',
                  tools   => \@tool_list
               }
            );
         }

         # Execute tool
         my $params = $json->{params} // $json->{arguments} // {};
         my $tool   = $tools->{$tool_name};

         my $result =
             $tool
           ? $tool->{handler}->( $c, $params )
           : { error => "Unknown tool: $tool_name", success => 0 };

         $c->render( json => $result );
      }
   );

   $r->websocket('/websocket')
     ->to( controller => 'websocket', action => 'default' );

   # API — token in JSON
   $r->post(
      '/api' => sub {
         my $c       = shift;
         my $json    = $c->req->json    || {};
         my $command = $json->{command} || '';
         my $token   = $json->{token}   || '';

         # ==================== PUBLIC REGISTRATION ====================
         # Only normal sign-up (no team_member flag) is allowed without auth
         if ( $command eq 'register_user' && !$json->{team_member} ) {
            my $temp_user = ordo::Model::User->new(
               remote_address => $c->tx->remote_address );
            my $res = $self->request( $temp_user, $json );
            $c->render( json => $res );
            return;
         }

         # ==================== ALL OTHER COMMANDS ====================
         # Require valid authenticated user (including team invites)
         my $user = undef;

         if ($token) {

            # Try execution token first
            $user = $self->_make_user( { execution_token => $token } );
         }

         if ( !$user && $token ) {

            # Then try normal API token
            $user = $self->_make_user( { token => $token } );
         }

         # No valid user → reject
         unless ( $user && $user->id ) {
            return $c->render(
               json => {
                  success => 0,
                  message => 'Unauthorized. Please log in.'
               },
               status => 401
            );
         }

         # Execute with authenticated user
         my $res = $self->request( $user, $json );
         $c->render( json => $res );
      }
   );

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
      $self->request( $user,
         { token => $u->{token}, command => 'login_user' } );

      my $servers = $self->sqlite->db->select( 'server', ['id'],
         { org_id => $u->{org_id} } );
      while ( my $server = $servers->hash ) {
         my $connection_ok =
           $self->_connect_ssh( $user, { id => $server->{id} } );
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
      my $jobs = $self->sqlite->db->select( 'job', ['*'],
         { state_id => { '=', [ ( $starting, $stopping ) ] } } );
      while ( my $job = $jobs->hash ) {
         $self->_set_job_state( $user,
            { id => $job->{id}, state => 'failed' } );
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
      my $count = $self->sqlite->db->query(
         "select count(*) as count from cluster where cal_id = $a->{cal_id}")
        ->hash->{count};
      next unless $count;
      my $user =
        ordo::Model::User->new( id => $a->{user_id}, org_id => $a->{org_id} );
      $self->request( $user,
         { token => $a->{token}, command => 'login_user' } );
      $self->_create_cron_object( $user, { id => $a->{cron_id} } );
   }
}

# HELPERS

sub check_and_send_usage_warning {
   my ( $self, $user, $used, $limit ) = @_;

   my $org_id = $user->org_id;

   return unless $org_id && $limit && $limit > 0;

   my $percent = int( ( $used / $limit ) * 100 );
   my $now     = time();
   my $cache   = $self->app->last_warning_cache;

   my @thresholds = (
      { key => '80',  percent => 80,  level => 'warning' },
      { key => '95',  percent => 95,  level => 'warning' },
      { key => '100', percent => 100, level => 'error' }
   );

   foreach my $t (@thresholds) {
      next unless $percent >= $t->{percent};

      my $last_sent = $cache->{$org_id}{ $t->{key} } || 0;

      if ( $now - $last_sent > 3600 ) {
         $self->send_usage_warning_broadcast(
            $user,
            {
               org_id        => $org_id,
               level         => $t->{level},
               usage_percent => $percent,
               used          => $used,
               limit         => $limit
            }
         );

         $cache->{$org_id}{ $t->{key} } = $now;
      }
      last;
   }
}

sub send_usage_warning_broadcast {
   my ( $self, $user, $args ) = @_;

   my $payload = {
      broadcast       => "usage_warning",
      level           => $args->{level},
      limit_type      => "monthly",
      usage_percent   => $args->{usage_percent},
      api_calls_used  => $args->{used},
      api_calls_limit => $args->{limit},
      message         => $self->build_usage_message(
         $args->{usage_percent},
         $args->{used}, $args->{limit}
      ),
      persistent => ( $args->{level} eq 'error' ) ? 1 : 0,
      timestamp  => time()
   };

   $self->_broadcast( $user, $payload );
}

sub build_usage_message {
   my ( $self, $percent, $used, $limit ) = @_;

   if ( $percent >= 100 ) {
      return "Monthly API limit exceeded. Some operations are now restricted.";
   }
   elsif ( $percent >= 95 ) {
      return "You're nearly at your monthly API limit (${percent}% used)";
   }
   else {
      return "You're approaching your monthly API limit (${percent}% used)";
   }
}

sub _make_user {
   my $self  = shift;
   my $where = shift;

   my $user = $self->sqlite->db->select( 'user', ['*'], $where )->hash;
   return unless $user->{id};

   my $org =
     $self->sqlite->db->select( 'org', ['*'], { id => $user->{org_id} } )->hash;

   my $u = ordo::Model::User->new(
      id                         => $user->{id},
      level                      => $user->{level},
      org_id                     => $user->{org_id},
      token                      => $user->{token},
      email                      => $user->{email},
      execution_token            => $user->{execution_token},
      base_cluster_id            => $user->{base_cluster_id},
      root_cluster_id            => $org->{root_cluster_id},
      monthly_call_limit         => $org->{monthly_call_limit},
      rate_limit_user_per_minute => $org->{rate_limit_user_per_minute},
      rate_limit_org_per_minute  => $org->{rate_limit_org_per_minute},
   );
   return $u;
}

sub _preload_documents {
   my $self = shift;
   my $base = $self->home->child('public/docs');

   my %summaries = (
      'overview' =>
        'Ordo is a hierarchical job scheduler with native MCP support...',
      'quickstart' =>
        'Step-by-step guide to create your first working workflow...',
      'core-concepts' => 'Explains fundamental concepts: Jobs vs Clusters...',
      'dashboard'     => 'Real-time view of job health, KPIs, live timers...',
      'jobs-and-clusters' =>
        'How to create, edit, and manage jobs and clusters...',
      'calendars-and-crons' =>
        'How to create and use Calendars with Quartz cron...',
      'settings'         => 'Account settings, Execution Token, API Token...',
      'connecting-to-ai' => 'How to connect Ordo to Grok via MCP...',
      'advanced-topics'  => 'Self-healing workflows, meta-automation...',
      'faq'              => 'Frequently asked questions about Ordo...',
   );

   my %full_docs;

   for my $sec ( keys %summaries ) {
      my $file = $base->child("$sec.md");
      print "FILE: $file\n";
      $full_docs{$sec} = -e $file
        ? decode( 'UTF-8', $file->slurp )

        #? $file->slurp->decode('UTF-8')
        : "Document not found: $sec.md";
   }

   $self->doc_cache->{summaries} = \%summaries;
   $self->doc_cache->{full}      = \%full_docs;
}

sub _is_execution_command {
   my ( $self, $command ) = @_;
   return $command eq 'update_job_state' || $command eq 'update_sysinfo';
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

sub validate_params {
   my ( $self, $required_types, $optional_types, $params ) = @_;

   my $clean = {};

   # 1. Check missing required parameters
   for my $key ( keys %$required_types ) {
      return ( 0, "missing required parameter: $key" )
        unless exists $params->{$key};
   }

   # 2. Check unknown parameters
   my %allowed = ( %$required_types, %$optional_types );
   for my $key ( keys %$params ) {
      return ( 0, "unknown parameter: $key" ) unless exists $allowed{$key};
   }

   # 3. Validate and clean each parameter
   for my $key ( keys %$params ) {
      my $value = $params->{$key};
      my $type  = $required_types->{$key} || $optional_types->{$key};

      if ( $type eq 's' ) {    # generic string
         $clean->{$key} = $value =~ s/^\s+|\s+$//gr;
      }
      elsif ( $type eq 'i' ) {    # integer
         return ( 0, "invalid integer for $key" ) unless $value =~ /^\d+$/;
         $clean->{$key} = $value + 0;
      }

      elsif ( $type eq 'i?' ) {   # nullable/optional integer (for detach/unset)
         if (  !defined $value
            || $value eq ''
            || $value eq 'undef'
            || $value eq 'null'
            || $value == 0 )
         {
            $clean->{$key} = undef;    # detach / unset
         }
         elsif ( $value =~ /^\d+$/ ) {
            $clean->{$key} = $value + 0;
         }
         else {
            return ( 0,
"invalid integer for $key (must be number or empty/0/null to detach)"
            );
         }
      }

      elsif ( $type eq 'pw' ) {    # password (e.g. for monitor SSH)
         return ( 0, "password must be 8–20 characters for $key" )
           unless length( $value // '' ) >= 8
           && length( $value // '' ) <= 20;
         $clean->{$key} =
           $value; # no trimming — preserve exact input (spaces/symbols allowed)
      }

      elsif ( $type eq 'n' )
      {            # name (job/cluster/cal/server) — allow slashes for /root
         return ( 0, "invalid name for $key" )
           unless $value =~ /^[\w\/\-_\.\s\&]{1,25}$/;
         $clean->{$key} = $value =~ s/^\s+|\s+$//gr;
      }
      elsif ( $type eq 'd' ) {    # description
         return ( 0, "description too long for $key" )
           if length $value > 2000;
         $clean->{$key} = $value =~ s/^\s+|\s+$//gr;
      }
      elsif ( $type eq 'p' ) {    # path
         return ( 0, "invalid path for $key" )
           unless $value =~ /^[\w\/\@\:\.\-]{1,200}$/;
         $clean->{$key} = $value =~ s/^\s+|\s+$//gr;
      }
      elsif ( $type eq 'c' ) {    # shell command
         return ( 0, "shell command too long for $key" )
           if length $value > 4000;
         $clean->{$key} =
           $value;    # preserve spaces — MUST be safely quoted in execution
      }
      elsif ( $type eq 'e' ) {    # email
         return ( 0, "invalid email for $key" )
           unless $value =~ /^[\w\.\-\+]+@[\w\.\-]+\.[a-zA-Z]{2,}$/;
         $clean->{$key} = lc( $value =~ s/^\s+|\s+$//gr );
      }
      elsif ( $type eq 'ct' ) {    # crontab (basic check)
         return ( 0, "invalid crontab for $key" )

           #unless $value =~ /^[\d\s\*\-\/,?L#]+$/;
           unless $value =~ $self->quartz_rx;
         $clean->{$key} = $value =~ s/^\s+|\s+$//gr;
      }
      elsif ( $type eq 'f' ) {     # float
         return ( 0, "invalid float for $key" )
           unless $value =~ /^[\d\.eE\-\+]+$/;
         $clean->{$key} = $value + 0.0;
      }
      elsif ( $type eq 'j' ) {     # JSON object
         eval { JSON::PP->new->decode($value) };
         return ( 0, "invalid JSON for $key" ) if $@;
         $clean->{$key} = $value;
      }
      elsif ( $type eq 'b' ) {     # boolean
         $clean->{$key} = !!$value;
      }
      elsif ( $type eq 'tz' ) {    # timezone
         return ( 0, "invalid timezone for $key" )
           unless $value =~ /^[\w\/\-+]{1,50}$/;
         $clean->{$key} = $value =~ s/^\s+|\s+$//gr;
      }

      elsif ( $type eq 'srv' ) {    # server name, host, IP address
                                    # Allow typical hostname, FQDN, IPv4, IPv6
         return ( 0, "invalid server identifier for $key" )
           unless $value =~ /^(?:
    [a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9](\.[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])*
    | \d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}
    | [a-fA-F0-9:]+
  )$/x;

         # Optional: trim and lowercase (for consistency)
         $clean->{$key} = lc( $value =~ s/^\s+|\s+$//gr );
      }
      elsif ( $type eq 'st' ) {
         my $valid_states =
           $self->sqlite->db->select( 'job_states', ['state'] )
           ->arrays->map( sub { $_->[0] } )->to_array;

#return (0, "invalid state for $key: '$value'") unless grep { $_ eq $value } @$valid_states;
         return ( 0, "invalid state for $key: '$value'" )
           unless exists $self->job_states->{$value};
         $clean->{$key} = $value;
      }

      elsif ( $type eq 'm' ) {    # mode (octal)
         return ( 0, "invalid mode for $key" ) unless $value =~ /^[0-7]{3}$/;
         $clean->{$key} = $value;
      }
      elsif ( $type eq 'sig' ) {    # signal
         return ( 0, "invalid signal for $key" )
           unless $value =~ /^(TERM|KILL|INT|HUP|USR1|USR2|\d{1,2})$/;
         $clean->{$key} = $value;
      }
      elsif ( $type =~ /^a:(.+)$/ ) {  # array with subtype (e.g. a:i, a:s, a:h)
         my $sub_type = $1;
         return ( 0, "invalid array for $key" ) unless ref $value eq 'ARRAY';
         return ( 0, "array too large for $key" ) if @$value > 1000;

         my @clean_array;
         for my $item (@$value) {
            if ( $sub_type eq 'h' ) {    # array of hashes (e.g. pids)
               return ( 0, "item in $key must be HASH" )
                 unless ref $item eq 'HASH';

               # Define expected PID hash structure
               my %pid_types = (
                  pid      => 'i',
                  ppid     => 'i',
                  priority => 'i',
                  pctcpu   => 'f',
                  pctmem   => 'f',
                  fname    => 'n',    # process name
                  start    => 's',    # 'N/A' or timestamp string
                                      # add more fields if needed
               );

               my ( $ok, $clean_item ) =
                 $self->validate_params( \%pid_types, {}, $item );
               return ( 0, "invalid PID hash item in $key" ) unless $ok;
               push @clean_array, $clean_item;
            }
            else {    # simple array (a:i, a:s, etc.)
               my ( $ok, $clean_item ) = $self->validate_params(
                  {},
                  { item => $sub_type },
                  { item => $item }
               );
               return ( 0, "invalid item in array $key" ) unless $ok;
               push @clean_array, $clean_item->{item};
            }
         }
         $clean->{$key} = \@clean_array;
      }
      else {
         return ( 0, "unknown validation type '$type' for $key" );
      }
   }

   return ( 1, $clean );
}

sub throttle_exceeded {
   my ( $self, $user ) = @_;

   my $minute = strftime( '%Y-%m-%d %H:%M', localtime );

   if ( exists $user->request_count->{$minute} ) {
      $user->request_count->{$minute}++;
   }
   else {
      $user->request_count->{$minute} = 1;
   }

   print "RCRL: "
     . $user->request_count->{$minute} . " "
     . $user->rate_limit_org_per_minute . " "
     . $user->rate_limit_user_per_minute . "\n";
   return 1
     if $user->request_count->{$minute} > $user->rate_limit_user_per_minute;
   return 0;
}

sub increment_usage {
   my ( $self, $user ) = @_;

   my $org_id = $user->org_id;
   return 0 unless $org_id;

   my $year_month = strftime( '%Y-%m', localtime );

   # Get current usage
   my $row = $self->sqlite->db->select( 'usage_counters', ['call_count'],
      { org_id => $org_id, year_month => $year_month } )->hash;

   my $current_count = $row->{call_count} || 0;

   # Check and send warnings (before incrementing)
   $self->check_and_send_usage_warning( $user, $current_count,
      $user->monthly_call_limit );

   # Enforce monthly limit
   if ( $current_count >= $user->monthly_call_limit ) {
      return 0;    # Limit exceeded
   }

   # Increment the counter
   $self->_increment_counter( $org_id, $year_month );

   return 1;
}

# Small helper to keep the main function readable
sub _increment_counter {
   my ( $self, $org_id, $year_month ) = @_;

   $self->sqlite->db->query(
      q{
        INSERT OR REPLACE INTO usage_counters
        (org_id, year_month, call_count, last_updated)
        VALUES (?, ?,
          COALESCE(
            (SELECT call_count FROM usage_counters
             WHERE org_id = ? AND year_month = ?),
            0
          ) + 1,
          CURRENT_TIMESTAMP
        )
      },
      $org_id, $year_month, $org_id, $year_month
   );
}

sub request {
   my ( $self, $user, $decoded ) = @_;
   my $response = {};
   die "Decoded must be HASH ref" unless $decoded && ref $decoded eq 'HASH';

   my $command = delete $decoded->{command};
   my $params  = {
      map  { $_ => $decoded->{$_} }
      grep { defined $decoded->{$_} } keys %$decoded
   };

   if ( exists $self->routing->{$command} ) {
      my $level = $user->level || 0;
      my ( $sub_name, $min_level, $legal_options, $count_usage ) =
        @{ $self->routing->{$command} };

      my ( $required_types, $optional_types ) = @{$legal_options};
      $optional_types->{token}      = 's';
      $optional_types->{tz}         = 'tz';
      $optional_types->{request_id} = 's';

      if ( $level < $min_level ) {
         $response->{success} = 0;
         $response->{message} = 'permission denied';
      }
      else {
         # ==================== VALIDATION ====================
         my ( $valid, $clean_params_or_error ) =
           $self->validate_params( $required_types, $optional_types, $params );

         if ( !$valid ) {
            $response = { success => 0, message => $clean_params_or_error };
         }
         else {
      # ==================== SPECIAL CASE: LOGIN / REGISTER ====================
            if (
               $command eq 'login_user'
               || ( $command eq 'register_user'
                  && !$clean_params_or_error->{team_member} )
              )
            {

               # Normal registration / magic login — keep open (no throttling)
               $response = $self->$sub_name( $user, $clean_params_or_error );

            }
            else {
# ==================== ALL OTHER COMMANDS + TEAM INVITES ====================
# Team invites (register_user with team_member=1) get throttled like normal commands

               my $user_id = $user->id;
               my $org_id  = $user->org_id;

               if (  $command ne 'update_job_state'
                  && $self->throttle_exceeded($user) )
               {
                  $self->log->warn(
"Rate limit hit for user $user_id / org $org_id (command $command)"
                  );
                  $response = {
                     success    => 0,
                     persistent => 1,
                     limit_type => 'rate',
                     message    =>
                       "Too many requests (wait a minute and try again)"
                  };
               }
               elsif ( $command ne 'update_job_state'
                  && $count_usage
                  && !$self->increment_usage($user) )
               {
                  $response = {
                     success    => 0,
                     persistent => 1,
                     limit_type => 'monthly',
                     message    => "Monthly API limit reached"
                  };
                  $self->log->warn(
"Monthly API limit hit for user $user_id / org $org_id (command $command)"
                  );
               }
               else {
                  # Execute command
                  $response = $self->$sub_name( $user, $clean_params_or_error );
               }
            }
         }
      }
   }
   else {
      $response = { success => 0, message => 'no such command' };
   }

   $response->{command_reply} = $command;
   return $response;
}

sub request2 {
   my ( $self, $user, $decoded ) = @_;
   my $response = {};

   die "Decoded must be HASH ref" unless $decoded && ref $decoded eq 'HASH';

   my $command = delete $decoded->{command};
   my $params  = {
      map  { $_ => $decoded->{$_} }
      grep { defined $decoded->{$_} } keys %$decoded
   };

   if ( exists $self->routing->{$command} ) {
      my $level = $user->level || 0;
      my ( $sub_name, $min_level, $legal_options, $count_usage ) =
        @{ $self->routing->{$command} };
      my ( $required_types, $optional_types ) = @{$legal_options};

      $optional_types->{token}      = 's';
      $optional_types->{tz}         = 'tz';
      $optional_types->{request_id} = 's';

      if ( $level < $min_level ) {
         $response->{success} = 0;
         $response->{message} = 'permission denied';
      }
      else {
         # ==================== VALIDATION ====================
         my ( $valid, $clean_params_or_error ) =
           $self->validate_params( $required_types, $optional_types, $params );

         if ( !$valid ) {
            $response = { success => 0, message => $clean_params_or_error };
         }
         else {
        # ==================== SPECIAL CASE: SKIP FOR LOGIN ====================
            if ( $command eq 'login_user' || $command eq 'register_user' ) {

               # Skip throttling/logging for login (low-impact auth command)
               $response = $self->$sub_name( $user, $clean_params_or_error );
            }
            else {
               # ==================== NORMAL COMMANDS ====================

               # Throttle (always apply, even for non-counted commands)
               my $user_id = $user->id;
               my $org_id  = $user->org_id;
               if (  $command ne 'update_job_state'
                  && $self->throttle_exceeded($user) )
               {
                  $self->log->warn(
"Rate limit hit for user $user_id / org $org_id (command $command)"
                  );
                  $response = {
                     success    => 0,
                     persistent => 1,
                     limit_type => 'rate',
                     message    =>
                       "Too many requests (wait a minute and try again)"
                  };
               }
               elsif ( $command ne 'update_job_state'
                  && $count_usage
                  && !$self->increment_usage($user) )
               {
                  $response = {
                     success    => 0,
                     persistent => 1,
                     limit_type => 'monthly',
                     message    => "Monthly API limit reached"
                  };
                  $self->log->warn(
"Monthly API limit hit for user $user_id / org $org_id (command $command)"
                  );
               }
               else {
                  # Execute as method
                  $response = $self->$sub_name( $user, $clean_params_or_error );
               }
            }
         }
      }
   }
   else {
      $response = { success => 0, message => 'no such command' };
   }

   $response->{command_reply} = $command;
   return $response;
}

# cluster related subroutines

sub _cluster_info {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id} || $self->path2id( $user, $d->{name} );

   return unless $cluster_id;
   my $org_id = $user->org_id;

   my $sql = <<~"SQL";
      select c.*, js.state as jobstate, cal.name as cal_name
      from cluster c 
      join job_states js on c.state_id = js.id
      left join cal on c.cal_id = cal.id
      where c.id = $cluster_id
      and c.org_id = $org_id
   SQL

   my $cluster = $self->sqlite->db->query($sql)->hash;

   my $needs_ids = $self->sqlite->db->query(
"SELECT needs_cluster_id FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 0",
      $cluster->{id}
   )->hashes->to_array;
   my $needs_any_ids = $self->sqlite->db->query(
"SELECT needs_cluster_id FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 1",
      $cluster->{id}
   )->hashes->to_array;

   $cluster->{needs_ids} = [ map { $_->{needs_cluster_id} } @$needs_ids ];
   $cluster->{needs_any_ids} =
     [ map { $_->{needs_cluster_id} } @$needs_any_ids ];
   $cluster->{next_start} =
     $self->_cal_next_start( $user, { id => $cluster->{cal_id} } )
     if $cluster->{cal_id};

#my $needs_ids = $self->sqlite->db->query( "SELECT needs_cluster_id FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 0", $d->{id} )->hashes->to_array;
#my $needs_any_ids = $self->sqlite->db->query( "SELECT needs_cluster_id FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 1", $d->{id} )->hashes->to_array;
#$cluster->{needs_ids} = map { $_->{id} } @$needs_ids;
#$cluster->{needs_any_ids} = map { $_->{id} } @$needs_any_ids;
#$cluster->{jobs} = $self->_find_jobs( $user, { cluster_id => $cluster->{id} } );

#$cluster->{needs}  = $self->_read_cluster_needs( $user, { id => $cluster->{id} } );
#$cluster->{next_start} = $self->_cal_next_start( $user, { id => $cluster->{cal_id} } ) if $cluster->{cal_id};
#my $cluster = $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id, org_id => $user->org_id } )->hash;
   return $cluster;
}

sub read_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_read_cluster( $user, $d );
   $cluster->{success} = $cluster->{id} ? 1 : 0;
   return $cluster;
}

sub _read_cluster {
   my ( $self, $user, $d ) = @_;

   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

#my $needs_ids = $self->sqlite->db->query( "SELECT needs_cluster_id FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 0", $cluster->{id} )->hashes->to_array;
#my $needs_any_ids = $self->sqlite->db->query( "SELECT needs_cluster_id FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 1", $cluster->{id} )->hashes->to_array;

#$cluster->{needs_ids} = [ map { $_->{needs_cluster_id} } @$needs_ids ];
#$cluster->{needs_any_ids} = [ map { $_->{needs_cluster_id} } @$needs_any_ids ];
   $cluster->{jobs} =
     $self->_find_jobs( $user, { cluster_id => $cluster->{id} } );

#$cluster->{next_start} = $self->_cal_next_start( $user, { id => $cluster->{cal_id} } ) if $cluster->{cal_id};

   return $cluster;
}

sub _set_cluster_state {
   my ( $self, $user, $d ) = @_;

   my $LOOP = 0;

   # id state
   my $cluster =
     $self->sqlite->db->select( 'cluster', ['*'], { id => $d->{id} } )->hash;
   return unless $cluster && $cluster->{id};

   my $cluster_id = $cluster->{id};

   return if $cluster->{state_id} == $self->job_states->{immutable};

   my $update_hash = {};

   if ( $d->{state} && $self->job_states->{ $d->{state} } ) {
      return if $self->job_states->{ $d->{state} } == $cluster->{state_id};
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
   }

   my $killed = $self->job_states->{killed};
   my $failed = $self->job_states->{failed};
   my $zombie = $self->job_states->{zombie};

   if ( $d->{state} eq 'running' ) {
      return 1 if $cluster->{state_id} == $self->job_states->{running};
      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      # Set parent cluster to running if no failed/killed/zombie children
      my $j = $self->sqlite->db->select(
         'job',
         ['id'],
         {
            cluster_id => $cluster->{parent_id},
            state_id   => { '=', [ ( $killed, $failed, $zombie ) ] }
         }
      );
      my $c = $self->sqlite->db->select(
         'cluster',
         ['*'],
         {
            parent_id => $cluster->{parent_id},
            id        => { '!=', $cluster_id },
            state_id  => { '=',  [ ( $killed, $failed, $zombie ) ] }
         }
      );
      unless ( $j->hash || $c->hash ) {
         $self->_set_cluster_state( $user,
            { state => 'running', id => $cluster->{parent_id} } )
           if $cluster->{parent_id};
      }
   }
   elsif (
      scalar(
         grep { $d->{state} eq $_ } (qw(complete ice_complete pruned_complete))
      )
     )
   {
      $update_hash->{state_id} = $self->job_states->{complete}
        if $d->{state} eq 'pruned_complete';

      if ( $d->{state} eq 'complete' ) {

         # Handle looping
         if (  $cluster->{loops}
            && $cluster->{loops} > $cluster->{loop_count} )
         {
            my $loop_count = $cluster->{loop_count} || 0;
            $loop_count++;
            $self->sqlite->db->update(
               'cluster',
               {
                  loop_count => $loop_count,
                  state_id   => $self->job_states->{looping}
               },
               { id => $cluster_id }
            );
            $LOOP = 1;
         }
      }

      $update_hash->{ended} = time;

      # Update cluster with any pending changes
      $self->sqlite->db->update( 'cluster', $update_hash,
         { id => $cluster_id } )
        if scalar keys %$update_hash;

      # Complete parent if possible
      if ( $cluster->{parent_id}
         && $self->_cluster_is_complete( $user,
            { id => $cluster->{parent_id} } ) )
      {
         $self->_set_cluster_state( $user,
            { state => 'complete', id => $cluster->{parent_id} } );
      }

      # Trigger dependent clusters
      my $complete = $self->job_states->{complete};
      my $pruned   = $self->job_states->{pruned};
      my $waiting  = $self->job_states->{waiting};
      my $ready    = $self->job_states->{ready};
      my $ice      = $self->job_states->{ice};

      my $depends_sql = <<~"SQL";
         SELECT cn.cluster_id AS id
         FROM cluster_needs cn
         JOIN cluster c ON cn.cluster_id = c.id
         WHERE cn.needs_cluster_id = $cluster_id
           AND c.state_id IN ($ready, $waiting, $ice, $pruned)
      SQL

      my $cneed = $self->sqlite->db->query($depends_sql);
      while ( my $c = $cneed->hash ) {
         if ( $self->_cluster_needs_met( $user, { id => $c->{id} } ) ) {
            $self->_start_cluster( $user,
               { id => $c->{id}, origin => 'auto', noreset => 1 } );
         }
      }

      # Handle clone deletion
      if ( $cluster->{clone_cluster_id} ) {
         $self->delete_cluster( $user, { id => $cluster_id } );
      }
   }
   elsif ( $d->{state} eq 'failed' || $d->{state} eq 'killed' ) {
      $update_hash->{ended} = time;

      # Fail parent cluster
      if (  $cluster->{parent_id}
         && $cluster->{parent_id} != $user->root_cluster_id )
      {
         $self->_set_cluster_state( $user,
            { id => $cluster->{parent_id}, state => 'failed' } );
      }

      # On-fail alarm
      if ( $cluster->{on_fail_id} && $d->{state} eq 'failed' ) {
         my $fail_cluster = $self->sqlite->db->select( 'cluster', ['id'],
            { id => $cluster->{on_fail_id} } )->hash;
         if ( $fail_cluster->{id} ) {
            $self->_start_cluster( $user,
               { id => $fail_cluster->{id}, origin => 'fail', force => 1 } );
         }
      }
   }
   elsif ( $d->{state} eq 'ready' || $d->{state} eq 'waiting' ) {
      $update_hash->{json}    = undef;
      $update_hash->{started} = undef;
      $update_hash->{ended}   = undef;
   }

   # Final update if needed
   if ( $update_hash->{state_id} ) {
      $self->sqlite->db->update( 'cluster', $update_hash,
         { id => $cluster_id } );
      $self->_broadcast_cluster( $user, [$cluster_id] );
   }

   if ($LOOP) {
      $self->_reset_cluster( $user, { id => $cluster_id } );
      $self->_start_cluster(
         $user,
         {
            id        => $cluster_id,
            origin    => 'loop',
            origin_id => $cluster_id
         }
      );
   }

   return 1;
}

sub _broadcast {
   my ( $self, $user, $payload ) = @_;
   my $org_id = $user->org_id;
   return
     unless $payload && $user->org_id && $self->app->clients_by_org->{$org_id};
   for my $client_tx ( @{ $self->app->clients_by_org->{$org_id} } ) {
      next if $client_tx->is_finished;
      $client_tx->send( { json => $payload } );
   }
}

sub _broadcast_cluster {
   my ( $self, $user, $ids ) = @_;
   $self->_broadcast_any( $user, $ids, 'cluster' );
}

sub _broadcast_job {
   my ( $self, $user, $ids ) = @_;
   $self->_broadcast_any( $user, $ids, 'job' );
}

sub _broadcast_server {
   my ( $self, $user, $ids ) = @_;
   $self->_broadcast_any( $user, $ids, 'server' );
}

sub _broadcast_cal {
   my ( $self, $user, $ids ) = @_;
   $self->_broadcast_any( $user, $ids, 'cal' );
}

sub _broadcast_org {
   my ( $self, $user ) = @_;
   my $payload = $self->_org_info($user);
   $payload->{broadcast} = 'org_changed';
   $self->_broadcast( $user, $payload );
}

sub _broadcast_any {
   my ( $self, $user, $ids, $type ) = @_;
   return
        unless $type
     && $self->app->clients_by_org->{ $user->org_id }
     && scalar @{$ids};
   my $payload = {
      broadcast => $type . 's_changed',
      updates   => [],
      deletes   => [],
   };
   my $method =
     $type eq 'cal'
     ? '_read_cal'
     : $type eq 'cluster' ? '_cluster_info'

     #: $type eq 'cluster' ? '_read_cluster'
     : ( '_' . $type . '_info' );
   for my $id ( @{$ids} ) {
      my $thing = $self->$method( $user, { id => $id } );

      #my $cluster = $self->_cluster_info( $user, { id => $cluster_id } );
      if ( $thing->{id} ) {
         push @{ $payload->{updates} }, $thing;
      }
      else {
         push @{ $payload->{deletes} }, { id => $id };
      }
   }
   $self->_broadcast( $user, $payload );
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
      $self->_set_cluster_state( $user,
         { id => $cluster_id, state => 'ice_complete' } );
      return { success => 0, skipped => 1, message => 'cluster on ice' };
   }
   elsif ( $cluster->{clonable}
      && $cluster->{state_id} == $self->job_states->{running} )
   {
      my $response = $self->clone_cluster( $user, { id => $cluster_id } );
      return $response unless $response->{success} && $response->{clone_id};
      $self->_broadcast_cluster( $user, [ $response->{clone_id} ] );
      return $self->_start_cluster( $user,
         { id => $response->{clone_id}, force => 1 } );
   }
   elsif ( $cluster->{state_id} == $self->job_states->{running} ) {
      return { success => 0, message => 'cluster already running' };
   }

   unless ( $self->_cluster_needs_met( $user, { id => $cluster->{id} } ) ) {

#print "NEEDS: " . $self->_cluster_needs_met( $user, { id => $cluster->{id} } ) . "\n";
      return { success => 0, waiting => 1, message => 'dependency not met.' };
   }

   #unless ( $d->{force} ) {

#   if ( $cluster->{next_start} && $d->{origin} ne 'cron' ) {
#      return { success => 0, waiting => 1, message => 'expecting cron start. use --force to start anyway' };
#   }

# prevent cluster from running if needs not met
#if ( !$self->_cluster_needs_met( $user, { id => $cluster->{id} } ) ) {
#return { success => 0, waiting => 1, message => "dependency not met. use --force to start anyway" };
#}
#}

   unless ( $d->{origin} && $d->{origin} eq 'loop' ) {
      $self->sqlite->db->update(
         'cluster',
         { loop_count => 0 },
         { id         => $cluster->{id} }
      );
   }

   $self->_reset_cluster( $user, { id => $cluster_id } ) unless $d->{noreset};
   $self->_set_cluster_state( $user,
      { state => 'running', id => $cluster_id } );

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
      my $rv = $self->_start_cluster( $user,
         { id => $c->{id}, origin => 'auto', noreset => 1 } );
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
      $self->_set_cluster_state( $user,
         { state => 'failed', id => $cluster_id } );
      return {
         success => 0,
         failed  => 1,
         message => "cluster $cluster_id failed"
      };
   }
   elsif ( $jobs_waiting || $clusters_waiting ) {
      $self->_set_cluster_state( $user,
         { state => 'waiting', id => $cluster_id } );
      my $message = "cluster started.";
      $message .= " $clusters_waiting clusters waiting." if $clusters_waiting;
      $message .= " $jobs_waiting jobs waiting."         if $jobs_waiting;
      return { success => 1, waiting => 1, message => $message };
   }
   elsif ( $self->_cluster_is_complete( $user, { id => $cluster_id } ) ) {
      $self->_set_cluster_state( $user,
         { state => 'complete', id => $cluster_id } );
      return {
         success   => 1,
         completed => 1,
         message   => "cluster $cluster_id complete"
      };
   }
   else {
      return {
         success => 1,
         started => 1,
         message => "cluster $cluster_id started"
      };
   }
}

sub _reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster_info = $self->read_cluster( $user, $d );
   my $cluster_id   = $cluster_info->{id};

   return unless $cluster_id;

   my $servers = $self->sqlite->db->query(
      "select distinct(server_id) from job where cluster_id = $cluster_id");
   while ( my $s = $servers->hash ) {
      $self->_sync_server( $user, { id => $s->{id} } );
   }

   if ( $cluster_info->{state_id} == $self->job_states->{running}
      && !$self->_cluster_is_complete( $user, { id => $cluster_id } ) )
   {
      return;
   }

   my $pruned = $self->job_states->{pruned};
   my $hold   = $self->job_states->{hold};
   my $ice    = $self->job_states->{ice};

   my $job_select     = { cluster_id => $cluster_id };
   my $cluster_select = { parent_id  => $cluster_id };

   unless ( $d->{all} ) {
      $job_select->{state_id} =
        { '!=', [ -and => ( $hold, $ice, $pruned ) ] };
      $cluster_select->{state_id} =
        { '!=', [ -and => ( $hold, $ice, $pruned ) ] };
   }

   my $needs = $self->_read_cluster_needs( $user, { id => $cluster_id } );
   my $cluster_state =
     $cluster_info->{next_start} || scalar keys %$needs ? 'waiting' : 'ready';

   # set cluster state to ready or waiting
   $self->_set_cluster_state( $user,
      { id => $cluster_id, state => $cluster_state } );

   my $jobs = $self->sqlite->db->select( 'job', ['*'], $job_select );
   while ( my $job = $jobs->hash ) {

#next if scalar( grep { $job->{state_id} == $self->job_states->{$_} } (qw(running watching)) );
#next if $job->{pid} || $job->{ppid};
      my $needs     = $self->_read_job_needs( $user, { id => $job->{id} } );
      my $job_state = scalar keys %$needs ? 'waiting' : 'ready';
      $self->_set_job_state( $user, { id => $job->{id}, state => $job_state } );
   }

   # reset descendent clusters
   my $clusters =
     $self->sqlite->db->select( 'cluster', ['id'], $cluster_select );
   while ( my $cluster = $clusters->hash ) {
      $self->_reset_cluster( $user,
         { id => $cluster->{id}, all => $d->{all} } );
   }

   return 1;
}

sub reset_cluster {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_reset_cluster( $user, $d );
   return $rv
     ? { success => 1 }
     : { success => 0, message => 'cluster is running' };
}

sub find_cluster {
   my ( $self, $user, $d ) = @_;

   my $cluster = $self->_read_cluster( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my @clusters;
   push @clusters, $cluster;

   my $find_clusters = sub {
      my $id     = shift;
      my $org_id = $user->org_id;

      my $children = $self->sqlite->db->select(
         'cluster', ['id'],
         { parent_id => $id, org_id => $user->org_id },
         { order_by  => 'id' }
      );

      while ( my $c = $children->hash ) {
         my $child = $self->_read_cluster( $user, { id => $c->{id} } );
         push @clusters, $child;
         __SUB__->( $c->{id} );
      }
      return;
   };

   $find_clusters->( $cluster->{id} );
   return scalar @clusters
     ? { success => 1, clusters => \@clusters }
     : { success => 0, message  => 'no clusters found' };
}

sub update_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );

   return $cluster unless $cluster->{id};
   my $cluster_id = $cluster->{id};

   return { success => 0, message => 'cluster not found' } unless $cluster_id;

   my ( $needs_ids, $needs_any_ids, $on_fail_id );

   if ( $d->{needs_ids} ) {
      $needs_ids = $self->_filter_cluster_ids( $user, $d->{needs_ids} );
   }
   elsif ( $d->{needs} ) {
      $needs_ids = $self->_resolve_cluster_ids( $user, $d->{needs} );
   }
   if ( $d->{needs_any_ids} ) {
      $needs_any_ids = $self->_filter_cluster_ids( $user, $d->{needs_any_ids} );
   }
   elsif ( $d->{needs_any} ) {
      $needs_any_ids = $self->_resolve_cluster_ids( $user, $d->{needs_any} );
   }
   if ( $d->{on_fail_id} ) {
      $on_fail_id =
        shift @{ $self->_filter_cluster_ids( $user, [ $d->{on_fail_id} ] ) };
   }
   elsif ( $d->{on_fail} ) {
      $on_fail_id =
        shift @{ $self->_resolve_cluster_ids( $user, [ $d->{on_fail} ] ) };
   }

   my $update_hash = {
      map  { $_, $d->{$_} }
      grep { exists $d->{$_} } (qw(mode description loops clonable))
   };

   $update_hash->{name} = $d->{newname} if $d->{newname};
   $update_hash->{on_fail_id} =
       $on_fail_id && $on_fail_id != $cluster_id
     ? $on_fail_id
     : undef;

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

   eval {
      #my $tx = $self->sqlite->db->begin;
      if ( scalar keys %{$update_hash} ) {
         $self->sqlite->db->update( 'cluster', $update_hash,
            { id => $cluster_id } );
      }
      if ( $needs_ids || $needs_any_ids ) {
         $self->_write_cluster_needs(
            $user,
            {
               needs_all => $needs_ids,
               needs_any => $needs_any_ids,
               id        => $cluster_id,
            }
         );
      }

      if ( $d->{remove_needs} ) {
         $self->sqlite->db->delete( 'cluster_needs',
            { cluster_id => $cluster_id } )
           if $d->{remove_needs};
      }

      if ( exists $d->{cal_id} || exists $d->{cal} ) {
         my $new_cal =
           $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
         my $new_cal_id = $new_cal->{id} ? $new_cal->{id} : undef;
         die
           unless $self->_set_cluster_cal_id( $user,
            { cluster_id => $cluster_id, cal_id => $new_cal_id } );
      }
      elsif ( exists $d->{cron} || exists $d->{at} ) {
         if ( $d->{cron} ) {
            $self->_add_cluster_cron( $user,
               { id => $cluster_id, tz => $d->{tz}, cron => $d->{cron} } )
              or die;
         }
         elsif ( $d->{at} ) {
            $self->_add_cluster_cron( $user,
               { id => $cluster_id, tz => $d->{tz}, at => $d->{at} } )
              or die;
         }
         else {
            $self->_set_cluster_cal_id( $user,
               { cluster_id => $cluster_id, cal_id => undef } )
              or die;
         }
      }

      #$tx->commit;
   };

   if ($@) {
      return { success => 0, message => $@ } if $@;
   }
   else {
      $self->_broadcast_cluster( $user, [$cluster_id] );
      return { success => 1, message => 'cluster updated' };
   }
}

sub delete_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );
   return $cluster if $cluster->{success} == 0;

   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};
   return { success => 0, message => 'root cluster cannot be deleted' }
     if $user->root_cluster_id == $cluster->{id};

   # delete cluster and all descendants

   my $clusters =
     $self->find_cluster( $user, { id => $cluster->{id} } )->{clusters};
   push @{$clusters}, $cluster;

   my $delete_count = 0;
   foreach my $c ( @{$clusters} ) {

      # delete jobs
      my $jobs =
        $self->sqlite->db->select( 'job', ['*'], { cluster_id => $c->{id} } );
      while ( my $j = $jobs->hash ) {
         my $rv = $self->delete_job( $user, { id => $j->{id}, force => 1 } );
      }

      # delete cluster
      my $rows =
        $self->sqlite->db->delete( 'cluster', { id => $c->{id} } )->rows;
      $delete_count += $rows;
      next unless $c->{cal_id};

      # calendar cleanup
      my $count = $self->sqlite->db->query(
         "select count(*) as count from cluster where cal_id = $c->{cal_id}")
        ->hash->{count};
      if ( $count == 0 ) {

         # stop cal if no clusters subscribed
         $self->_stop_cal( $user, { id => $c->{cal_id} } );

         # delete cal if it has no name
         $self->sqlite->db->delete( 'cal',
            { name => undef, id => $c->{cal_id}, org_id => $user->org_id } );
      }
   }
   if ($delete_count) {
      $self->_broadcast_cluster( $user, [ map { $_->{id} } @{$clusters} ] );
      return { success => 1, deleted => $delete_count };
   }
   else {
      return { success => 0 };
   }
}

sub create_cluster {
   my ( $self, $user, $d ) = @_;

   my ( $parent_id, $name );
   if ( $d->{parent_id} ) {
      $parent_id = $d->{parent_id};
      $name      = $d->{name};
   }
   else {
      my $p = $self->_path_info( $user, $d->{name} );
      return { success => 0, message => 'cluster not found' }
        unless $p->{success};
      return { success => 0, message => 'a job by that name already exists' }
        if $p->{job_id};
      return { success => 0, message => 'a cluster by that name exists' }
        if $p->{cluster_id};
      $parent_id = $p->{parent_cluster_id};
      $name      = $p->{name};
   }

 #my $cluster = $self->read_cluster( $user, { id => $p->{parent_cluster_id} } );
   my $parent_cluster = $self->read_cluster( $user, { id => $parent_id } );

   return { success => 0, message => 'parent cluster not found' }
     unless $parent_cluster->{id};

   my ( $needs_ids, $needs_any_ids, $on_fail_id );

   if ( $d->{needs_ids} ) {
      $needs_ids = $self->_filter_cluster_ids( $user, $d->{needs_ids} );
   }
   elsif ( $d->{needs} ) {
      $needs_ids = $self->_resolve_cluster_ids( $user, $d->{needs} );
   }
   if ( $d->{needs_any_ids} ) {
      $needs_any_ids = $self->_filter_cluster_ids( $user, $d->{needs_any_ids} );
   }
   elsif ( $d->{needs_any} ) {
      $needs_any_ids = $self->_resolve_cluster_ids( $user, $d->{needs_any} );
   }
   if ( $d->{on_fail_id} ) {
      $on_fail_id =
        shift @{ $self->_filter_cluster_ids( $user, [ $d->{on_fail_id} ] ) };
   }
   elsif ( $d->{on_fail} ) {
      $on_fail_id =
        shift @{ $self->_resolve_cluster_ids( $user, [ $d->{on_fail} ] ) };
   }

   my $insert_hash = {
      org_id    => $user->org_id,
      user_id   => $user->id,
      parent_id => $parent_id,
      name      => $name,
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

   $insert_hash->{mode} =
       $d->{mode}    ? $d->{mode}
     : $user->{mode} ? $user->{mode}
     :                 770;

   my $id;
   eval {
      $id =
        $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id;
   };
   return { success => 0, message => 'unknown error' } if $@;

 #my $id = $self->sqlite->db->insert( 'cluster', $insert_hash )->last_insert_id;

   if ( $needs_ids || $needs_any_ids ) {
      $self->_write_cluster_needs(
         $user,
         {
            needs_all => $needs_ids,
            needs_any => $needs_any_ids,
            id        => $id,
         }
      );
   }

   if ( $d->{cron} || $d->{at} ) {
      my $rv = $self->_add_cluster_cron( $user,
         { id => $id, tz => $d->{tz}, cron => $d->{cron}, at => $d->{at} } );
   }
   if ($id) {
      $self->_broadcast_cluster( $user, [$id] );
      return { success => 1, id => $id, message => "new cluster created" };
   }
   else {
      return { success => 0, "error creating cluster" };
   }
}

# shortcut to add a cal+cron directly to a cluster
sub _add_cluster_cron {
   my ( $self, $user, $d ) = @_;

   # id (cluster) tz cron at

   return unless $d->{cron} || $d->{at};

   my $cluster = $self->sqlite->db->select(
      'cluster',
      [ 'id', 'cal_id' ],
      { id => $d->{id}, org_id => $user->org_id }
   )->hash;
   my $cluster_id = $cluster->{id};
   my $cal_id     = $cluster->{cal_id};

   my $tz = $d->{tz} || 'UTC';
   eval {
      my $tx = $self->sqlite->db->begin;

      my $cal_id = $self->_create_cal( $user,
         { tz => $tz, description => "calendar for cluster_id $cluster_id" } );
      die unless $cal_id;

      my $rv =
          $d->{cron}
        ? $self->_add_cron( $user, { name => $d->{cron}, cal_id => $cal_id } )
        : $d->{at}
        ? $self->_add_at( $user, { name => $d->{at}, cal_id => $cal_id } )
        : { success => 0 };

      die unless $rv->{success};
      my $success = $self->_set_cluster_cal_id( $user,
         { cluster_id => $cluster_id, cal_id => $cal_id } );
      die unless $success;
      $tx->commit;
   };
   return $@ ? 0 : 1;
}

sub change_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->read_cluster( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $cluster_id = $cluster->{id};

# 0 = not found, undef = root cluster
#return { success => 0, message => 'unable to locate cluster' } if defined $cluster_id && $cluster_id == 0;
   return { success => 0, message => 'unable to locate cluster' }
     unless $cluster_id;

   my $fullpath  = $self->id2path( $user, { id => $cluster_id } );
   my $user_info = $self->read_user($user);
   eval {
      $self->sqlite->db->update(
         'user',
         { base_cluster_id => $cluster_id },
         { id              => $user_info->{id} }
      );
   };
   my $success = $@ ? 0 : 1;
   return {
      path       => $fullpath,
      cluster_id => $cluster_id,
      success    => $success
   };
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
      my $c =
        $self->sqlite->db->select( 'cluster', ['id'],
         { parent_id => $parent_id, name => $part, org_id => $user->org_id } )
        ->hash;

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

   my $cluster =
     $self->sqlite->db->select( 'cluster', ['id'], { id => $d->{id} } )->hash;
   my $cluster_id = $cluster->{id};

   my @names;
   my $count = 0;

   while ( defined $cluster_id ) {
      my $c =
        $self->sqlite->db->select( 'cluster', ['*'], { id => $cluster_id } )
        ->hash;

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

   my $results =
     $self->sqlite->db->select( 'user', ['*'], { token => $d->{token} } )->hash;

   my $org =
     $self->sqlite->db->select( 'org', ['*'], { id => $results->{org_id} } )
     ->hash;

   my $team = $self->sqlite->db->select( 'user', [qw(id email level)],
      { org_id => $results->{org_id} } )->hashes->to_array;

   my ( $message, $success, $path );
   my $host  = hostname()        || get_local_ip_address();
   my $login = $results->{email} || $results->{id};

   if ( $results->{id} ) {
      $self->sqlite->db->update(
         'user',
         { update_time => time },
         { id          => $results->{id} }
      );

      $user->id( $results->{id} );
      $user->level( $results->{level} );
      $user->org_id( $results->{org_id} );
      $user->token( $results->{token} );
      $user->execution_token( $results->{execution_token} );
      $user->base_cluster_id( $results->{base_cluster_id} );
      $user->root_cluster_id( $org->{root_cluster_id} );
      $user->monthly_call_limit( $org->{monthly_call_limit} );
      $user->rate_limit_user_per_minute( $org->{rate_limit_user_per_minute} );
      $user->rate_limit_org_per_minute( $org->{rate_limit_org_per_minute} );
      $user->email( $results->{email} );
      $user->team($team);
      $path    = $self->id2path( $user, { id => $results->{base_cluster_id} } );
      $message = 'login success';
      $success = 1;
   }
   else {
      $message = 'login failed';
      $success = 0;
   }
   return {
      message         => $message,
      success         => $success,
      email           => $login,
      id              => $results->{id},
      org_id          => $results->{org_id},
      remote_address  => $results->{remote_address},
      token           => $results->{token},
      host            => $host,
      path            => $path,
      level           => $results->{level},
      base_cluster_id => $results->{base_cluster_id},
      root_cluster_id => $org->{root_cluster_id},
   };
}

sub register_user {
   my ( $self, $user, $d ) = @_;

   my $valid = Email::Valid->new;
   $valid->mxcheck(1);

   unless ( $d->{email} && $valid->address( $d->{email} ) ) {
      return { success => 0, message => 'Invalid email address' };
   }

   my $email          = lc( $d->{email} );
   my $is_team_invite = $d->{team_member} ? 1 : 0;

   my $existing_user =
     $self->sqlite->db->select( 'user', ['*'], { email => $email } )->hash;

   if ($existing_user) {

      # Block invite to user in a different org
      if ( $is_team_invite && $existing_user->{org_id} != $user->org_id ) {
         return {
            success => 0,
            message =>
              "This email is already registered with a different organization. "
              . "They must use a different email address to join your team."
         };
      }

      # Existing user in same org -> just send magic link (re-login)
      $d->{level} = 0;
   }
   else {
      # New user
      $d->{level} = 0;

      if ( $is_team_invite && $user && $user->org_id ) {
         $d->{org_id} = $user->org_id;
      }
   }

   # ==================== ONLY CREATE IF NEW USER ====================
   my $result;
   if ($existing_user) {
      $result = { success => 1 };    # Skip create_user for existing users
   }
   else {
      $result = $self->create_user( $user, $d );
      return $result unless $result->{success};
   }

   # ============================================================

   # Generate JWT
   my $exp_seconds = $is_team_invite ? 24 * 3600 : 900;    # 24h vs 15min
   my $jwt         = $self->jwt->claims(
      {
         email => $email,
         exp   => time() + $exp_seconds
      }
   )->encode;

   my $url = $self->local_url . $self->url_for('confirm')->query( jwt => $jwt );

   # Choose email template
   my ( $html_body, $plain_text ) =
       $is_team_invite
     ? $self->_fetch_invite( $user, $email, $url )
     : $self->_fetch_reg( $user, $email, $url );

   $self->email( $email,
      $is_team_invite ? 'Ordo Team Invitation' : 'Ordo Magic Login Link',
      $html_body, $plain_text );

   return {
      success => 1,
      message => $is_team_invite
      ? "Invitation sent successfully to $email"
      : "Magic login link sent to $email"
   };
}

sub _fetch_reg {
   my ( $self, $user, $email, $url ) = @_;

   my $html_body = <<~"HTML";
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Arial, sans-serif; background:#0f0f1f; color:#e0e0e0; padding:20px;">
  <div style="max-width:600px; margin:0 auto; background:#1a1a1a; padding:30px; border-radius:8px;">
    <h2>Welcome to Ordo Machinae</h2>
   
    <p>Please click the button below to sign in:</p>
   
    <p style="margin:30px 0;">
      <a href="$url"
         style="background:#00ffcc; color:#000; padding:16px 32px;
                text-decoration:none; border-radius:6px; font-weight:bold; display:inline-block;">
        Sign in to Ordo
      </a>
    </p>
    <p>This link will expire in 15 minutes.</p>
    <p>
      By signing in, you agree to our
      <a href="https://ordoscheduler.com/terms">Terms of Service</a>
      and
      <a href="https://ordoscheduler.com/privacy">Privacy Policy</a>.
    </p>
    <p>If you didnt request this link, please ignore this email.</p>
  </div>
</body>
</html>
HTML

   my $plain_text = <<~"TEXT";
Welcome to Ordo Machinae!

Please click the link below to sign in:
$url

This link will expire in 15 minutes.

By signing in, you agree to our:
- Terms of Service: https://ordoscheduler.com/terms
- Privacy Policy: https://ordoscheduler.com/privacy

If you didnt request this, please ignore this email.

-- The Ordo Team
TEXT

   return ( $html_body, $plain_text );
}

sub _fetch_invite {
   my ( $self, $inviter, $email, $url ) = @_;

   my $inviter_name =
     $inviter && $inviter->email ? $inviter->email : "a team member";

   my $html_body = <<~"HTML";
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Arial, sans-serif; background:#0f0f1f; color:#e0e0e0; padding:20px;">
  <div style="max-width:600px; margin:0 auto; background:#1a1a1a; padding:30px; border-radius:8px;">
    
    <h2>Youve been invited to Ordo</h2>
    
    <p>$inviter_name has invited you to join their organization on Ordo.</p>
    
    <p>Ordo is a modern AI-native job scheduler for teams and power users.</p>
    
    <p style="margin:35px 0;">
      <a href="$url" 
         style="background:#00ffcc; color:#000; padding:16px 36px; 
                text-decoration:none; border-radius:6px; font-weight:bold; 
                display:inline-block; font-size:17px;">
        Accept Invitation
      </a>
    </p>
    
    <p>This invitation link will expire in 24 hours.</p>
    
    <p>
      By accepting, you agree to our 
      <a href="https://ordoscheduler.com/terms">Terms of Service</a> 
      and 
      <a href="https://ordoscheduler.com/privacy">Privacy Policy</a>.
    </p>
    
    <p>If you werent expecting this invitation, you can safely ignore this email.</p>
    
    <p>-- The Ordo Team</p>
  </div>
</body>
</html>
HTML

   my $plain_text = <<~"TEXT";
Youve been invited to Ordo

$inviter_name has invited you to join their organization.

Ordo is a modern AI-native job scheduler.

Accept the invitation here:
$url

This link will expire in 24 hours.

By accepting, you agree to our Terms of Service and Privacy Policy:
https://ordoscheduler.com/terms
https://ordoscheduler.com/privacy

If you werent expecting this invitation, you can safely ignore this email.

-- The Ordo Team
TEXT

   return ( $html_body, $plain_text );
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
   my ( $user_id, $api_token, $exec_token, $org_id );

   eval {
      my $tx = $db->begin;

      # create org
      if ( $d->{team_member} ) {
         $org_id = $user->org_id;
      }
      else {
         $org_id = $db->query("INSERT INTO org DEFAULT VALUES")->last_insert_id;
         die "unable to create org" unless $org_id;

         #my $exec_token = $self->_new_token();
         #$db->update(
         #   'org',
         #   {
         #      execution_token            => $exec_token,
         #      execution_token_created_at => time()
         #   },
         #   { id => $org_id }
         #);
      }

      # create root cluster
      my $root_id;

      my $root = $db->select( 'cluster', ['id'],
         { org_id => $org_id, name => 'root', parent_id => undef } )->hash;
      if ( $root->{id} ) {
         $root_id = $root->{id};
      }
      else {
         $root_id = $db->insert(
            'cluster',
            {
               org_id   => $org_id,
               name     => 'root',
               state_id => $self->job_states->{immutable}
            }
         )->last_insert_id;
      }

      die "unable to create root cluster" unless $root_id;

      $api_token                      = $self->_new_token();
      $exec_token                     = $self->_new_token();
      $user_insert->{token}           = $api_token;
      $user_insert->{execution_token} = $exec_token;
      $user_insert->{org_id}          = $org_id;
      $user_insert->{base_cluster_id} = $root_id;
      $user_id = $db->insert( 'user', $user_insert )->last_insert_id;
      die unless $user_id;

      $db->update( 'org', { root_cluster_id => $root_id }, { id => $org_id } );

      #$db->update( 'cluster', { user_id => $user_id }, { id => $root_id } );
      $tx->commit;
   };

   if ($@) {
      return { message => $@, success => 0 };
   }
   else {
      return {
         success => 1,
         id      => $user_id,
         token   => $api_token,
         message => "user $user_id created"
      };
   }
}

sub rotate_execution_token {
   my ( $self, $user, $d ) = @_;
   my $token = $self->_new_token();

   $self->sqlite->db->update(
      'user',
      { execution_token => $token },
      { id              => $user->id }
   )->hash;

   return {
      success => 1,
      token   => $token,
      message => 'New exec token generated'
   };
}

sub new_token {
   my ( $self, $user, $d ) = @_;
   my $user_id = $d->{id} || $user->id;
   my $token   = $self->_new_token();
   $self->sqlite->db->update( 'user', { token => $token }, { id => $user_id } )
     ->hash;

   return { success => 1, token => $token, message => 'New token generated' };
}

sub _new_token {
   my $uuid  = create_uuid_as_string();
   my $token = hmac_sha1_hex($uuid);
   return $token;
}

sub read_user {
   my ( $self, $user ) = @_;
   my $me    = $self->_user_info( $user, { id => $user->id } );
   my $group = $self->sqlite->db->select(
      'user',
      [
         qw(id email org_id level remote_address update_time creation_time mode name)
      ],
      { org_id => $user->org_id, id => { '!=', $user->id } }
   )->hashes->to_array;
   my $org =
     $self->sqlite->db->select( 'org', ['*'], { id => $user->org_id } )->hash;
   $me->{group} = $group;
   $me->{org}   = $org;
   return $me;

   #return $self->_user_info($user, { id => $user->id } );
}

sub _user_info {
   my ( $self, $user, $d ) = @_;

   my $info =
     $self->sqlite->db->select( 'user', ['*'], { id => $d->{id} } )->hash;
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
      update_time     => $info->{update_time},
      creation_time   => $info->{creation_time},
      success         => 1,
   };
}

sub update_user {
   my ( $self, $user, $d ) = @_;
   my $update_hash =
     { map { $_, $d->{$_} } grep { exists $d->{$_} } qw(mode name) };
   eval {
      $self->sqlite->db->update( 'user', $update_hash, { id => $user->id } )
        ->hash;
   };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

sub read_org {
   my ( $self, $user, $d ) = @_;
   my $org     = $self->_org_info($user);
   my $success = $org->{id} ? 1 : 0;
   return { success => $success, %$org };
}

sub _org_info {
   my ( $self, $user ) = @_;
   my $org =
     $self->sqlite->db->select( 'org', ['*'], { id => $user->org_id } )->hash;
   $org->{members} = $self->sqlite->db->select( 'user', [qw(id email level)],
      { org_id => $user->org_id } )->hashes->to_array;
   $org->{api_calls_reset_date} =
     timelocal( 0, 0, 0, 1, (localtime)[4] + 2, (localtime)[5] );
   my $org_id = $user->org_id;

   my $sql = <<~"SQL";
     select max(year_month) as current_month_year, call_count from usage_counters where org_id = $org_id
   SQL

   my $usage = $self->sqlite->db->query($sql)->hash;
   $org->{api_calls_this_month} = $usage->{call_count};
   $org->{current_month_year}   = $usage->{current_month_year};

   my $server_count = $self->sqlite->db->query(
      "select count(*) as count from server where org_id = $org_id")
     ->hash->{count};
   $org->{server_count} = $server_count;
   return $org;
}

sub update_org {
   my ( $self, $user, $d ) = @_;
   return $self->_update_org( $user, $d );
}

sub _update_org {
   my ( $self, $user, $d ) = @_;
   my $update_hash =
     { map { $_, $d->{$_} } grep { exists $d->{$_} } qw(name description) };
   eval {
      $self->sqlite->db->update( 'org', $update_hash, { id => $user->org_id } )
        ->hash;
   };
   my $success = $@ ? 0 : 1;
   return { success => $success };
}

sub delete_user {
   my ( $self, $user, $d ) = @_;
   my $rows;
   $rows = $self->sqlite->db->delete( 'user', { id => $d->{id} } )->rows;

   #return { success => 0, message => 'user not found' } unless $rows;
   return { success => 1, message => 'Your account has been deleted' };
}

sub delete_me {
   my ( $self, $user ) = @_;
   return $self->delete_user( $user, { id => $user->id } );
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
   my $job               = $self->sqlite->db->select( 'job', ['id'],
      { cluster_id => $parent_cluster_id, name => $name } )->hash;

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

   my $needs_ids = $self->sqlite->db->query(
"SELECT needs_job_id FROM job_needs WHERE job_id = ? AND needs_any_mode = 0",
      $job_id
   )->hashes->to_array;
   my $needs_any_ids = $self->sqlite->db->query(
"SELECT needs_job_id FROM job_needs WHERE job_id = ? AND needs_any_mode = 1",
      $job_id
   )->hashes->to_array;
   $job->{needs_ids}     = [ map { $_->{needs_job_id} } @$needs_ids ];
   $job->{needs_any_ids} = [ map { $_->{needs_job_id} } @$needs_any_ids ];

   return $job;
}

sub _find_jobs {
   my ( $self, $user, $d ) = @_;
   my $org_id = $user->org_id;

   return { success => 0 } unless $d->{cluster_id};

   my @jobs;
   my $jobs = $self->sqlite->db->select(
      'job', ['id'],
      { cluster_id => $d->{cluster_id} },
      { order_by   => 'id' }
   );
   while ( my $job = $jobs->hash ) {
      my $j = $self->_job_info( $user, { id => $job->{id} } );
      push @jobs, $j if $j->{id};
   }

   return \@jobs;
}

sub clone_cluster {
   my ( $self, $user, $d ) = @_;

   # id name parent_id

   my $cluster = $self->_cluster_info( $user, $d );

   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $parent_id = $d->{parent_id} || $cluster->{parent_id};

   my $clone_id = $self->_clone_cluster( $user,
      { id => $cluster->{id}, parent_id => $parent_id, origin => 1 } );

   return $clone_id
     ? { success => 1, clone_id => $clone_id }
     : { success => 0 };
}

sub _clone_cluster {
   my ( $self, $user, $d ) = @_;

   # id name parent_id

   my $running = $self->job_states->{running};
   my $cluster = $self->sqlite->db->select( 'cluster', ['*'],
      { id => $d->{id}, org_id => $user->org_id } )->hash;

   return unless $cluster->{id};

   state ( %job_map, %cluster_map );
   my $name;
   if ( $d->{origin} ) {
      $name = delete $cluster->{name};
   }

   $cluster->{parent_id}        = $d->{parent_id} || $cluster->{parent_id};
   $cluster->{clone_cluster_id} = delete $cluster->{id};
   $cluster->{clonable}         = undef;
   unless (
      scalar(
         grep { $cluster->{state_id} == $self->job_states->{$_} } (qw(hold ice))
      )
     )
   {
      $cluster->{state_id} = $self->job_states->{ready};
   }

   my $cluster_id;
   eval {
      #my $tx = $self->sqlite->db->begin;
      $cluster_id =
        $self->sqlite->db->insert( 'cluster', $cluster )->last_insert_id;
      if ( $d->{origin} ) {
         my $new_name = $name .= "_$cluster_id";
         $self->sqlite->db->update(
            'cluster',
            { name => $new_name },
            { id   => $cluster_id }
         );
      }

      $cluster_map{ $cluster->{clone_cluster_id} } = $cluster_id;

      my $jobs = $self->sqlite->db->select(
         'job', ['*'],
         { cluster_id => $cluster->{clone_cluster_id} },
         { order_by   => 'id' }
      );
      while ( my $job = $jobs->hash ) {
         $job->{clone_job_id} = delete $job->{id};
         $job->{cluster_id}   = $cluster_id;

         unless (
            scalar(
               grep { $job->{state_id} == $self->job_states->{$_} }
                 (qw(hold ice))
            )
           )
         {
            $job->{state_id} = $self->job_states->{ready};
         }

         my $job_id = $self->sqlite->db->insert( 'job', $job )->last_insert_id;
         $self->_reset_job_stats( $user, { id => $job_id } );

         $job_map{ $job->{clone_job_id} } = $job_id;
      }

      #$self->_reset_cluster( $user, { id => $cluster_id } );

      # clone child clusters
      my $children = $self->sqlite->db->select(
         'cluster', ['id'],
         { parent_id => $cluster->{clone_cluster_id} },
         { order_by  => 'id' }
      );
      while ( my $child = $children->hash ) {
         $self->_clone_cluster( $user,
            { id => $child->{id}, parent_id => $cluster_id } )
           if $child->{id};
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
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $jobs = $self->sqlite->db->select( 'job', ['id'],
      { cluster_id => $cluster->{id} } );
   while ( my $job = $jobs->hash ) {
      $self->_hard_kill_job( $user, { id => $job->{id} } );
   }

   $self->_set_cluster_state( $user,
      { id => $cluster->{id}, state => 'killed' } );

   # stop descendent clusters
   my $child_clusters = $self->sqlite->db->select( 'cluster', ['id'],
      { parent_id => $cluster->{id} } );
   while ( my $child_cluster = $child_clusters->hash ) {
      $self->kill_cluster( $user, { id => $child_cluster->{id} } );
   }

   return { success => 1 };
}

sub hold_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} }
      (qw(starting running immutable)) )
   {
      return { success => 0, message => 'unable to hold cluster' };
   }

   # hold cluster
   $self->_set_cluster_state( $user,
      { id => $cluster->{id}, state => 'hold' } );

   # hold child jobs
   my $jobs = $self->sqlite->db->select(
      'job',
      ['id'],
      {
         cluster_id => $cluster->{id},
         state_id   => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'hold' } );
   }

   # hold child clusters
   my $children = $self->sqlite->db->select(
      'cluster',
      ['id'],
      {
         parent_id => $cluster->{id},
         state_id  => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $child = $children->hash ) {
      $self->hold_cluster( $user, { id => $child->{id}, state => 'hold' } );

   #$self->_set_cluster_state( $user, { id => $child->{id}, state => 'hold' } );
   }

   return { success => 1 };
}

sub complete_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} }
      (qw(running immutable)) )
   {

      #if ( !$self->_cluster_is_complete( $user, { id => $cluster->{id} } ) ) {
      return { success => 0, message => 'unable to complete cluster' };
   }

   # complete cluster
   $self->_set_cluster_state( $user,
      { id => $cluster->{id}, state => 'complete' } );

   # complete child jobs
   my @job_ids;
   my $jobs = $self->sqlite->db->select(
      'job',
      ['id'],
      {
         cluster_id => $cluster->{id},
         state_id   => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $job = $jobs->hash ) {
      $self->sqlite->db->update(
         'job',
         { state_id => $self->job_states->{complete} },
         { id       => $job->{id} }
      );
      push( @job_ids, $job->{id} );

    # $self->_set_job_state( $user, { id => $job->{id}, state => 'complete' } );
   }
   $self->_broadcast_job( $user, [@job_ids] ) if scalar @job_ids;

   # complete child clusters
   my $children = $self->sqlite->db->select(
      'cluster',
      ['id'],
      {
         parent_id => $cluster->{id},
         state_id  => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $child = $children->hash ) {
      $self->complete_cluster( $user,
         { id => $child->{id}, state => 'complete' } );

   #$self->_set_cluster_state( $user, { id => $child->{id}, state => 'hold' } );
   }

   return { success => 1 };
}

sub release_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};
   return { success => 0, message => 'cluster not on hold' }
     unless $cluster->{state_id} == $self->job_states->{hold};

   my $hold = $self->job_states->{hold};

   # release cluster
   $self->_reset_cluster( $user, { id => $cluster->{id}, all => 1 } );

   # start cluster if parent is running
   my $parent = $self->sqlite->db->select( 'cluster', ['state_id'],
      { id => $cluster->{parent_id} } )->hash;

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
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} }
      (qw(starting running immutable)) )
   {
      return { success => 0, message => 'cluster cannot be iced' };
   }

   # ice cluster
   $self->_set_cluster_state( $user, { id => $cluster->{id}, state => 'ice' } );

   # ice child jobs
   my $jobs = $self->sqlite->db->select(
      'job',
      ['id'],
      {
         cluster_id => $cluster->{id},
         state_id   => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'ice' } );
   }

   # ice child clusters
   my $children = $self->sqlite->db->select(
      'cluster',
      ['id'],
      {
         parent_id => $cluster->{id},
         state_id  => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $child = $children->hash ) {
      $self->ice_cluster( $user, { id => $child->{id}, state => 'ice' } );
   }
   return { success => 1 };
}

sub prune_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};

   my $running = $self->job_states->{running};

   if ( grep { $self->job_states->{$_} == $cluster->{state_id} }
      (qw(starting running immutable)) )
   {
      return { success => 0, message => 'cluster cannot be pruned' };
   }

   # prune cluster
   $self->_set_cluster_state( $user,
      { id => $cluster->{id}, state => 'pruned' } );

   # prune child jobs
   my $jobs = $self->sqlite->db->select(
      'job',
      ['id'],
      {
         cluster_id => $cluster->{id},
         state_id   => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $job = $jobs->hash ) {
      $self->_set_job_state( $user, { id => $job->{id}, state => 'pruned' } );
   }

   # prune child clusters
   my $children = $self->sqlite->db->select(
      'cluster',
      ['id'],
      {
         parent_id => $cluster->{id},
         state_id  => { '!=', [ -and => ($running) ] }
      }
   );
   while ( my $child = $children->hash ) {
      $self->prune_cluster( $user, { id => $child->{id}, state => 'prune' } );
   }
   return { success => 1 };
}

sub melt_cluster {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_cluster_info( $user, $d );
   return { success => 0, message => 'cluster not found' }
     unless $cluster->{id};
   return { success => 0, message => 'cluster not on ice' }
     unless $cluster->{state_id} == $self->job_states->{ice};

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

   my $parent_id;
   if ( $d->{parent_id} ) {
      $parent_id = $d->{parent_id};
   }
   else {
      my $j = $self->_path_info( $user, $d->{name} );
      return { success => 0, message => 'cluster not found' }
        unless $j->{success};
      return { success => 0, message => 'a job by that name already exists' }
        if $j->{job_id};
      return { success => 0, message => 'a cluster by that name exists' }
        if $j->{cluster_id};
      return {
         success => 0,
         message => 'jobs not allowed in the root cluster'
        }
        if $user->root_cluster_id == $j->{parent_cluster_id};
      $parent_id = $j->{parent_cluster_id};
   }

   my ( $needs_ids, $needs_any_ids, $on_fail_id );

   if ( $d->{needs_ids} ) {
      $needs_ids = $self->_filter_job_ids( $user, $d->{needs_ids} );
   }
   elsif ( $d->{needs} ) {
      $needs_ids = $self->_resolve_job_ids( $user, $d->{needs} );
   }
   if ( $d->{needs_any_ids} ) {
      $needs_any_ids = $self->_filter_job_ids( $user, $d->{needs_any_ids} );
   }
   elsif ( $d->{needs_any} ) {
      $needs_any_ids = $self->_resolve_job_ids( $user, $d->{needs_any} );
   }
   if ( $d->{on_fail_id} ) {
      $on_fail_id =
        shift @{ $self->_filter_job_ids( $user, [ $d->{on_fail_id} ] ) };
   }
   elsif ( $d->{on_fail} ) {
      $on_fail_id =
        shift @{ $self->_resolve_job_ids( $user, [ $d->{on_fail} ] ) };
   }

   my $insert_hash = { cluster_id => $parent_id, name => $d->{name} };
   $insert_hash->{delay} = $d->{delay} if $d->{delay} && $d->{delay} <= 86400;

   my @fields = qw(retrys loops delay state_id description started ended);

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

   $insert_hash->{on_fail_id} = $on_fail_id if $on_fail_id;

   if ( $d->{script} ) {
      $insert_hash->{script} = $d->{script};
   }

   if ( $d->{server_id} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'],
         { id => $d->{server_id}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' }
        unless $res->{id};
      $insert_hash->{server_id} = $res->{id};
   }
   elsif ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'],
         { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' }
        unless $res->{id};
      $insert_hash->{server_id} = $res->{id};
   }
   my $id;
   eval {
      $id = $self->sqlite->db->insert( 'job', $insert_hash )->last_insert_id;
   };

   if ($@) {
      return { success => 0, message => $@ };
   }
   $self->_write_job_needs(
      $user,
      {
         needs_all  => $needs_ids,
         needs_any  => $needs_any_ids,
         id         => $id,
         cluster_id => $parent_id
      }
   );

   $self->_broadcast_job( $user, [$id] );
   return {
      success    => 1,
      id         => $id,
      cluster_id => $parent_id,
      message    => "new job created in cluster id $parent_id"
   };
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
         return {
            success => 0,
            message => 'job running. use --force to delete anyway'
         };
      }
   }

   $self->_hard_kill_job( $user, { id => $job->{id} } )
     unless $job->{state_id} == $self->job_states->{watching};
   $self->sqlite->db->delete( 'job', { id => $job->{id} } );

# if no jobs left in the cluster, set cluster state to ready and de-link it from any calendar
   my $count = $self->sqlite->db->query(
      "select count(*) as count from job where cluster_id = $job->{cluster_id}")
     ->hash->{count};
   unless ($count) {
      $self->_set_cluster_cal_id( $user,
         { cluster_id => $job->{cluster_id}, cal_id => undef } );
      $self->_set_cluster_state( $user,
         { id => $job->{cluster_id}, state => 'ready' } );
   }
   $self->_broadcast_job( $user, [ $job->{id} ] );
   return { success => 1, id => $job->{id} };
}

sub unwatch_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'not a watcher job' }
     unless $job->{state_id} == $self->job_states->{watching};
   return $self->delete_job( $user, { id => $job->{id} } );
}

sub melt_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   return { success => 0, message => 'job not on ice' }
     unless $job->{state_id} == $self->job_states->{ice};

#eval { $self->sqlite->db->update( 'job', { state_id => $self->job_states->{ready} }, { id => $job->{id} } ); };
   $self->_set_job_state( $user, { state => 'ready', id => $job->{id} } );
   return { success => 1 };

   #if ($@) {
   #   return { success => 0, message => $@ };
   #}
   #return { success => 1 };
}

sub ice_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};

#return { success => 0, message => 'job is running' } if $job->{state_id} == $self->job_states->{running};

   if (
      scalar(
         grep { $self->job_states->{$_} == $job->{state_id} }
           (qw(starting running immutable))
      )
     )
   {
      return { success => 0, message => 'job cannot be iced' };
   }

   $self->_set_job_state( $user, { state => 'ice', id => $job->{id} } );
   return { success => 1 };
}

sub prune_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};

   if (
      scalar(
         grep { $self->job_states->{$_} == $job->{state_id} }
           (qw(starting running immutable))
      )
     )
   {
      return { success => 0, message => 'job cannot be pruned' };
   }

   $self->_set_job_state( $user, { state => 'pruned', id => $job->{id} } );
   return { success => 1 };
}

sub release_job {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};
   return { success => 0, message => 'job not on hold' }
     unless $job->{state_id} == $self->job_states->{hold};

   $self->_set_job_state( $user, { state => 'ready', id => $job->{id} } );

   my $cluster_state_id =
     $self->read_cluster( $user, { id => $job->{cluster_id} } )->{state_id};

   if (
      scalar(
         grep { $cluster_state_id == $self->job_states->{$_} }
           (qw(running waiting))
      )
     )
   {
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
   return { success => 0, message => 'job is running' }
     if $job->{state_id} == $self->job_states->{running};
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

   my $jb = $self->sqlite->db->select(
      'job',
      ['*'],
      {
         cluster_id => $cluster_id,
         state_id   => { '!=', [ -and => ( $complete, $ice, $pruned ) ] }
      },
      { limit => 1 }
   );
   my $cl = $self->sqlite->db->select(
      'cluster',
      ['*'],
      {
         parent_id => $cluster_id,
         state_id  => { '!=', [ -and => ( $complete, $ice, $pruned ) ] }
      },
      { limit => 1 }
   );

   return $jb->hash || $cl->hash ? 0 : 1;
}

sub _set_job_state {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return unless $job && $job->{id};

   my $job_id = $job->{id};

   my $failed   = $self->job_states->{failed};
   my $killed   = $self->job_states->{killed};
   my $ready    = $self->job_states->{ready};
   my $waiting  = $self->job_states->{waiting};
   my $complete = $self->job_states->{complete};
   my $pruned   = $self->job_states->{pruned};
   my $ice      = $self->job_states->{ice};
   my $zombie   = $self->job_states->{zombie};

   my $update_hash = {};

   if ( $self->job_states->{ $d->{state} } ) {
      $update_hash->{state_id} = $self->job_states->{ $d->{state} };
   }

   my $cluster =
     $self->sqlite->db->select( 'cluster', ['*'], { id => $job->{cluster_id} } )
     ->hash;

   if ( $d->{state} eq 'starting' ) {
      $self->sqlite->db->update( 'job', { started => time },
         { id => $job_id } );
      $self->_reset_job_stats( $user, { id => $job_id } );

      #$update_hash->{started} = undef;
   }

   if ( scalar( grep { $d->{state} eq $_ } (qw(sleeping running)) ) ) {
      $update_hash->{started} = time;
      $update_hash->{ended}   = undef;

      my $j = $self->sqlite->db->select(
         'job',
         ['*'],
         {
            cluster_id => $job->{cluster_id},
            id         => { '!=', $job_id },
            state_id   => { '=',  [ ( $killed, $failed, $zombie ) ] }
         }
      );
      my $c = $self->sqlite->db->select(
         'cluster',
         ['*'],
         {
            parent_id => $cluster->{id},
            id        => { '!=', $cluster->{id} },
            state_id  => { '=',  [ ( $killed, $failed ) ] }
         }
      );

      unless ( $j->hash || $c->hash ) {
         $self->_set_cluster_state( $user,
            { state => 'running', id => $job->{cluster_id} } )
           unless $cluster->{state_id} == $self->job_states->{running};
      }
   }
   elsif ( grep { $d->{state} eq $_ } (qw(failed killed zombie)) ) {
      $self->sqlite->db->update(
         'job',
         { state_id => $self->job_states->{ $d->{state} } },
         { id       => $job_id }
      );
      $update_hash->{ended} = time;
      $self->_reset_job_stats( $user, { id => $job_id } )
        unless $d->{state} eq 'zombie';
      $self->_set_cluster_state( $user,
         { state => 'failed', id => $job->{cluster_id} } );

      if ( $d->{state} eq 'failed' ) {
         if ( $job->{retrys} && $job->{retrys} > $job->{retry_count} ) {
            my $retry_count = $job->{retry_count} || 0;
            $retry_count++;
            $self->sqlite->db->update(
               'job',
               { retry_count => $retry_count },
               { id          => $job_id }
            );
            $self->_set_job_state( $user,
               { state => 'retrying', id => $job_id } );
            $self->_start_job( $user,
               { id => $job_id, origin => 'retry', force => 1 } );
         }

         if ( $job->{on_fail_id} ) {
            my $cluster_alarm =
              $self->sqlite->db->select( 'cluster', ['id'],
               { id => $job->{on_fail_id} } )->hash;
            if ( $cluster_alarm->{id} ) {
               $self->_start_cluster(
                  $user,
                  {
                     id                => $cluster_alarm->{id},
                     origin            => 'fail',
                     origin_job_id     => $job_id,
                     origin_cluster_id => $cluster->{id},
                     force             => 1,
                  }
               );
            }
         }
      }
   }
   elsif (
      scalar(
         grep { $d->{state} eq $_ } (qw(complete ice_complete pruned_complete))
      )
     )
   {
      $update_hash->{state_id} = $self->job_states->{complete}
        if $d->{state} eq 'pruned_complete';

      if ( $d->{state} eq 'complete' ) {
         if ( $job->{loops} && $job->{loops} > $job->{loop_count} ) {
            my $loop_count = $job->{loop_count} || 0;
            $loop_count++;
            $self->sqlite->db->update(
               'job',
               {
                  loop_count => $loop_count,
                  state_id   => $self->job_states->{looping}
               },
               { id => $job_id }
            );
            $self->_start_job( $user, { id => $job_id, origin => 'loop' } );
         }
         else {
            $self->sqlite->db->update(
               'job',
               {
                  loop_count => 0,
                  state_id   => $self->job_states->{complete}
               },
               { id => $job_id }
            );
         }
      }

      # Trigger dependent jobs
      my $depends_sql = <<~"SQL";
         SELECT jn.job_id, j.state_id, jn.needs_any_mode
         FROM job_needs jn
         JOIN job j ON jn.job_id = j.id
         WHERE jn.needs_job_id = $job_id
           AND j.state_id IN ($ready, $waiting, $ice, $pruned)
      SQL

      my $need = $self->sqlite->db->query($depends_sql);
      while ( my $j = $need->hash ) {
         if ( $self->_job_needs_met( $user, { id => $j->{job_id} } ) ) {
            $self->_start_job(
               $user,
               {
                  id                => $j->{job_id},
                  origin            => 'auto',
                  origin_job_id     => $job_id,
                  origin_cluster_id => $cluster->{id},
                  force             => 1,
               }
            );
         }
      }

      $update_hash->{ended} = time;
      $self->_reset_job_stats( $user, { id => $job_id } );

      # Note: moved to end so all jobs complete first
      #$COMPLETE_CLUSTER = 1;

      #if ( $self->_cluster_is_complete( $user, { id => $job->{cluster_id} } ) )
      #{
      #   $self->_set_cluster_state( $user,
      #      { state => 'complete', id => $job->{cluster_id} } );
      #}
   }
   elsif ( $d->{state} eq 'retrying' ) {

      # Allow transition only if not already running
      return
        if scalar( grep { $job->{state_id} == $self->job_states->{$_} }
           (qw(starting running)) );
   }
   elsif ( $d->{state} eq 'looping' ) {
      return
        if scalar( grep { $job->{state_id} == $self->job_states->{$_} }
           (qw(starting running)) );
   }
   elsif ( $d->{state} eq 'ready' || $d->{state} eq 'waiting' ) {
      $update_hash->{loop_count}  = 0;
      $update_hash->{retry_count} = 0;
      $update_hash->{json}        = undef;
      $update_hash->{started}     = undef;
      $update_hash->{ended}       = undef;
   }

   # Final DB update
   $self->sqlite->db->update( 'job', $update_hash, { id => $job_id } )
     if scalar keys %$update_hash;

   $self->_broadcast_job( $user, [$job_id] );

   if ( $self->_cluster_is_complete( $user, { id => $job->{cluster_id} } ) )

#if ( $self->_cluster_is_complete( $user, { id => $job->{cluster_id} } ) && $cluster->{state_id} == $self->job_states->{running} )
   {
      $self->_set_cluster_state( $user,
         { state => 'complete', id => $job->{cluster_id} } );
   }

   # $self->_broadcast_job( $user, [$job_id] );

   #if ( $COMPLETE_CLUSTER )
   #{
   #   $self->_set_cluster_state( $user,
   #      { state => 'complete', id => $job->{cluster_id} } );
   #}

   return 1;
}

sub _update_job_log {
   my ( $self, $user, $d ) = @_;

   return unless $d->{job_id} && $d->{log_id} && $d->{ppid};

   #return unless $d->{log_id} && $d->{ppid};

   #my $job_id = $job->{id};
   #my $log_id = $d->{log_id};
   #my $ppid   = $d->{ppid};

   my $log_dir = "ordo_node/logs";    # adjust to your log path
       #my $log_file = "$log_dir/out.$d->{job_id}.$d->{ppid}.$d->{log_id}.log";

   if ( $d->{state} eq 'running' ) {

      # Insert new log entry
      my $insert_hash = {
         map  { $_ => $d->{$_} }
         grep { defined $d->{$_} } (qw(job_id log_id ppid started))
      };
      my $rows = $self->sqlite->db->insert( 'job_log', $insert_hash )->rows;

      # Auto-cleanup: delete oldest log if > 12
      if ($rows) {
         my $count = $self->sqlite->db->query(
            "SELECT count(*) as count FROM job_log WHERE job_id = ?",
            $d->{job_id} )->hash->{count};

         # delete oldest if oldest < yesterday and count > 12

         if ( $count > 12 ) {
            my $oldest = $self->sqlite->db->select(
               'job_log', ['*'],
               { job_id   => $d->{job_id} },
               { order_by => 'id', limit => 1 }
            )->hash;

            if ( $oldest->{started} < ( time - 86400 ) ) {
               my $delete_file =
"$log_dir/out.$oldest->{job_id}.$oldest->{ppid}.$oldest->{log_id}.log";
               $self->sqlite->db->delete( 'job_log', { id => $oldest->{id} } );

               # Cross-platform log file deletion (Perl unlink via SSH)
               my $ssh = $self->ssh_connection->{ $d->{server_id} };
               unless ( $ssh && $ssh->check_master ) {
                  $self->_connect_ssh( $user, { id => $d->{server_id} } );
                  $ssh = $self->ssh_connection->{ $d->{server_id} };
               }

               if ($ssh) {
                  my $remote_log = $ssh->capture(
                     "perl -e 'unlink \"$delete_file\" if -f \"$delete_file\"'"
                  );
                  if ($@) {
                     $self->log->warn(
                        "Failed to delete remote log $delete_file: $@");
                  }
               }
            }
         }
      }
   }
   else {
      # Update existing log entry
      my $update_hash = {
         map  { $_ => $d->{$_} }
         grep { defined $d->{$_} }
           (qw(job_id log_id ppid pid exit_code signal ended))
      };

      #$update_hash->{job_id} = $d->{job_id};
      $self->sqlite->db->update(
         'job_log',
         $update_hash,
         {
            job_id => $d->{job_id},
            log_id => $d->{log_id},
            ppid   => $d->{ppid}
         }
      );
   }
}

sub update_job_state {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};

   my $job_id = $job->{id};

   # Step 1: Update runtime fields in job table
   my @runtime_fields =
     qw(pctcpu pid ppid start rss pctmem fname signal exit_code started ended);

   my $runtime_hash =
     { map { $_ => $d->{$_} } grep { exists $d->{$_} } @runtime_fields };
   $runtime_hash->{last_update} = time;

   $self->sqlite->db->update( 'job', $runtime_hash, { id => $job_id } )
     if scalar keys %$runtime_hash;

   # Step 2: Job log handling
   if ( $d->{ppid} && $d->{log_id} && $d->{state} ) {
      my $update_log_hash = {
         map  { $_ => $d->{$_} }
         grep { exists $d->{$_} }
           qw(state log_id ppid pid exit_code signal started ended)
      };
      $update_log_hash->{job_id}    = $job->{id};
      $update_log_hash->{server_id} = $job->{server_id};
      $self->_update_job_log( $user, $update_log_hash );
   }

   # Step 3: Call _set_job_state if state is present and valid
   if ( defined $d->{state} && $self->job_states->{ $d->{state} } ) {
      $self->_set_job_state( $user, { id => $job_id, state => $d->{state} } );
   }

   # Step 4: Broadcast state/runtime update
   $self->_broadcast_job( $user, [$job_id] );

   return { success => 0 };
}

sub update_job_config {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );
   return { success => 0, message => 'job not found' } unless $job->{id};

   my ( $needs_ids, $needs_any_ids, $on_fail_id );

   if ( $d->{needs_ids} ) {
      $needs_ids = $self->_filter_job_ids( $user, $d->{needs_ids} );
   }
   elsif ( $d->{needs} ) {
      $needs_ids = $self->_resolve_job_ids( $user, $d->{needs} );
   }

   if ( $d->{needs_any_ids} ) {
      $needs_any_ids = $self->_filter_job_ids( $user, $d->{needs_any_ids} );
   }
   elsif ( $d->{needs_any} ) {
      $needs_any_ids = $self->_resolve_job_ids( $user, $d->{needs_any} );
   }

   if ( $d->{on_fail_id} ) {
      $on_fail_id =
        shift @{ $self->_filter_cluster_ids( $user, [ $d->{on_fail_id} ] ) };
   }
   elsif ( $d->{on_fail} ) {
      $on_fail_id =
        shift @{ $self->_resolve_cluster_ids( $user, [ $d->{on_fail} ] ) };
   }

   my @fields = qw(retrys loops delay description script);
   my $update_hash =
     { map { $_ => $d->{$_} } grep { exists $d->{$_} } @fields };

   if ( $needs_ids || $needs_any_ids ) {
      $self->_write_job_needs(
         $user,
         {
            needs_all  => $needs_ids,
            needs_any  => $needs_any_ids,
            id         => $job->{id},
            cluster_id => $job->{cluster_id}
         }
      );
   }

   # on_fail update
   $update_hash->{on_fail_id} =
       $on_fail_id
     ? $on_fail_id
     : undef;

   # server update
   if ( $d->{server_id} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'],
         { id => $d->{server_id}, org_id => $user->org_id } )->hash;
      $update_hash->{server_id} = $res->{id} if $res->{id};
   }
   elsif ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'],
         { name => $d->{server}, org_id => $user->org_id } )->hash;
      $update_hash->{server_id} = $res->{id} if $res->{id};
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

   $update_hash->{delay} = $d->{delay} if $d->{delay} && $d->{delay} <= 86400;
   $update_hash->{on_fail_id}  = $on_fail_id ? $on_fail_id : undef;
   $update_hash->{name}        = $d->{newname} if $d->{newname};
   $update_hash->{last_update} = time;

   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   $self->sqlite->db->delete( 'job_needs', { job_id => $job->{id} } )
     if $d->{remove_needs};

   # Optional broadcast if name/description changed
   if ( $d->{newname} || $d->{description} ) {
      $self->_broadcast_job( $user, [ $job->{id} ] );
   }

   return { success => 1, message => 'job updated' };
}

sub _resolve_job_ids {
   my ( $self, $user, $needs ) = @_;
   return unless $needs && ref $needs eq 'ARRAY';
   my @need_ids;
   for my $need ( @{$needs} ) {
      my $path_info = $self->_path_info( $user, $need );
      push @need_ids, $path_info->{job_id}
        if $path_info->{success} && $path_info->{job_id};
   }
   return \@need_ids;
}

sub _filter_job_ids {
   my ( $self, $user, $jids ) = @_;
   return unless $jids && ref $jids eq 'ARRAY';
   return [
      map { $_->{id} } @{
         $self->sqlite->db->select( 'job', ['id'], { id => { '=', $jids } } )
           ->hashes->to_array
      }
   ];
}

sub _filter_cluster_ids {
   my ( $self, $user, $cids ) = @_;
   return unless $cids && ref $cids eq 'ARRAY';
   return [
      map { $_->{id} } @{
         $self->sqlite->db->select( 'cluster', ['id'],
            { id => { '=', $cids } } )->hashes->to_array
      }
   ];
}

sub _resolve_cluster_ids {
   my ( $self, $user, $needs ) = @_;
   return unless $needs && ref $needs eq 'ARRAY';
   my @need_ids;
   for my $need ( @{$needs} ) {
      my $path_info = $self->_path_info( $user, $need );
      push @need_ids, $path_info->{cluster_id}
        if $path_info->{success} && $path_info->{cluster_id};
   }
   return \@need_ids;
}

sub _update_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' } unless $job->{id};

   my ( $needs_ids, $needs_any_ids, $on_fail_id );

   if ( $d->{needs_ids} ) {
      $needs_ids = $self->_filter_job_ids( $user, $d->{needs_ids} );
   }
   elsif ( $d->{needs} ) {
      $needs_ids = $self->_resolve_job_ids( $user, $d->{needs} );
   }
   if ( $d->{needs_any_ids} ) {
      $needs_any_ids = $self->_filter_job_ids( $user, $d->{needs_any_ids} );
   }
   elsif ( $d->{needs_any} ) {
      $needs_any_ids = $self->_resolve_job_ids( $user, $d->{needs_any} );
   }
   if ( $d->{on_fail_id} ) {
      $on_fail_id =
        shift @{ $self->_filter_cluster_ids( $user, [ $d->{on_fail_id} ] ) };
   }
   elsif ( $d->{on_fail} ) {
      $on_fail_id =
        shift @{ $self->_resolve_cluster_ids( $user, [ $d->{on_fail} ] ) };
   }

   my @fields =
     qw(retrys loops delay pctcpu pid start priority rss pctmem fname signal exit_code state_id description started ended server_id script);
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

   $update_hash->{delay} = $d->{delay} if $d->{delay} && $d->{delay} <= 86400;
   $update_hash->{on_fail_id} =
       $on_fail_id
     ? $on_fail_id
     : undef;

   if ( $d->{state} ) {
      my $rv = $self->_set_job_state( $user,
         { id => $job->{id}, state => $d->{state} } );

      # job log
      if ( $d->{log_id} && $d->{ppid} ) {
         if ( $d->{state} eq 'running' ) {
            my $insert_hash = {
               map  { $_ => $d->{$_} }
               grep { defined $d->{$_} } (qw(log_id ppid pid started))
            };
            $insert_hash->{job_id} = $job->{id};
            my $rows =
              $self->sqlite->db->insert( 'job_log', $insert_hash )->rows;

            # delete oldest log
            if ($rows) {
               my $count = $self->sqlite->db->query(
"select count(*) as count from job_log where job_id = $d->{id}"
               )->hash->{count};
               if ( $count > 12 ) {
                  my $dl = $self->sqlite->db->select(
                     'job_log', ['*'],
                     { job_id   => $job->{id} },
                     { order_by => 'id', limit => 1 }
                  )->hash;
                  $self->sqlite->db->delete( 'job_log', { id => $dl->{id} } );

                  my $ssh = $self->ssh_connection->{ $job->{server_id} };
                  unless ( $ssh && $ssh->check_master ) {
                     $self->_connect_ssh( $user, { id => $job->{server_id} } );
                     $ssh = $self->ssh_connection->{ $job->{server_id} };
                  }

                  # TODO: multi-platform script
                  $ssh->spawn(
"rm ordo_node/logs/*\.$dl->{job_id}\.$dl->{ppid}\.$dl->{log_id}\.log"
                  );
               }
            }
         }
         else {
            my $update_hash = {
               map  { $_ => $d->{$_} }
               grep { defined $d->{$_} }
                 (qw(log_id ppid pid exit_code signal ended))
            };
            $update_hash->{job_id} = $d->{id};
            $self->sqlite->db->update(
               'job_log',
               $update_hash,
               {
                  job_id => $job->{id},
                  log_id => $d->{log_id},
                  ppid   => $d->{ppid}
               }
            );
         }
      }
   }

   if ( $needs_ids || $needs_any_ids ) {
      $self->_write_job_needs(
         $user,
         {
            needs_all  => $needs_ids,
            needs_any  => $needs_any_ids,
            id         => $job->{id},
            cluster_id => $job->{cluster_id}
         }
      );
   }

   if ( $d->{server} ) {
      my $res = $self->sqlite->db->select( 'server', ['id'],
         { name => $d->{server}, org_id => $user->org_id } )->hash;
      return { success => 0, message => 'server not found' }
        unless $res->{id};
      $update_hash->{server_id} = $res->{id};
   }
   $update_hash->{name}        = $d->{newname} if $d->{newname};
   $update_hash->{last_update} = time;

   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   $self->sqlite->db->delete( 'job_needs', { job_id => $job->{id} } )
     if $d->{remove_needs};

   $self->_broadcast_job( $user, [ $job->{id} ] );

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
      my $target =
        $self->sqlite->db->select( 'job', ['state_id'], { id => $target_id } )
        ->hash;

      $needs{$target_id} = {
         state_id => $target->{state_id} || 0,
         mode     => $mode,                      # 0 = all, 1 = any
      };
   }

   return \%needs;
}

sub _write_job_needs {
   my ( $self, $user, $d ) = @_;
   my $job_id    = $d->{id};
   my $needs_all = $d->{needs_all} || [];    # AND dependencies
   my $needs_any = $d->{needs_any} || [];    # OR dependencies

   return unless ( $needs_all || $needs_any );

   my $tx = $self->sqlite->db->begin;

   # Clear old dependencies
   $self->sqlite->db->query( 'DELETE FROM job_needs WHERE job_id = ?',
      $job_id );

   # Insert AND deps (needs_any_mode = 0)
   for my $target_id (@$needs_all) {
      next unless $target_id =~ /^\d+$/;
      print "$job_id, $target_id\n";

      $self->sqlite->db->query(
'INSERT OR IGNORE INTO job_needs (job_id, needs_job_id, needs_any_mode) VALUES (?, ?, 0)',
         $job_id, $target_id
      );
   }

   # Insert OR deps (needs_any_mode = 1)
   for my $target_id (@$needs_any) {
      next unless $target_id =~ /^\d+$/;
      $self->sqlite->db->query(
'INSERT OR IGNORE INTO job_needs (job_id, needs_job_id, needs_any_mode) VALUES (?, ?, 1)',
         $job_id, $target_id
      );
   }

   $tx->commit;
   return 1;
}

sub _write_cluster_needs {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id};
   my $needs_all  = $d->{needs_all};
   my $needs_any  = $d->{needs_any};

   return unless $needs_all || $needs_any;

   my $tx = $self->sqlite->db->begin;

   $self->sqlite->db->query( 'DELETE FROM cluster_needs WHERE cluster_id = ?',
      $cluster_id );

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
      $self->sqlite->db->query(
'INSERT INTO cluster_needs (cluster_id, needs_cluster_id, needs_any_mode) VALUES (?, ?, 1)',
         $cluster_id, $target_id
      );
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
      my $target = $self->sqlite->db->select( 'cluster', ['state_id'],
         { id => $target_id } )->hash;

      $needs{$target_id} = {
         state_id => $target->{state_id} || 0,
         mode     => $mode,                      # 0 = all, 1 = any
      };
   }
   return \%needs;
}

sub _ping {
   my ( $self, $host ) = @_;
   return unless $host;
   my $output = `ping -c 1 $host 2>&1`;
   if (
      $output =~ /min\/avg\/max\/(mdev|stddev) = ([\d.]+)\/([\d.]+)\/([\d.]+)/ )
   {
      return $3;
   }
}

sub update_sysinfo {
   my ( $self, $user, $d ) = @_;
   return { success => 0, exit => 1, message => 'missing server id' }
     unless $d->{id};

   my $server = $self->_server_info( $user, { id => $d->{id} } );
   return { success => 0, exit => 1, message => 'server not found' }
     unless $server;

   my @stats = qw(
     used_disk
     load_15
     used_memory
     total_processes
     load_1
     used_swap
     total_swap
     max_files
     total_disk
     open_files
     root_total_disk
     root_used_disk
     cpu_percent
     net_rx_bytes
     net_tx_bytes
     uptime
     load_5
     total_memory
     zombie_processes
     free_memory
     free_disk
     free_swap
     root_free_disk
   );

   my $uh = { map { $_, $d->{$_} } grep { exists $d->{$_} } @stats };

   my $ssh = $self->ssh_connection->{ $server->{id} };
   return { success => 0, exit => 1 }
     unless $server->{id} && $ssh && $ssh->check_master;
   $uh->{ping}        = $self->_ping( $server->{host} ) if $server->{host};
   $uh->{update_time} = time;
   my $running  = $self->job_states->{running};
   my $watching = $self->job_states->{watching};
   my $starting = $self->job_states->{starting};
   my $stopping = $self->job_states->{stopping};

   my @job_ids = ();

   # receive pid info
   if ( $d->{pids} && ref $d->{pids} eq 'ARRAY' ) {
      foreach my $pid ( @{ $d->{pids} } ) {
         my $job = $self->sqlite->db->select( 'job', ['id'],
            { server_id => $server->{id}, pid => $pid->{pid} } )->hash;
         next unless $job->{id};
         push @job_ids, $job->{id};
         my $update = {
            map  { $_, $pid->{$_} }
            grep { exists $pid->{$_} }
              (qw(pctcpu pid start priority rss pctmem ppid fname))
         };
         $update->{last_update} = time;
         $self->sqlite->db->update( 'job', $update, { id => $job->{id} } );

         if ( $job->{stats} ) {
            my $js_insert =
              { map { $_, $update->{$_} }
                 (qw(pctcpu pid start priority rss pctmem ppid fname)) };
            $self->sqlite->db->insert( 'job_stats', $js_insert );
         }

         # TODO: job resource alarms: max duration pctcpu pctmem
      }
   }

   # identify zombies
   if ( $d->{zombies} && ref $d->{zombies} eq 'ARRAY' ) {

#my $ids = $self->sqlite->db->select( 'job', [ 'id', 'state_id' ], { pid => $d->{zombies}, state_id => [ $running, $watching ] } );
      my $ids = $self->sqlite->db->select(
         'job',
         [ 'id', 'state_id' ],
         { pid => $d->{zombies}, server_id => $d->{id} }
      );
      while ( my $next = $ids->hash ) {
         $self->_set_job_state( $user,
            { state => 'zombie', id => $next->{id} } );
      }
   }

   # send pid request
   my @pids;
   my $pids = $self->sqlite->db->select(
      'job',
      ['pid'],
      {
         server_id => $d->{id},
         pid       => { '!=', undef },
         state_id  => [ $stopping, $starting, $running, $watching ]
      }
   );
   while ( my $next = $pids->hash ) {
      push @pids, $next->{pid};
   }

   if ( $server->{stats} ) {
      my @stats = qw(
        used_disk
        load_15
        used_memory
        total_processes
        load_1
        used_swap
        total_swap
        max_files
        total_disk
        open_files
        root_total_disk
        root_used_disk
        cpu_percent
        net_rx_bytes
        net_tx_bytes
        uptime
        load_5
        total_memory
        zombie_processes
        free_memory
        free_disk
        free_swap
        root_free_disk
      );

      my $ss_insert = { map { $_, $uh->{$_} } @stats };
      $self->sqlite->db->insert( 'server_stats', $ss_insert );
   }

   eval { $self->sqlite->db->update( 'server', $uh, { id => $d->{id} } ) };

   if ($@) {
      return { success => 0, message => $@ };
   }
   else {
      $self->_broadcast_server( $user, [ $server->{id} ] );
      $self->_broadcast_job( $user, \@job_ids );
      return { success => 1, pids => \@pids };
   }
}

sub watch_job {
   my ( $self, $user, $d ) = @_;

   return { success => 0, message => 'missing pid or match' }
     unless ( $d->{pid} || $d->{match} );

   my $server = $self->_server_info( $user,
      { id => $d->{server_id}, name => $d->{server} } );
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

sub _cluster_needs_met {
   my ( $self, $user, $d ) = @_;
   my $cluster = $self->_read_cluster( $user, { id => $d->{id} } );

   return 1
     if (!scalar @{ $cluster->{needs_ids} }
      && !scalar @{ $cluster->{needs_any_ids} } );

   my $complete = $self->job_states->{complete};
   my $ice      = $self->job_states->{ice};
   my $pruned   = $self->job_states->{pruned};

   my $all_sql = <<~"SQL";
      select cn.needs_cluster_id, c.state_id, cn.cluster_id
      from cluster c 
      join cluster_needs cn on c.id = cn.needs_cluster_id
      where c.state_id not in ($complete,$ice,$pruned)
      and cn.needs_any_mode = 0
      and cn.cluster_id = ?;
   SQL

   my $not_met = $self->sqlite->db->query( $all_sql, $d->{id} )->hash;
   my $all_met = scalar @{ $cluster->{needs_ids} } && $not_met ? 0 : 1;

   my $any_sql = <<~"SQL";
      select cn.needs_cluster_id, c.state_id, cn.cluster_id
      from cluster c 
      join cluster_needs cn on c.id = cn.needs_cluster_id
      where c.state_id in ($complete,$ice,$pruned)
      and cn.needs_any_mode = 1
      and cn.cluster_id = ?;
   SQL

   my $met     = $self->sqlite->db->query( $any_sql, $d->{id} )->hash;
   my $any_met = scalar @{ $cluster->{needs_any_ids} } && !$met ? 0 : 1;

   return $all_met && $any_met ? 1 : 0;
}

sub _job_needs_met {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, { id => $d->{id} } );

   return 1
     if (!scalar @{ $job->{needs_ids} }
      && !scalar @{ $job->{needs_any_ids} } );

   my $complete = $self->job_states->{complete};
   my $ice      = $self->job_states->{ice};
   my $pruned   = $self->job_states->{pruned};

   my $all_sql = <<~"SQL";
      select jn.needs_job_id, j.state_id, jn.job_id
      from job j
      join job_needs jn on j.id = jn.needs_job_id 
      where j.state_id not in ($complete,$ice,$pruned)
      and jn.needs_any_mode = 0
      and jn.job_id = ?;
   SQL

   my $not_met = $self->sqlite->db->query( $all_sql, $d->{id} )->hash;
   my $all_met = scalar @{ $job->{needs_ids} } && $not_met ? 0 : 1;

   my $any_sql = <<~"SQL";
      select jn.needs_job_id, j.state_id, jn.job_id
      from job j
      join job_needs jn on j.id = jn.needs_job_id
      where j.state_id in ($complete,$ice,$pruned)
      and jn.needs_any_mode = 1 
      and jn.job_id = ?;
   SQL

   my $met     = $self->sqlite->db->query( $any_sql, $d->{id} )->hash;
   my $any_met = scalar @{ $job->{needs_any_ids} } && !$met ? 0 : 1;

   return $all_met && $any_met ? 1 : 0;
}

sub start_job {
   my ( $self, $user, $d ) = @_;
   $d->{origin} = 'user';
   return $self->_start_job( $user, $d );
}

sub _start_job {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );
   return { success => 0, skipped => 1, message => 'job not found' }
     unless $job->{id};

   if ( ( $job->{pid} || $job->{ppid} )
      && scalar grep { $self->job_states->{$_} == $job->{state_id} }
      (qw(starting running)) )
   {
      return {
         success => 0,
         skipped => 1,
         message => 'job is already running'
      };
   }

   # skip if job on ice
   if ( $job->{state_id} == $self->job_states->{ice} ) {
      $self->_set_job_state( $user,
         { id => $job->{id}, state => 'ice_complete' } );
      return { success => 0, skipped => 1, message => 'job on ice' };
   }

   # skip if job pruned
   if ( $job->{state_id} == $self->job_states->{pruned} ) {
      $self->_set_job_state( $user,
         { id => $job->{id}, state => 'pruned_complete' } );
      return { success => 0, skipped => 1, message => 'job pruned' };
   }

   # don't start if dependencies not satisfied

   unless ( $self->_job_needs_met( $user, { id => $job->{id} } ) ) {
      print "NEEDS: "
        . $self->_job_needs_met( $user, { id => $job->{id} } ) . "\n";
      return { success => 0, waiting => 1, message => 'dependency not met.' };
   }

   # reset counters on user start
   if ( $d->{origin} eq 'user' ) {
      $self->sqlite->db->update(
         'job',
         { loop_count => 0, retry_count => 0 },
         { id         => $job->{id} }
      );
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

   # === Use Execution Token for all job launches ===
   my $launch_token = $user->execution_token;

   my $opts = {
      token      => $launch_token,               # ← Always use execution token
      id         => $job->{id},
      email      => $user->email,
      team       => $user->team,
      cluster_id => $job->{cluster_id},
      server_id  => $job->{server_id},
      script     => $job->{script},
      api        => $self->local_url . '/api',
   };

   # Optional but recommended: keep original user for auditing
   $opts->{user_id} = $user->id;    # ← Add this

   $opts->{origin}            = $d->{origin}        if $d->{origin};
   $opts->{origin_job_id}     = $d->{origin_job_id} if $d->{origin_job_id};
   $opts->{origin_cluster_id} = $d->{origin_cluster_id}
     if $d->{origin_cluster_id};
   $opts->{delay}  = $job->{delay} if $job->{delay};
   $opts->{json}   = $job->{json}  if $job->{json};
   $opts->{needs}  = $needs        if $needs;
   $opts->{needed} = $needed       if $needed;

   my $json     = encode_json($opts);
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
   return { success => 0, message => 'hk job not found' }
     unless $job && $job->{id};
   return { success => 0, message => 'hk pid not found' }
     unless $job->{pid} || $job->{ppid};
   return {
      success => 0,
      message => 'watcher jobs cannot be killed. unwatch or delete it instead'
     }
     if $job->{state_id} == $self->job_states->{watching};

   my $server = $self->_server_info( $user, { id => $job->{server_id} } );
   return { success => 0, message => 'server not found' }
     unless $server && $server->{id};

   my @pids;
   unshift @pids, $job->{pid}  if $job->{pid};
   unshift @pids, $job->{ppid} if $job->{ppid};

   my $pid_list = join( ', ', @pids );

   # check connection
   my $ssh = $self->ssh_connection->{ $server->{id} };
   $self->_connect_ssh( $user, { id => $server->{id} } )
     unless $ssh && $ssh->check_master;
   $ssh = $self->ssh_connection->{ $server->{id} };
   return { success => 0, message => 'server not connected' }
     unless $ssh && $ssh->check_master;

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
   return { success => 0, message => 'pid not found' }
     if !$job->{pid} && !$job->{ppid};
   return {
      success => 0,
      message => 'watcher jobs cannot be killed. unwatch or delete it instead'
     }
     if $job->{state_id} == $self->job_states->{watching};

   if ( scalar grep { $job->{state_id} == $self->job_states->{$_} }
      (qw(waiting looping retrying)) )
   {
      return $self->_hard_kill_job( $user, { id => $job->{id} } );
   }

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } )
     unless $ssh && $ssh->check_master;
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
   return { success => 0, message => 'job not found' }
     unless ref $job && $job->{id};

   # check connection
   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   $self->_connect_ssh( $user, { id => $job->{server_id} } )
     unless $ssh && $ssh->check_master;

   $ssh->system("renice -n 19 -p $job->{pid}");
   return $ssh->error
     ? { success => 0, message => $ssh->error }
     : { success => 1 };
}

sub _reset_job_stats {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );    #job info
   return { success => 0, message => 'job not found' }
     unless ref $job && $job->{id};

   my %update = map { $_ => undef }
     (qw(signal pid ppid exit_code pctcpu start priority rss pctmem fname));

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
   my $copy_key =
"sshpass -p $d->{password} ssh-copy-id -f  -p $port $d->{user}\@$d->{host}";
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
      my $update    = {
         map  { $_, $basicinfo->{$_} }
         grep { $basicinfo->{$_} } (qw(home os cores cwd ip_address))
      };
      $self->sqlite->db->update( 'server', $update, { id => $s->{id} } );
   };
   return $@ ? 0 : 1;
}

sub create_monitor {
   my ( $self, $user, $d ) = @_;

   my $id = $self->_new_connection( $user, $d );
   return { success => 0, message => "unable to create connection" }
     unless $id;

   # create monitor and start it
   my $installed = $self->_install_monitor( $user, { id => $id } )
     or die "install failed";
   return { success => 0, message => "install failed" } unless $installed;

   $self->_start_monitor( $user, { id => $id } ) or die "start failed";
   $self->_broadcast_server( $user, [$id] );

   return { success => 1 };
}

sub read_monitor {
   my ( $self, $user, $d ) = @_;
   my $server = $self->_server_info( $user, $d );
   return $server->{id}
     ? { success => 1, %$server }
     : { success => 0, message => 'monitor not found' };
}

sub find_monitor {
   my ( $self, $user, $d ) = @_;
   my $servers =
     $self->sqlite->db->select( 'server', ['id'], { org_id => $user->org_id } );
   my @server_list;
   while ( my $server = $servers->hash ) {
      my $s = $self->read_monitor( $user, { id => $server->{id} } );
      next unless $s->{success};
      push @server_list, $s;
   }
   return { success => 1, servers => \@server_list };
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

   my $insert_hash =
     { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(name user host)) };
   $insert_hash->{org_id} = $user->org_id;

   my $id;
   eval {
      $id = $self->sqlite->db->insert( 'server', $insert_hash )->last_insert_id;
   };

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
   $self->_connect_ssh( $user, { id => $s->{id} } )
     unless ( $ssh && $ssh->check_master );
   $ssh = $self->ssh_connection->{ $s->{id} };
   return 1;
}

sub update_monitor {
   my ( $self, $user, $d ) = @_;

   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'monitor not found' } unless $server;

#my $update_hash = { map { $_ => $d->{$_} } grep { exists $d->{$_} } (qw(port user host password total_memory used_memory cpu total_disk used_disk uptime)) };
   my $update_hash = {
      map  { $_ => $d->{$_} }
      grep { exists $d->{$_} } (qw(port user host password))
   };
   $update_hash->{ping} = $self->_ping( $server->{host} ) if $server->{host};
   $update_hash->{update_time} = time;
   $update_hash->{name}        = $d->{newname} if $d->{newname};

   if ( scalar keys %{$update_hash} ) {
      eval {
         $self->sqlite->db->update( 'server', $update_hash,
            { id => $server->{id} } );
      };
      return { success => 0, message => $@ } if $@;
   }
   $server = $self->_server_info( $user, $d );
   $self->_broadcast_server( $user, [ $server->{id} ] );

   my $connection_ok = $self->_connect_ssh( $user, { id => $server->{id} } );
   return { success => 0, message => "$server->{name} connection failed" }
     unless $connection_ok;

   if ( $d->{password} ) {
      $self->_ssh_copy(
         $user,
         {
            user     => $server->{user},
            host     => $server->{host},
            password => $d->{password}
         }
      ) if $d->{password};
   }
   return { success => 1, message => "connected to $server->{name}" };
}

sub upgrade_monitor {
   my ( $self, $user, $d ) = @_;
   my $rv = $self->_install_monitor( $user, $d );
   return { success => $rv };
}

sub delete_monitor {
   my ( $self, $user, $d ) = @_;
   return { success => 0, message => 'missing name or id' }
     unless $d->{name} || $d->{id};

   my $server = $self->_server_info( $user, $d );
   return { success => 0, message => 'server not found' }
     unless $server && $server->{name};

   eval {
      $self->sqlite->db->delete( 'server', { id => $server->{id} } );
      $self->_disconnect_ssh( $user, { id => $server->{id} } );
      delete $self->ssh_connection->{ $server->{id} };
   };
   if ($@) {
      return { success => 0, message => $@ };
   }
   else {
      $self->_broadcast_server( $user, [ $server->{id} ] );
      return { success => 1 };
   }
}

sub active_pids {
   my ( $self, $user, $d ) = @_;

   my $server = $self->sqlite->db->select( 'server', ['*'],
      { id => $d->{id}, org_id => $user->org_id } )->hash;
   return { success => 0, message => 'server not found' } unless $server->{id};

   my $jobs = $self->sqlite->db->select(
      'job',
      [ 'id', 'pid', 'state_id' ],
      { pid => { '!=', undef }, server_id => $server->{id} }
   )->hashes->to_array;
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

   my $jobs = $self->sqlite->db->query(
"select * from job where (pid is not null or ppid is not null) and server_id = $d->{id}"
   )->hashes->to_array;

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
   return
        unless ref $found eq 'HASH'
     && exists $found->{alive}
     && exists $found->{zombies};
   my @alive   = @{ $found->{alive} }   if ref $found->{alive} eq 'ARRAY';
   my @zombies = @{ $found->{zombies} } if ref $found->{zombies} eq 'ARRAY';

   foreach my $zombie ( grep { exists $pid_map{$_} } @zombies ) {
      $self->_set_job_state( $user,
         { id => $pid_map{$zombie}->{id}, state => 'zombie' } );
      $zombie_count++;
   }
   foreach my $life ( grep { exists $pid_map{$_} } @alive ) {
      if ( $pid_map{$life}->{state_id} != $self->job_states->{running} ) {
         $self->_set_job_state( $user,
            { id => $pid_map{$life}->{id}, state => 'running' } );
         $revived_count++;
      }
   }
   return 1;
}

sub sync {
   my ( $self, $user, $d ) = @_;

   my $zombie_count  = 0;
   my $revived_count = 0;
   my $servers =
     $self->sqlite->db->select( 'server', ['*'], { org_id => $user->org_id } );
   while ( my $server = $servers->hash ) {

      my $jobs = $self->sqlite->db->query(
"select * from job where (pid is not null or ppid is not null) and server_id = $server->{id}"
      )->hashes->to_array;

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
            $self->_set_job_state( $user,
               { id => $job_id, state => 'zombie' } );
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
      next
        unless ref $found eq 'HASH'
        && exists $found->{alive}
        && exists $found->{zombies};
      my @alive   = @{ $found->{alive} } if ref $found->{alive} eq 'ARRAY';
      my @zombies = @{ $found->{zombies} }
        if ref $found->{zombies} eq 'ARRAY';

      foreach my $zombie ( grep { exists $pid_map{$_} } @zombies ) {
         $self->_set_job_state( $user,
            { id => $pid_map{$zombie}->{id}, state => 'zombie' } );
         $zombie_count++;
      }
      foreach my $life ( grep { exists $pid_map{$_} } @alive ) {
         if ( $pid_map{$life}->{state_id} != $self->job_states->{running} ) {
            $self->_set_job_state( $user,
               { id => $pid_map{$life}->{id}, state => 'running' } );
            $revived_count++;
         }
      }
   }
   return {
      success => 1,
      message => "$zombie_count zombies found $revived_count revived"
   };
}

# log related subroutines

sub _log_info {
   my ( $self, $user, $d ) = @_;
   my $job = $self->_job_info( $user, $d );

   return unless $job->{id};

   my $log;
   if ( $d->{log_id} ) {
      $log = $self->sqlite->db->select( 'job_log', ['*'],
         { id => $d->{log_id}, job_id => $job->{id} } )->hash;
   }
   else {
      $log = $self->sqlite->db->query(
"select * from job_log where job_id = $job->{id} order by id desc limit 1"
      )->hash;
   }

   return
        unless $log->{job_id}
     && $log->{log_id}
     && $log->{ppid}
     && $job->{server_id};

   my $ssh = $self->ssh_connection->{ $job->{server_id} };
   unless ( $ssh && $ssh->check_master ) {
      $self->_connect_ssh( $user, { id => $job->{server_id} } );
      $ssh = $self->ssh_connection->{ $job->{server_id} };
   }
   $ssh = $self->ssh_connection->{ $job->{server_id} };

   return unless $ssh && $ssh->check_master;

   my $o = "ordo_node/logs/out.$log->{job_id}.$log->{ppid}.$log->{log_id}.log";

   # TODO: change to cross-platform script

   my $out = $ssh->capture("cat $o");
   return if $ssh->error || !$out;
   $log->{out} = $out;

   $log->{job_name}    = $job->{name};
   $log->{server_name} = $job->{server_name};
   $log->{job_path}    = $self->id2path( $user, { id => $job->{cluster_id} } );
   return $log;
}

sub read_log {
   my ( $self, $user, $d ) = @_;

   my $log = $self->_log_info( $user, $d );

   if ( $log && $log->{id} ) {
      $log->{success} = 1;
      return $log;
   }
   return { success => 0, message => 'log not found' };
}

sub find_log {
   my ( $self, $user, $d ) = @_;

   my $job = $self->_job_info( $user, $d );

   return { success => 0, message => 'job not found' } unless $job->{id};
   my @all;
   my $logs = $self->sqlite->db->select(
      'job_log', ['*'],
      { job_id   => $job->{id} },
      { order_by => { -desc => 'started' }, limit => 20 }
   );

   while ( my $log = $logs->hash ) {
      push @all, $log;
   }
   my $path = $self->id2path( $user, { id => $job->{cluster_id} } );
   return scalar @all
     ? {
      success => 1,
      path    => $path,
      name    => $job->{name},
      job_id  => $job->{id},
      logs    => \@all
     }
     : { success => 0, message => 'no logs found' };

}

# cron related subroutines

sub update_cron {
   my ( $self, $user, $d ) = @_;

   # id begin expire description

   my $cron =
     $self->sqlite->db->select( 'cron', ['*'], { id => $d->{id} } )->hash;
   return { success => 0, message => 'cron not found' } unless $cron->{id};

   my $cal;
   if ( $d->{cal} || $d->{cal_id} ) {
      $cal =
        $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
      return { success => 0, message => 'calendar not found' }
        unless $cal->{id};
   }

   my $update_hash = {
      map  { $_, $d->{$_} }
      grep { exists $d->{$_} } (qw(description begin expire))
   };
   $update_hash->{cal_id} = $cal->{id}    if $cal->{id};
   $update_hash->{name}   = $d->{newname} if $d->{newname};
   my $exp = $d->{newname} || $d->{name};

   eval {
      my $c = Cron::Toolkit->new( expression => $exp, );
      $update_hash->{english} = $c->describe;
   };
   return { success => 0, message => 'invalid cron expression' } if $@;

   my $rows =
     $self->sqlite->db->update( 'cron', $update_hash,
      { id => $cron->{id}, org_id => $user->org_id } )->rows
     if scalar keys %$update_hash;
   if ($rows) {
      $self->_broadcast_cal( $user, [ $cal->{id} ] );
      return { success => 1 };
   }
   else {
      return { success => 0, message => 'unable to update cron' };
   }
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

   my $cal_row =
     $self->sqlite->db->select( 'cal', ['tz'], { id => $d->{cal_id} } )->hash;
   my $tz = $cal_row->{tz} || 'UTC';

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

   my $cron_row =
     $self->sqlite->db->select( 'cron', ['*'], { id => $d->{id} } )->hash;
   return { success => 0, message => 'cron not found' } unless $cron_row;

   my $cal_id = $cron_row->{cal_id};
   return { success => 0, message => 'missing cal_id' } unless $cal_id;

   return { success => 0, message => 'cron has no next start time' }
     unless $self->_cron_next_start( $user, $d );

   $self->_delete_cron_object( $user, { id => $d->{id} } );

   $self->cron->{ $d->{id} } = EV::periodic(
      0, 0,
      sub {
         my ( $watcher, $now ) = @_;
         my $next = $self->_cron_next_start( $user, $d ) || 0;
         $self->sqlite->db->update(
            'cron',
            { next_start => $next },
            { id         => $d->{id} }
         );
         return $next;
      },
      sub {
         # delete cron if no next start date
         $self->_delete_cron( $user, $d )
           unless $self->_cron_next_start( $user, $d );

         # start all clusters connected to this calendar
         my $cluster_ids = $self->_cal_cluster_ids( $user, { id => $cal_id } );
         for my $cluster_id (@$cluster_ids) {
            my $rv = $self->_start_cluster( $user,
               { id => $cluster_id, origin => 'cron' } );
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

   my $org_id = $user->org_id;
   my $sql    = <<~"SQL";
      select cron.id as cron_id, cal.id as cal_id
      from cron
      join cal on cron.cal_id = cal.id
      where cal.org_id = $org_id
      and cron.id = $d->{id}
   SQL

   my $cal = $self->sqlite->db->query($sql)->hash;

   return 0 unless $cal->{cron_id};

   $self->_delete_cron_object( $user, $d );
   $self->_delete_cron_row( $user, $d );
   $self->_broadcast_cal( $user, [ $cal->{cal_id} ] );

   return 1;
}

sub delete_cron {
   my ( $self, $user, $d ) = @_;

   my $success = $self->_delete_cron( $user, { id => $d->{id} } );
   my $message = $success ? 'cron deleted' : 'cron not found';
   return { success => $success, message => $message };
}

# cal related subroutines

sub _create_cal {
   my ( $self, $user, $d ) = @_;

   # name tz

   my $id;
   eval {
      $id = $self->sqlite->db->insert(
         'cal',
         {
            name        => $d->{name},
            tz          => $d->{tz},
            description => $d->{description},
            org_id      => $user->org_id
         }
      )->last_insert_id;
   };

   return $id ? $id : undef;
}

sub create_cal {
   my ( $self, $user, $d ) = @_;

   # name id tz cron at

   my $id = $self->_create_cal( $user, $d );

   if ($id) {
      $self->_broadcast_cal( $user, [$id] );
      return { success => 1 };
   }
   else {
      return {
         success => 0,
         message => 'a calendar by that name already exists'
      };
   }
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
   my $results = $self->sqlite->db->select( 'cron', ['*'],
      { cal_id => $d->{id}, org_id => $user->org_id } );
   while ( my $c = $results->hash ) {
      my $next = $self->_cron_next_start( $user, { id => $c->{id} } );
      $c->{next_start} = $next;
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
   $self->sqlite->db->update(
      'cron',
      { next_start => undef },
      { cal_id     => $d->{id}, org_id => $user->org_id }
   );
}

sub _set_cluster_cal_id {
   my ( $self, $user, $d ) = @_;

   # cluster_id cal_id

   # get old cal_id
   my $old_cal = $self->sqlite->db->select( 'cluster', ['cal_id'],
      { id => $d->{cluster_id} } )->hash;
   my $old_cal_id = $old_cal->{cal_id};
   my $new_cal_id = $d->{cal_id};

   # update cal_id
   my $rows = $self->sqlite->db->update(
      'cluster',
      { cal_id => $new_cal_id },
      { id     => $d->{cluster_id} }
   )->rows;

   if ($old_cal_id) {
      my $count = $self->sqlite->db->query(
         "select count(*) as count from cluster where cal_id = $old_cal_id")
        ->hash->{count};

      if ( $count == 0 ) {

         # stop old cal if no clusters subscribed
         $self->_stop_cal( $user, { id => $old_cal_id } );

         # LEGACY
         # delete old calendar if cal is cluster specific (has no name)
         #$self->sqlite->db->delete( 'cal',
         #   { name => undef, id => $old_cal_id, org_id => $user->org_id } );

         # nothing to do so return
         return 1 if $new_cal_id && $old_cal_id == $new_cal_id;
      }
      $self->_broadcast_cal( $user, [$old_cal_id] );
   }

   if ($new_cal_id) {
      my $count = $self->sqlite->db->query(
         "select count(*) as count from cluster where cal_id = $new_cal_id")
        ->hash->{count};

      # start new cal if subscribers went from 0 to 1
      if ( $count == 1 ) {
         $self->_start_cal( $user, { id => $new_cal_id } );
      }
      $self->_broadcast_cal( $user, [$new_cal_id] );
   }
   return $rows ? 1 : 0;
}

sub _cron_next_start {
   my ( $self, $user, $d ) = @_;

   # id (cron id)

   my $c = $self->sqlite->db->query(
"select cron.*, cal.tz from cron join cal on cron.cal_id = cal.id where cron.id = $d->{id}"
   )->hash;
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
      and next_start is not null
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
   my $results =
     $self->sqlite->db->select( 'cluster', ['id'], { cal_id => $d->{id} } );
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
      $cal->{cluster_ids} =
        $self->_cal_cluster_ids( $user, { id => $cal->{id} } );
      $cal->{crons} = $self->_cal_crons( $user, { id => $cal->{id} } );
      $cal->{next_start} =
        $self->_cal_next_start( $user, { id => $cal->{id} } );
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
   return $cal_info->{id}
     ? { success => 1, cals    => \@all }
     : { success => 0, message => 'cal not found' };
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
   return { success => 1, cals => \@all };
}

sub _add_cron {
   my ( $self, $user, $d ) = @_;

   # name description start end

   my $cal_info =
     $self->_cal_info( $user, { id => $d->{cal_id}, name => $d->{cal} } );
   return { success => 0, message => 'calendar not found' }
     unless $cal_info->{id};

   my $id;
   eval {
      $id = $self->_create_cron_row(
         $user,
         {
            name        => $d->{name},
            begin       => $d->{begin},
            expire      => $d->{expire},
            description => $d->{description},
            cal_id      => $cal_info->{id},
         }
      );
   };

   if ($id) {
      $self->_broadcast_cal( $user, [ $cal_info->{id} ] );
   }
   else {
      return {
         success => 0,
         message =>
           'invalid or an identical cron already exists in that calendar'
      };
   }

   # only start when subscribers exist
   my $count = $self->sqlite->db->query(
      "select count(*) as count from cluster where cal_id = $cal_info->{id}")
     ->hash->{count};
   return { success => 1, message => 'cron created but not started' }
     unless $count;

   my $rv = $self->_create_cron_object( $user, { id => $id } );
   return $rv;
}

sub _add_at {
   my ( $self, $user, $d ) = @_;

   # at name description start end cal cal_id

   return { success => 0, message => 'only future events may be scheduled' }
     if time > $d->{name};
   return { success => 0, message => 'event too far in the future' }
     if $d->{name} > 4102466400;    # max year 2100

   my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
     localtime( $d->{name} );

   $d->{name} = sprintf( "%d %d %d %d %d ? %d",
      $sec, $min, $hour, $mday, $mon + 1, $year += 1900 );

   my $rv = $self->_add_cron( $user, $d );
   return $rv;
}

sub update_cal {
   my ( $self, $user, $d ) = @_;

   # name id cron cron_id at remove

   my $cal = $self->_cal_info( $user, $d );
   return { success => 0, message => 'cal not found' } unless $cal->{id};

   my $update_hash =
     { map { $_, $d->{$_} } grep { exists $d->{$_} } (qw(description tz)) };
   $update_hash->{name} = $d->{newname} if $d->{newname};

   if ( scalar keys %$update_hash ) {
      $self->sqlite->db->update( 'cal', $update_hash,
         { id => $cal->{id}, org_id => $user->org_id } );
      $self->_broadcast_cal( $user, [ $cal->{id} ] );
      return { success => 1 };
   }
   else {
      return { success => 0 };
   }
}

sub _delete_cal {
   my ( $self, $user, $d ) = @_;

   # id (cal id)

   my $rows = $self->sqlite->db->delete( 'cal', { id => $d->{id} } )->rows;
   if ($rows) {
      $self->_broadcast_cal( $user, [ $d->{id} ] );
      return 1;
   }
   else {
      return 0;
   }
}

sub delete_cal {
   my ( $self, $user, $d ) = @_;

   # id name

   my $cal = $self->_cal_info( $user, $d );

   $self->_stop_cal( $user, { id => $cal->{id} } );
   my $success = $self->_delete_cal( $user, { id => $cal->{id} } );
   return { success => $success, %$cal };
}

sub find_stats {
   my ( $self, $user, $d ) = @_;

   my $since = $d->{since} || ( time() - 86400 );

   my $stats = $self->sqlite->db->query( "
        SELECT
          COUNT(*) as runs_today,

          SUM(CASE WHEN jl.exit_code != 0 
                   OR (jl.signal IS NOT NULL AND jl.signal != 0)
                   THEN 1 ELSE 0 END) as failed_runs_today,

          MAX(CASE WHEN jl.ended > jl.started THEN jl.ended - jl.started ELSE 0 END) as longest_duration

        FROM job_log jl
        JOIN job j ON jl.job_id = j.id
        JOIN cluster c ON j.cluster_id = c.id
        WHERE jl.ended >= ?
          AND c.org_id = ?
    ", $since, $user->org_id )->hash;

   my $runs_today    = $stats->{runs_today}        // 0;
   my $failed_today  = $stats->{failed_runs_today} // 0;
   my $success_count = $runs_today - $failed_today;

   my $success_rate =
     $runs_today > 0
     ? sprintf( "%.1f", 100.0 * $success_count / $runs_today )
     : 100;

   return {
      success           => 1,
      command_reply     => 'find_stats',
      success_rate      => $success_rate + 0,
      runs_today        => $runs_today,
      failed_runs_today => $failed_today,
      longest_duration  => $stats->{longest_duration} // 0,
      calculated_at     => time()
   };
}

sub get_documentation {
   my ( $self, $user, $d ) = @_;

   my $section = $d->{section} // 'overview';
   my $format  = $d->{format}  // 'markdown';

   my $content = $self->_get_doc_content( $section, $format );

   return { success => 0, message => 'doc not found' } unless $content;

   return {
      success => 1,
      section => $section,
      format  => $format,
      content => $content,
   };
}

sub _get_doc_content {
   my ( $self, $section, $format ) = @_;

   if ( $format eq 'summary' ) {
      return $section eq 'all'
        ? $self->doc_cache->{summaries}
        : ( $self->doc_cache->{summaries}{$section}
           // $self->doc_cache->{summaries}{'overview'} );
   }

   # Full markdown
   return $section eq 'all'
     ? $self->doc_cache->{full}
     : ( $self->doc_cache->{full}{$section}
        // "Document not found: $section.md" );
}

# command routing

sub routing {
   state %routing = (

      # Docs
      'get_documentation' => [
         'get_documentation', 1, [ { section => 'n', format => 'n' }, {} ], 1
      ],

      # Stats
      'find_stats' => [ 'find_stats', 1, [ {}, { since => 'i' } ], 1 ],

      # Org related
      'update_org' =>
        [ 'update_org', 1, [ {}, { description => 'd', name => 'n' } ], 1 ],
      'read_org' => [ 'read_org', 1, [ {}, {} ], 0 ],

      # User related
      'create_user' => [
         'create_user',
         3,
         [
            { name => 'n' }, { team_member => 'i', email => 'e', level => 'i' }
         ],
         1
      ],
      'read_user'   => [ 'read_user', 0, [ {}, {} ], 0 ],
      'update_user' =>
        [ 'update_user', 1, [ {}, { mode => 'm', name => 'n' } ], 1 ],
      'delete_user' => [ 'delete_user', 3, [ { id    => 'i' }, {} ], 1 ],
      'delete_me'   => [ 'delete_me',   1, [ {}, {} ], 1 ],
      'login_user'  => [ 'login_user',  0, [ { token => 's' }, {} ], 0 ],
      'new_token'   => [ 'new_token',   1, [ {}, {} ], 0 ],
      'rotate_execution_token' =>
        [ 'rotate_execution_token', 1, [ {}, {} ], 0 ],
      'register_user' =>
        [ 'register_user', 0, [ { email => 'e' }, { team_member => 'i' } ], 0 ],

      # Job related
      'create_job' => [
         'create_job',
         1,
         [
            { name => 'n', script => 'c', server => 'srv' },
            {
               parent_id     => 'i',
               needs         => 'a:s',
               needs_ids     => 'a:i',
               json          => 'j',
               description   => 'd',
               retrys        => 'i',
               loops         => 'i',
               delay         => 'i',
               priority      => 'i',
               mode          => 'm',
               needs_any     => 'a:s',
               needs_any_ids => 'a:i',

               #on_fail       => 'p',
               #on_fail_id    => 'i',
            }
         ],
         1
      ],
      'read_job' => [
         'read_job',
         1,
         [ {}, { name => 'n', id => 'i', cluster_id => 'i' } ],
         1
      ],

      'update_job_config' => [
         'update_job_config',
         1,
         [
            {},    # no required params
            {
               id            => 'i',
               name          => 'n',
               newname       => 'n',
               description   => 'd',
               script        => 'c',
               server        => 'srv',
               server_id     => 'i?',
               needs         => 'a:s',
               needs_ids     => 'a:i',
               needs_any_ids => 'a:i',
               needs_any     => 'a:s',
               json          => 'j',
               mode          => 'm',
               retrys        => 'i',
               loops         => 'i',
               delay         => 'i',
               priority      => 'i',

               #on_fail       => 'p',
               #on_fail_id    => 'i?',
               remove_needs => 'i',
            }
         ],
         1    # billable
      ],

      'update_job_state' => [
         'update_job_state',
         1,
         [
            {},    # no required params
            {
               id        => 'i',
               state     => 'st',
               pid       => 'i',
               ppid      => 'i',
               exit_code => 'i',
               signal    => 'sig',
               mem       => 'f',
               cpu       => 'f',
               started   => 'i',
               ended     => 'i',
               log_id    => 'i',
            }
         ],
         0    # do not count (automatic)
      ],
      'delete_job' => [
         'delete_job', 1, [ {}, { name => 'n', id => 'i', force => 'b' } ], 1
      ],
      'start_job' =>
        [ 'start_job', 1, [ {}, { name => 'n', id => 'i', force => 'b' } ], 1 ],
      'watch_job' => [
         'watch_job',
         99,
         [
            {},
            {
               name      => 'n',
               id        => 'i',
               server_id => 'i',
               server    => 'srv',
               pid       => 'i',
               match     => 'c'
            }
         ],
         1
      ],
      'kill_job'    => [ 'kill_job', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'nice_job'    => [ 'nice_job', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'hold_job'    => [ 'hold_job', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'release_job' =>
        [ 'release_job', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'ice_job'   => [ 'ice_job',   1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'prune_job' => [ 'prune_job', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'melt_job'  => [ 'melt_job',  1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'complete_job' =>
        [ 'complete_job', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],

      # Cluster related
      'create_cluster' => [
         'create_cluster',
         1,
         [
            { name => 'n' },
            {
               parent_id     => 'i',
               needs         => 'a:s',
               needs_ids     => 'a:i',
               json          => 'j',
               description   => 'd',
               cron          => 'ct',
               at            => 'i',
               cal           => 'n',
               cal_id        => 'i?',
               tz            => 'tz',
               clonable      => 'b',
               mode          => 'm',
               loops         => 'i',
               needs_any     => 'a:s',
               needs_any_ids => 'a:i',
               on_fail       => 'p',
               on_fail_id    => 'i?',
            }
         ],
         1
      ],
      'read_cluster' =>
        [ 'read_cluster', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'update_cluster' => [
         'update_cluster',
         1,
         [
            {},
            {
               id            => 'i',
               name          => 'n',
               needs         => 'a:s',
               needs_ids     => 'a:i',
               json          => 'j',
               newname       => 'n',
               description   => 'd',
               cron          => 'ct',
               at            => 'i',
               cal           => 'n',
               cal_id        => 'i?',
               tz            => 'tz',
               mode          => 'm',
               clonable      => 'b',
               loops         => 'i',
               needs_any     => 'a:s',
               needs_any_ids => 'a:i',
               on_fail       => 'p',
               on_fail_id    => 'i',
               remove_needs  => 'i',
            }
         ],
         1
      ],
      'delete_cluster' =>
        [ 'delete_cluster', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'change_cluster' =>
        [ 'change_cluster', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'find_cluster' =>
        [ 'find_cluster', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'reset_cluster' =>
        [ 'reset_cluster', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'start_cluster' => [
         'start_cluster',                                  1,
         [ {}, { id => 'i', name => 'n', force => 'b' } ], 1
      ],
      'clone_cluster' => [
         'clone_cluster',                                      1,
         [ {}, { id => 'i', name => 'n', parent_id => 'i' } ], 1
      ],
      'ice_cluster' =>
        [ 'ice_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'prune_cluster' =>
        [ 'prune_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'melt_cluster' =>
        [ 'melt_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'hold_cluster' =>
        [ 'hold_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'kill_cluster' =>
        [ 'kill_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'release_cluster' =>
        [ 'release_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'complete_cluster' =>
        [ 'complete_cluster', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],

      # Calendar related
      'create_cal' => [
         'create_cal',                                            1,
         [ { name => 'n', tz => 'tz' }, { description => 'd' } ], 1
      ],
      'read_cal'   => [ 'read_cal', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'find_cal'   => [ 'find_cal', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'update_cal' => [
         'update_cal',
         1,
         [
            {},
            {
               id          => 'i',
               name        => 'n',
               tz          => 'tz',
               description => 'd',
               newname     => 'n'
            }
         ],
         1
      ],
      'delete_cal' =>
        [ 'delete_cal', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],

      # Crons / Ats
      'create_cron' => [
         'create_cron',
         1,
         [
            { name => 'ct' },
            {
               description => 'd',
               cal         => 'n',
               cal_id      => 'i',
               begin       => 'i',
               expire      => 'i'
            }
         ],
         1
      ],
      'delete_cron' =>
        [ 'delete_cron', 1, [ {}, { name => 'ct', id => 'i' } ], 1 ],
      'create_at' => [
         'create_at',
         1,
         [ { name => 'i' }, { description => 'd', cal => 'n', cal_id => 'i' } ],
         1
      ],
      'update_cron' => [
         'update_cron',
         1,
         [
            { id => 'i' },
            {
               newname     => 'ct',
               description => 'd',
               begin       => 'i',
               expire      => 'i',
               cal         => 'n',
               cal_id      => 'i'
            }
         ],
         1
      ],

      # Logs
      'find_log' => [ 'find_log', 1, [ {}, { name => 'n', id => 'i' } ], 1 ],
      'read_log' =>
        [ 'read_log', 1, [ {}, { name => 'n', id => 'i', log_id => 'i' } ], 1 ],

      # Monitor related
      'create_monitor' => [
         'create_monitor',
         1,
         [
            { name     => 'n',  user => 'n', host => 'srv' },
            { password => 'pw', port => 'i' }
         ],
         1
      ],
      'find_monitor' =>
        [ 'find_monitor', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'read_monitor' =>
        [ 'read_monitor', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'update_monitor' => [
         'update_monitor',
         1,
         [
            {},
            {
               id       => 'i',
               port     => 'i',
               name     => 'n',
               newname  => 'n',
               user     => 'n',
               host     => 'srv',
               password => 'pw',
            }
         ],
         1
      ],
      'delete_monitor' =>
        [ 'delete_monitor', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'ssh_copy' => [
         'ssh_copy',                                                          1,
         [ { name => 'n', user => 'n', host => 'p' }, { password => 'pw' } ], 1
      ],
      'stop_monitor' =>
        [ 'stop_monitor', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'start_monitor' =>
        [ 'start_monitor', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'upgrade_monitor' =>
        [ 'upgrade_monitor', 1, [ {}, { id => 'i', name => 'n' } ], 1 ],
      'active_pids'    => [ 'active_pids', 1, [ { id => 'i' }, {} ], 0 ],
      'sync'           => [ 'sync',        1, [ {},            {} ], 1 ],
      'update_sysinfo' => [
         'update_sysinfo',
         1,
         [
            {
               used_memory      => 'i',
               total_memory     => 'i',
               free_memory      => 'i',
               used_disk        => 'i',
               total_disk       => 'i',
               free_disk        => 'i',
               uptime           => 'f',
               pids             => 'a:h',
               zombies          => 'a:i',
               id               => 'i',
               cpu_percent      => 'f',
               load_1           => 'f',
               load_5           => 'f',
               load_15          => 'f',
               used_swap        => 'i',
               total_swap       => 'i',
               free_swap        => 'i',
               open_files       => 'i',
               max_files        => 'i',
               total_processes  => 'i',
               zombie_processes => 'i',
               net_rx_bytes     => 'i',
               net_tx_bytes     => 'i',
               root_used_disk   => 'i',
               root_total_disk  => 'i',
               root_free_disk   => 'i',
            },
            {}
         ],
         1
      ],
   );

   return \%routing;
}

EV::run;

1;
