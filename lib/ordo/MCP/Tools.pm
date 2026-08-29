package ordo::MCP::Tools;
use Mojo::Base -base;
use MIME::Base64 ();
use Mojo::JSON   qw(encode_json);

# MCP tool names match native WebSocket/HTTP command names.
# MCP `json` arg: object -> JSON string; null/empty -> '' (clear via API)
sub _normalize_json_arg {
   my ($payload) = @_;
   return $payload unless exists $payload->{json};
   my $j = $payload->{json};
   if ( !defined $j || ( !ref($j) && $j eq '' ) ) {
      $payload->{json} = '';
   }
   elsif ( ref $j ) {
      $payload->{json} = encode_json($j);
   }
   return $payload;
}

sub get_tools {
   return {

      get_documentation => {
         description =>
           'Retrieve Ordo documentation. Call this first in a new session '
           . '(section "api", "overview", or "quickstart").',
         inputSchema => {
            type       => 'object',
            properties => {
               section => {
                  type        => 'string',
                  description => 'Documentation section',
                  enum        => [
                     'overview', 'quickstart', 'core-concepts', 'jobs-and-clusters',
                     'calendars-and-crons', 'advanced-topics', 'connecting-to-ai', 'faq',
                     'api', 'agent-protocol', 'cli', 'dashboard', 'stats-polling',
                     'settings', 'private-deployments', 'self-hosted', 'all'
                  ],
                  default => 'overview',
               },
               format => {
                  type        => 'string',
                  enum        => [ 'markdown', 'summary' ],
                  default     => 'markdown',
               },
            },
            required => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request(
               $c->stash('user'),
               {
                  command => 'get_documentation',
                  section => $args->{section} // 'overview',
                  format  => $args->{format}  // 'markdown',
               }
            );
         },
      },

      find_cluster => {
         description =>
           'Look up clusters by path or name. Returns a flat clusters[] array; '
           . 'each cluster has parent_id and nested jobs. Child clusters are '
           . 'siblings in the array, not nested. Defaults to /root.',
         inputSchema => {
            type       => 'object',
            properties => {
               name => {
                  type        => 'string',
                  description => 'Cluster path or name (e.g. /root, Monitoring)',
                  default     => '/root',
               },
               filter => {
                  type => 'string',
                  enum => [ 'all', 'running', 'failed', 'waiting' ],
               },
            },
            required => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'find_cluster', name => $args->{name} // '/root' } );
         },
      },

      read_job => {
         description => 'Full details for a job (state, script, dependencies, limits).',
         inputSchema => {
            type       => 'object',
            properties => { id => { type => 'integer', description => 'Job ID' } },
            required   => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'read_job', id => $args->{id} } );
         },
      },

      read_cluster => {
         description =>
           'Full details for a cluster including jobs and state. Preferred progress check after start.',
         inputSchema => {
            type       => 'object',
            properties => { id => { type => 'integer', description => 'Cluster ID' } },
            required   => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'read_cluster', id => $args->{id} } );
         },
      },

      find_monitor => {
         description =>
           'List servers with live metrics. Call before create_job for a valid server_id.',
         inputSchema => { type => 'object', properties => {}, required => [] },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'find_monitor' } );
         },
      },

      find_cal => {
         description => 'List calendars, cron expressions, and attached clusters.',
         inputSchema => { type => 'object', properties => {}, required => [] },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'find_cal' } );
         },
      },

      create_job => {
         description =>
           'Create a job in a cluster. parent_id = owning cluster. Prefer a shebang. needs_ids=AND, needs_any_ids=OR.',
         inputSchema => {
            type       => 'object',
            properties => {
               name      => { type => 'string', description => 'Short job name' },
               script    => { type => 'string', description => 'Full script (plain text); base64-encoded for the API' },
               parent_id => { type => 'integer', description => 'Owning cluster ID' },
               server_id => { type => 'integer', description => 'Server ID from find_monitor' },
               description => { type => 'string' },
               needs_ids => { type => 'array', items => { type => 'integer' } },
               needs_any_ids => { type => 'array', items => { type => 'integer' } },
               retrys => { type => 'integer' },
               loops  => { type => 'integer' },
               delay  => { type => 'integer' },
               json   => { type => 'object', description => 'Durable JSON object (max 64KB). null clears.' },
               max_runtime_seconds    => { type => 'integer' },
               max_runtime_cluster_id => { type => 'integer' },
            },
            required => [ 'name', 'script', 'parent_id', 'server_id' ],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            if ( $payload->{script} && !$payload->{script_b64} ) {
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'create_job', %$payload } );
         },
      },

      create_cluster => {
         description => 'Create a cluster. parent_id defaults to root if omitted.',
         inputSchema => {
            type       => 'object',
            properties => {
               name => { type => 'string' },
               parent_id => { type => 'integer' },
               on_fail_id => { type => 'integer' },
               on_overdue_id => { type => 'integer' },
               auto_start => { type => 'boolean', default => 1 },
               description => { type => 'string' },
               cal_id => { type => 'integer' },
               needs_ids => { type => 'array', items => { type => 'integer' } },
               needs_any_ids => { type => 'array', items => { type => 'integer' } },
               loops => { type => 'integer' },
               json  => { type => 'object' },
            },
            required => ['name'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'create_cluster', %$payload } );
         },
      },

      create_cal => {
         description =>
           'Create a calendar. Then use create_cron; attach to a cluster with update_cluster (cal_id).',
         inputSchema => {
            type       => 'object',
            properties => {
               name => { type => 'string' },
               tz   => { type => 'string', description => 'IANA timezone e.g. America/Chicago' },
               description => { type => 'string' },
            },
            required => [ 'name', 'tz' ],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'create_cal', %$args } );
         },
      },

      update_job_config => {
         description => 'Update an existing job (native command: update_job_config).',
         inputSchema => {
            type       => 'object',
            properties => {
               id => { type => 'integer' },
               newname => { type => 'string' },
               script  => { type => 'string' },
               description => { type => 'string' },
               server_id => { type => 'integer' },
               needs_ids => { type => 'array', items => { type => 'integer' } },
               needs_any_ids => { type => 'array', items => { type => 'integer' } },
               retrys => { type => 'integer' },
               loops  => { type => 'integer' },
               delay  => { type => 'integer' },
               json   => { type => 'object' },
               max_runtime_seconds => { type => 'integer' },
               max_runtime_cluster_id => { type => 'integer' },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            if ( $payload->{script} && !$payload->{script_b64} ) {
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'update_job_config', %$payload } );
         },
      },

      update_cluster => {
         description => 'Update a cluster (calendar, handlers, dependencies, etc.).',
         inputSchema => {
            type       => 'object',
            properties => {
               id => { type => 'integer' },
               newname => { type => 'string' },
               description => { type => 'string' },
               cal_id => { type => 'integer' },
               auto_start => { type => 'boolean' },
               needs_ids => { type => 'array', items => { type => 'integer' } },
               needs_any_ids => { type => 'array', items => { type => 'integer' } },
               on_fail_id => { type => 'integer' },
               on_overdue_id => { type => 'integer' },
               loops => { type => 'integer' },
               json  => { type => 'object' },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'update_cluster', %$payload } );
         },
      },

      create_cron => {
         description =>
           "Add a cron expression to a calendar.\n"
           . "name = Quartz cron (e.g. 0 0 9 * * ? *) or 5-field Unix (auto-expanded).\n"
           . "cal_id = calendar id. Optional description is stored on the cron row.\n"
           . "Day-of-week: Monday=1 .. Sunday=7.",
         inputSchema => {
            type       => 'object',
            properties => {
               name => {
                  type        => 'string',
                  description => 'Quartz (6–7 fields) or Unix 5-field cron expression',
               },
               cal_id => { type => 'integer', description => 'Calendar ID' },
               description => {
                  type        => 'string',
                  description => 'Free-text label stored on the cron row',
               },
            },
            required => [ 'name', 'cal_id' ],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'create_cron', %$args } );
         },
      },

      delete_cron => {
         description => 'Delete a cron entry by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'delete_cron', id => $args->{id} } );
         },
      },

      delete_cal => {
         description => 'Delete a calendar and its cron entries.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'delete_cal', id => $args->{id} } );
         },
      },

      start_job => {
         description => 'Start a job by id. MCP is fire-and-forget unless the user asks for status/logs.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'start_job', id => $args->{id} } );
         },
      },
      start_cluster => {
         description =>
           'Start a cluster by id. Fire-and-forget on MCP: report success and stop unless user asks for status.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'start_cluster', id => $args->{id} } );
         },
      },
      kill_job => {
         description => 'Kill a running job by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'kill_job', id => $args->{id} } );
         },
      },
      kill_cluster => {
         description => 'Kill a running cluster by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'kill_cluster', id => $args->{id} } );
         },
      },
      hold_job => {
         description => 'Hold a job by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'hold_job', id => $args->{id} } );
         },
      },
      hold_cluster => {
         description => 'Hold a cluster by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'hold_cluster', id => $args->{id} } );
         },
      },
      release_job => {
         description => 'Release a held job by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'release_job', id => $args->{id} } );
         },
      },
      release_cluster => {
         description => 'Release a held cluster by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'release_cluster', id => $args->{id} } );
         },
      },
      ice_job => {
         description => 'Ice (strong hold) a job by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'ice_job', id => $args->{id} } );
         },
      },
      ice_cluster => {
         description => 'Ice (strong hold) a cluster by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'ice_cluster', id => $args->{id} } );
         },
      },
      melt_job => {
         description => 'Melt (un-ice) a job by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'melt_job', id => $args->{id} } );
         },
      },
      melt_cluster => {
         description => 'Melt (un-ice) a cluster by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'melt_cluster', id => $args->{id} } );
         },
      },
      complete_job => {
         description => 'Mark a job complete by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'complete_job', id => $args->{id} } );
         },
      },
      complete_cluster => {
         description => 'Mark a cluster complete by id.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'complete_cluster', id => $args->{id} } );
         },
      },
      delete_job => {
         description => 'Delete a job by id. Permanent.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'delete_job', id => $args->{id} } );
         },
      },
      delete_cluster => {
         description => 'Delete a cluster by id. Permanent.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'delete_cluster', id => $args->{id} } );
         },
      },
      reset_cluster => {
         description => 'Reset a cluster to a clean startable state.',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'reset_cluster', id => $args->{id} } );
         },
      },
      clone_cluster => {
         description => 'Clone a cluster (copy only; does not start).',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'clone_cluster', id => $args->{id} } );
         },
      },

      read_log => {
         description =>
           'Most recent log output for a job. Request id is the job id. '
           . 'Reply id is the log row; reply also has job_id and log_id. '
           . 'Optional log_id selects a specific run.',
         inputSchema => {
            type => 'object',
            properties => {
               id => { type => 'integer', description => 'Job ID' },
               log_id => {
                  type        => 'integer',
                  description => 'Specific run log_id (omit for latest)',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'read_log', %$args } );
         },
      },
      find_log => {
         description => 'History of past runs for a job (timestamps + exit codes).',
         inputSchema => {
            type => 'object',
            properties => { id => { type => 'integer', description => 'Job ID' } },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'find_log', id => $args->{id} } );
         },
      },
      sync => {
         description => 'Reconcile scheduler state with processes on servers.',
         inputSchema => { type => 'object', properties => {}, required => [] },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'sync' } );
         },
      },
      read_user => {
         description => 'Current authenticated user.',
         inputSchema => { type => 'object', properties => {}, required => [] },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'read_user' } );
         },
      },
      read_org => {
         description => 'Organization details (tier, limits, usage).',
         inputSchema => { type => 'object', properties => {}, required => [] },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'read_org' } );
         },
      },
      add_server => {
         description =>
           'Adding servers is only supported in the Web UI (Servers tab).',
         inputSchema => { type => 'object', properties => {}, required => [] },
         handler => sub {
            return {
               success => 0,
               message =>
'Use the Web UI Servers tab to add servers. Agents cannot add servers via MCP.',
            };
         },
      },

   };
}

1;
