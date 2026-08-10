# lib/ordo/MCP/Tools.pm
package ordo::MCP::Tools;
use Mojo::Base -base;
use MIME::Base64 ();

sub get_tools {
   return {

      # ------------------------------------------------------------------
      # Documentation
      # ------------------------------------------------------------------
      get_documentation => {
         description =>
           'Retrieve Ordo documentation. Call this first in a new session '
           . '(section "overview" or "quickstart") to learn concepts, cron rules, and workflows.',
         inputSchema => {
            type       => 'object',
            properties => {
               section => {
                  type        => 'string',
                  description => 'Documentation section',
                  enum        => [
                     'overview',            'quickstart',
                     'core-concepts',       'jobs-and-clusters',
                     'calendars-and-crons', 'advanced-topics',
                     'connecting-to-ai',    'faq',
                     'rest-api',            'cli',
                     'dashboard',           'stats-polling',
                     'settings',            'private-deployments',
                     'self-hosted',         'all'
                  ],
                  default => 'overview',
               },
               format => {
                  type        => 'string',
                  description => 'Output format',
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

      # ------------------------------------------------------------------
      # Browsing / Inspection
      # ------------------------------------------------------------------
      list_jobs => {
         description =>
'List the hierarchical job/cluster tree. Use this to discover existing structure '
           . 'before creating or modifying anything. Defaults to /root.',
         inputSchema => {
            type       => 'object',
            properties => {
               path => {
                  type        => 'string',
                  description => 'Path starting with /root',
                  default     => '/root',
               },
               filter => {
                  type        => 'string',
                  description => 'Optional state filter',
                  enum        => [ 'all', 'running', 'failed', 'waiting' ],
               },
            },
            required => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'find_cluster', name => $args->{path} // '/root' }
            );
         },
      },

      get_job_details => {
         description =>
'Get full details for a specific job (state, script, dependencies, limits, etc.).',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Job ID',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'read_job', id => $args->{id} } );
         },
      },

      get_cluster_details => {
         description =>
'Get full details for a specific cluster, including its jobs and current state. '
           . 'Preferred way to check progress after starting a workflow.',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Cluster ID',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'read_cluster', id => $args->{id} } );
         },
      },

      list_servers => {
         description =>
'List all registered servers with live metrics (CPU, memory, disk, load, uptime). '
           . 'Always call this before create_job so you can choose a valid server_id.',
         inputSchema => {
            type       => 'object',
            properties => {},
            required   => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'find_monitor' } );
         },
      },

      list_calendars => {
         description =>
'List all calendars, their cron expressions, and which clusters are attached to them.',
         inputSchema => {
            type       => 'object',
            properties => {},
            required   => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'find_cal' } );
         },
      },

      # ------------------------------------------------------------------
      # Create
      # ------------------------------------------------------------------
      create_job => {
         description => 'Create a new job inside an existing cluster. '
           . 'parent_id is the cluster ID that will own the job. '
           . 'Prefer a shebang (#!/bin/sh, #!/usr/bin/env python3, …). '
           . 'Dependencies: needs_ids = AND, needs_any_ids = OR.',
         inputSchema => {
            type       => 'object',
            properties => {
               name => {
                  type        => 'string',
                  description => 'Short job name',
               },
               script => {
                  type        => 'string',
                  description =>
'Full script content (plain text). Automatically base64-encoded.',
               },
               parent_id => {
                  type        => 'integer',
                  description => 'Cluster ID that will contain this job',
               },
               server_id => {
                  type        => 'integer',
                  description => 'Server ID to run on (from list_servers)',
               },
               description => { type => 'string' },
               needs_ids   => {
                  type        => 'array',
                  items       => { type => 'integer' },
                  description => 'IDs that must ALL succeed (AND)',
               },
               needs_any_ids => {
                  type        => 'array',
                  items       => { type => 'integer' },
                  description => 'IDs where only ONE needs to succeed (OR)',
               },
               retrys                 => { type => 'integer' },
               loops                  => { type => 'integer' },
               delay                  => { type => 'integer' },
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
            $c->app->request( $c->stash('user'),
               { command => 'create_job', %$payload } );
         },
      },

      create_cluster => {
         description =>
           'Create a new cluster (container for jobs and/or nested clusters). '
           . 'If parent_id is omitted the cluster is placed under root.',
         inputSchema => {
            type       => 'object',
            properties => {
               name => {
                  type        => 'string',
                  description => 'Cluster name',
               },
               parent_id => {
                  type        => 'integer',
                  description => 'Parent cluster ID (defaults to root)',
               },
               on_fail_id    => { type => 'integer' },
               on_overdue_id => { type => 'integer' },
               auto_start    => {
                  type    => 'boolean',
                  default => 1,
               },
            },
            required => ['name'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'create_cluster', %$args } );
         },
      },

      create_calendar => {
         description =>
           'Create a named calendar (collection of Quartz cron expressions). '
           . 'After creation use add_cron, then attach the calendar to a cluster with update_cluster.',
         inputSchema => {
            type       => 'object',
            properties => {
               name => {
                  type        => 'string',
                  description => 'Calendar name',
               },
               tz => {
                  type        => 'string',
                  description => 'IANA timezone, e.g. America/Chicago',
               },
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

      # ------------------------------------------------------------------
      # Update
      # ------------------------------------------------------------------
      update_job => {
         description =>
           'Update an existing job (name, script, dependencies, limits, etc.).',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Job ID',
               },
               newname => { type => 'string' },
               script  => {
                  type        => 'string',
                  description => 'New script content (plain text)',
               },
               description => { type => 'string' },
               server_id   => { type => 'integer' },
               needs_ids   => {
                  type  => 'array',
                  items => { type => 'integer' },
               },
               needs_any_ids => {
                  type  => 'array',
                  items => { type => 'integer' },
               },
               retrys                 => { type => 'integer' },
               loops                  => { type => 'integer' },
               delay                  => { type => 'integer' },
               max_runtime_seconds    => { type => 'integer' },
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
            $c->app->request( $c->stash('user'),
               { command => 'update_job_config', %$payload } );
         },
      },

      update_cluster => {
         description =>
'Update an existing cluster. Use cal_id to attach or detach a calendar. '
           . 'Also used to set on_fail_id / on_overdue_id and dependencies.',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Cluster ID',
               },
               newname     => { type => 'string' },
               description => { type => 'string' },
               cal_id      => {
                  type        => 'integer',
                  description =>
                    'Calendar ID to attach (omit or null to detach)',
               },
               auto_start => { type => 'boolean' },
               needs_ids  => {
                  type  => 'array',
                  items => { type => 'integer' },
               },
               needs_any_ids => {
                  type  => 'array',
                  items => { type => 'integer' },
               },
               on_fail_id    => { type => 'integer' },
               on_overdue_id => { type => 'integer' },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'update_cluster', %$args } );
         },
      },

      # ------------------------------------------------------------------
      # Calendars & Cron
      # ------------------------------------------------------------------
      add_cron => {
         description =>
           "Add a Quartz cron expression to an existing calendar.\n\n"
           . "Format (6 or 7 fields): seconds minutes hours day-of-month month day-of-week [year]\n\n"
           . "Important day-of-week convention in Ordo: Monday=1 … Sunday=7 "
           . "(differs from classic Quartz where Sunday=1).\n\n"
           . "Useful patterns:\n"
           . "  0 0 0 1 1 ? *     → New Year's Day\n"
           . "  0 0 0 ? 1 1#3 *   → 3rd Monday in January (MLK)\n"
           . "  0 0 0 ? 5 1L *    → last Monday in May (Memorial Day)\n"
           . "  0 0 0 ? 11 4#4 *  → 4th Thursday in November (Thanksgiving)\n"
           . "  0 0 9 ? * 1-5 *   → 09:00 every weekday",
         inputSchema => {
            type       => 'object',
            properties => {
               name => {
                  type        => 'string',
                  description => 'The Quartz cron expression itself',
               },
               cal_id => {
                  type        => 'integer',
                  description => 'Target calendar ID',
               },
               description => {
                  type        => 'string',
                  description => 'Human-readable label, e.g. "Thanksgiving"',
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
         description => 'Delete a single cron entry from a calendar.',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Cron entry ID (not the calendar ID)',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'delete_cron', id => $args->{id} } );
         },
      },

      delete_calendar => {
         description => 'Delete a calendar and all of its cron entries.',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Calendar ID',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'delete_cal', id => $args->{id} } );
         },
      },

      # ------------------------------------------------------------------
      # Lifecycle
      # ------------------------------------------------------------------
      manage_job => {
         description => 'Perform a lifecycle action on a single job. '
           . 'Common actions: start, kill, hold, release, complete, delete, reset.',
         inputSchema => {
            type       => 'object',
            properties => {
               action => {
                  type => 'string',
                  enum => [
                     qw(start kill hold release ice melt complete delete reset)
                  ],
                  description => 'Action to perform',
               },
               id => {
                  type        => 'integer',
                  description => 'Job ID',
               },
            },
            required => [ 'action', 'id' ],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $cmd = $args->{action} . '_job';
            $c->app->request( $c->stash('user'),
               { command => $cmd, id => $args->{id} } );
         },
      },
      manage_cluster => {
         description =>
           'Perform a lifecycle action on a cluster (and its jobs). '
           . 'Most common: start (runs the whole workflow), kill, hold, reset, delete.'
           . "\n\n"
           . '**Important agent behavior – fire-and-forget:**' . "\n"
           . 'When you start a cluster, treat it as fire-and-forget. '
           . 'After a successful start, report what was started and stop. '
           . 'Do **not** automatically poll for completion or status. '
           . 'Only check status or logs if the user explicitly asks '
           . '(e.g. “did it finish?”, “show me the logs”, “what failed?”).',
         inputSchema => {
            type       => 'object',
            properties => {
               action => {
                  type => 'string',
                  enum => [
                     qw(start kill hold release ice melt complete delete reset)
                  ],
                  description => 'Action to perform',
               },
               id => {
                  type        => 'integer',
                  description => 'Cluster ID',
               },
            },
            required => [ 'action', 'id' ],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $cmd = $args->{action} . '_cluster';
            $c->app->request( $c->stash('user'),
               { command => $cmd, id => $args->{id} } );
         },
      },
      clone_cluster => {
         description =>
'Clone a cluster (identical copy). Most often used from an On Overdue handler '
           . 'so a late run does not block the next scheduled occurrence.',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Cluster ID to clone',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'clone_cluster', %$args } );
         },
      },

      # ------------------------------------------------------------------
      # Logs & Utility
      # ------------------------------------------------------------------
      read_log => {
         description =>
'Read the most recent log output for a job (start/end time, exit code, stdout/stderr).',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Job ID',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'read_log', id => $args->{id} } );
         },
      },

      find_logs => {
         description =>
           'Get history of past runs for a job (timestamps + exit codes).',
         inputSchema => {
            type       => 'object',
            properties => {
               id => {
                  type        => 'integer',
                  description => 'Job ID',
               },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'find_log', id => $args->{id} } );
         },
      },

      sync => {
         description =>
           'Reconcile scheduler state with actual processes on remote servers. '
           . 'Marks missing PIDs as zombie. Useful after network issues or manual kills.',
         inputSchema => {
            type       => 'object',
            properties => {},
            required   => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'sync' } );
         },
      },

      # ------------------------------------------------------------------
      # User / Org
      # ------------------------------------------------------------------
      read_user => {
         description =>
           'Return information about the currently authenticated user.',
         inputSchema => {
            type       => 'object',
            properties => {},
            required   => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'read_user' } );
         },
      },

      read_org => {
         description =>
'Return organization details (tier, rate limits, usage, member/server limits, billing status).',
         inputSchema => {
            type       => 'object',
            properties => {},
            required   => [],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'), { command => 'read_org' } );
         },
      },

      # ------------------------------------------------------------------
      # Intentional limitation
      # ------------------------------------------------------------------
      add_server => {
         description =>
           'Adding servers is only supported through the Web UI (Servers tab). '
           . 'This tool exists so agents know the limitation.',
         inputSchema => {
            type       => 'object',
            properties => {},
            required   => [],
         },
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
