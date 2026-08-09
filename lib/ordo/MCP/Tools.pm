# lib/ordo/MCP/Tools.pm
package ordo::MCP::Tools;
use Mojo::Base -base;

sub get_tools {
   return {
      # =====================================================================
      # DOCUMENTATION  (call this first in a new session)
      # =====================================================================
      get_documentation => {
         description =>
            'Retrieve Ordo documentation. **Always call this first in a new session** '
          . 'to understand core concepts, calendars/cron rules, and recommended workflows. '
          . 'Start with section "overview" or "quickstart".',
         params => {
            section => {
               type        => 'string',
               required    => 0,
               enum        => [
                  'overview', 'quickstart', 'core-concepts',
                  'jobs-and-clusters', 'calendars-and-crons',
                  'handlers', 'connecting-to-ai', 'advanced-topics',
                  'faq', 'all'
               ],
               description => 'Specific section. Prefer "overview" or "quickstart" first.',
               default     => 'overview',
            },
            format => {
               type     => 'string',
               required => 0,
               enum     => [ 'markdown', 'summary' ],
               default  => 'markdown',
            },
         },
         examples => [
            { params => { section => 'overview' } },
            { params => { section => 'quickstart' } },
            { params => { section => 'calendars-and-crons' } },
         ],
         handler => sub {
            my ( $c, $p ) = @_;
            $c->app->request(
               $c->stash('user'),
               {
                  command => 'get_documentation',
                  section => $p->{section} // 'overview',
                  format  => $p->{format}  // 'markdown'
               }
            );
         }
      },

      # =====================================================================
      # BROWSING
      # =====================================================================
      list_jobs => {
         description =>
            'List jobs and clusters in the hierarchical tree (starting from /root by default). '
          . 'Use this to discover existing structure before creating new items.',
         params => {
            path => {
               type        => 'string',
               required    => 0,
               default     => '/root',
               description => 'Path starting with /root',
            },
            filter => {
               type     => 'string',
               required => 0,
               enum     => [ 'all', 'running', 'failed', 'waiting' ],
            },
         },
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request(
               $_[0]->stash('user'),
               { command => 'find_cluster', name => $_[1]->{path} // '/root' }
            );
         }
      },

      get_job_details => {
         description => 'Get full details for a specific job (state, script, dependencies, etc.)',
         params => {
            id => { type => 'integer', required => 1, description => 'Job ID' }
         },
         examples => [ { params => { id => 4 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_job', id => $_[1]->{id} } );
         }
      },

      get_cluster_details => {
         description =>
            'Get full details for a specific cluster, including all its jobs and current state. '
          . 'Preferred way to check progress after starting a cluster.',
         params => {
            id => { type => 'integer', required => 1, description => 'Cluster ID' }
         },
         examples => [ { params => { id => 7 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_cluster', id => $_[1]->{id} } );
         }
      },

      # =====================================================================
      # CREATE
      # =====================================================================
      create_job => {
         description =>
            'Create a new job inside a cluster. '
          . 'parent_id is the **cluster ID** that will own the job. '
          . 'For complex scripts prefer a shebang (#!/bin/sh, #!/usr/bin/env python3, etc.). '
          . 'Dependencies: use needs_ids (AND) or needs_any_ids (OR).',
         params => {
            name        => { type => 'string',  required => 1, description => 'Short job name' },
            script      => { type => 'string',  required => 1, description => 'Full script content (plain text)' },
            parent_id   => { type => 'integer', required => 1, description => 'Cluster ID that will contain this job' },
            server_id   => { type => 'integer', required => 1, description => 'Server ID to run on (use list_servers first)' },
            description => { type => 'string',  required => 0 },
            needs_ids => {
               type        => 'array',
               items       => { type => 'integer' },
               required    => 0,
               description => 'Job/cluster IDs that must ALL complete successfully (AND)',
            },
            needs_any_ids => {
               type        => 'array',
               items       => { type => 'integer' },
               required    => 0,
               description => 'Job/cluster IDs where only ONE needs to complete (OR)',
            },
            retrys                 => { type => 'integer', required => 0 },
            loops                  => { type => 'integer', required => 0 },
            delay                  => { type => 'integer', required => 0 },
            max_runtime_seconds    => { type => 'integer', required => 0 },
            max_runtime_cluster_id => { type => 'integer', required => 0 },
         },
         examples => [
            {
               params => {
                  name      => 'prep',
                  parent_id => 7,
                  server_id => 1,
                  script    => "#!/bin/sh\necho \"Hello from Ordo\"\nsleep 1"
               }
            }
         ],
         handler => sub {
            my ( $c, $p ) = @_;
            my $payload = { %{$p} };
            if ( $payload->{script} && !$payload->{script_b64} ) {
               require MIME::Base64;
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            $c->app->request( $c->stash('user'),
               { command => 'create_job', %$payload } );
         }
      },

      create_cluster => {
         description =>
            'Create a new cluster (a container for jobs and/or other clusters). '
          . 'If parent_id is omitted the new cluster is placed under root.',
         params => {
            name          => { type => 'string',  required => 1 },
            parent_id     => { type => 'integer', required => 0, description => 'Parent cluster ID (defaults to root)' },
            on_fail_id    => { type => 'integer', required => 0 },
            on_overdue_id => { type => 'integer', required => 0 },
            auto_start    => { type => 'boolean', required => 0, default => 1 },
         },
         examples => [ { params => { name => 'Bork da Cake' } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'create_cluster', %{ $_[1] } } );
         }
      },

      # =====================================================================
      # UPDATE
      # =====================================================================
      update_job => {
         description => 'Update configuration of an existing job (name, script, dependencies, etc.)',
         params => {
            id                     => { type => 'integer', required => 1 },
            newname                => { type => 'string',  required => 0 },
            script                 => { type => 'string',  required => 0 },
            description            => { type => 'string',  required => 0 },
            server_id              => { type => 'integer', required => 0 },
            needs_ids              => { type => 'array', items => { type => 'integer' }, required => 0 },
            needs_any_ids          => { type => 'array', items => { type => 'integer' }, required => 0 },
            retrys                 => { type => 'integer', required => 0 },
            loops                  => { type => 'integer', required => 0 },
            delay                  => { type => 'integer', required => 0 },
            max_runtime_seconds    => { type => 'integer', required => 0 },
            max_runtime_cluster_id => { type => 'integer', required => 0 },
         },
         handler => sub {
            my ( $c, $p ) = @_;
            my $payload = {%$p};
            if ( $payload->{script} && !$payload->{script_b64} ) {
               require MIME::Base64;
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            $c->app->request( $c->stash('user'),
               { command => 'update_job_config', %$payload } );
         }
      },

      update_cluster => {
         description =>
            'Update an existing cluster. Use cal_id to attach (or detach by setting null) a calendar. '
          . 'Also used to set on_fail_id / on_overdue_id handlers and dependencies.',
         params => {
            id            => { type => 'integer', required => 1 },
            newname       => { type => 'string',  required => 0 },
            description   => { type => 'string',  required => 0 },
            cal_id        => { type => 'integer', required => 0, description => 'Calendar ID to attach (or omit/null to detach)' },
            auto_start    => { type => 'boolean', required => 0 },
            needs_ids     => { type => 'array', items => { type => 'integer' }, required => 0 },
            needs_any_ids => { type => 'array', items => { type => 'integer' }, required => 0 },
            on_fail_id    => { type => 'integer', required => 0 },
            on_overdue_id => { type => 'integer', required => 0 },
         },
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'update_cluster', %{ $_[1] } } );
         }
      },

      # =====================================================================
      # CLONING
      # =====================================================================
      clone_cluster => {
         description =>
            'Clone a cluster (creates an identical copy). Most often used from an On Overdue handler '
          . 'so a late run does not block the next scheduled occurrence.',
         params => {
            id => { type => 'integer', required => 1, description => 'Cluster ID to clone' }
         },
         examples => [ { params => { id => 7 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'clone_cluster', %{ $_[1] } } );
         }
      },

      # =====================================================================
      # CALENDARS & CRON  (important conventions for agents)
      # =====================================================================
      list_calendars => {
         description =>
            'List all calendars together with their cron entries and which clusters are attached.',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'), { command => 'find_cal' } );
         }
      },

      create_calendar => {
         description =>
            'Create a new calendar. A calendar is simply a named collection of Quartz cron expressions. '
          . 'After creation, use add_cron to populate it, then attach the calendar to a cluster with update_cluster.',
         params => {
            name        => { type => 'string', required => 1 },
            tz          => { type => 'string', required => 1, description => 'IANA timezone, e.g. America/Chicago' },
            description => { type => 'string', required => 0 },
         },
         examples => [
            { params => { name => 'US Holidays', tz => 'America/Chicago', description => 'Major US federal holidays' } },
            { params => { name => 'nightly',     tz => 'America/Chicago' } },
         ],
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'create_cal', %{ $_[1] } } );
         }
      },

      delete_calendar => {
         description => 'Delete a calendar (and all of its cron entries)',
         params => {
            id => { type => 'integer', required => 1 }
         },
         examples => [ { params => { id => 3 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'delete_cal', id => $_[1]->{id} } );
         }
      },

      add_cron => {
         description =>
            'Add a Quartz cron expression to an existing calendar.' . "\n\n"
          . '**Quartz format (6 or 7 fields):**' . "\n"
          . '  seconds  minutes  hours  day-of-month  month  day-of-week  [year]' . "\n\n"
          . '**Important day-of-week convention in Ordo:**' . "\n"
          . '  Monday = 1, Tuesday = 2, ... Sunday = 7' . "\n"
          . '  (This differs from classic Quartz where Sunday = 1.)' . "\n\n"
          . '**Useful patterns:**' . "\n"
          . '  0 0 0 1 1 ? *          → New Year\'s Day (midnight Jan 1)' . "\n"
          . '  0 0 0 ? 1 1#3 *        → 3rd Monday in January (MLK Day)' . "\n"
          . '  0 0 0 ? 5 1L *         → last Monday in May (Memorial Day)' . "\n"
          . '  0 0 0 ? 11 4#4 *       → 4th Thursday in November (Thanksgiving)' . "\n"
          . '  0 0 9 ? * 1-5 *        → 09:00 every weekday' . "\n\n"
          . 'Prefer day names when possible (MON, TUE, ...). The system may rewrite them to numbers.',
         params => {
            name        => {
               type        => 'string',
               required    => 1,
               description => 'Quartz cron expression (the "name" field is the expression itself)'
            },
            cal_id      => { type => 'integer', required => 1, description => 'Calendar ID' },
            description => { type => 'string',  required => 0, description => 'Human label, e.g. "Thanksgiving"' },
         },
         examples => [
            { params => { cal_id => 3, name => '0 0 0 1 1 ? *',        description => 'New Year\'s Day' } },
            { params => { cal_id => 3, name => '0 0 0 ? 1 1#3 *',      description => 'MLK Day (3rd Monday January)' } },
            { params => { cal_id => 3, name => '0 0 0 ? 5 1L *',       description => 'Memorial Day (last Monday May)' } },
            { params => { cal_id => 3, name => '0 0 0 ? 11 4#4 *',     description => 'Thanksgiving' } },
            { params => { cal_id => 1, name => '0 0 9 * * ? *',        description => 'Every day at 09:00' } },
         ],
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'create_cron', %{ $_[1] } } );
         }
      },

      delete_cron => {
         description => 'Delete a single cron entry from a calendar',
         params => {
            id => { type => 'integer', required => 1, description => 'Cron ID (not the calendar ID)' }
         },
         examples => [ { params => { id => 7 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'delete_cron', id => $_[1]->{id} } );
         }
      },

      # =====================================================================
      # SERVERS & UTILITY
      # =====================================================================
      list_servers => {
         description =>
            'List all monitored servers with live status and resource stats. '
          . 'Always call this before creating jobs so you can choose a valid server_id.',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'find_monitor' } );
         }
      },

      sync => {
         description =>
            'Reconcile scheduler state with actual processes on remote servers. '
          . 'Marks missing PIDs as zombie. Useful after network blips or manual kills.',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'), { command => 'sync' } );
         }
      },

      add_server => {
         description =>
            'Adding servers is only supported through the Web UI (Servers tab). '
          . 'This tool exists only so agents know the limitation.',
         params  => {},
         handler => sub {
            return {
               success => 0,
               message => 'Use the Web UI Servers tab to add servers. Agents cannot add servers via MCP.'
            };
         }
      },

      # =====================================================================
      # USER / ORG
      # =====================================================================
      read_user => {
         description => 'Get current user information (id, level, token, org membership, etc.)',
         params      => {},
         examples    => [ { params => {} } ],
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_user' } );
         }
      },

      read_org => {
         description =>
            'Get organization details (tier, rate limits, usage, member/server limits, Stripe status)',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'), { command => 'read_org' } );
         }
      },

      # =====================================================================
      # LOGS
      # =====================================================================
      read_log => {
         description =>
            'Read the most recent log output for a job. Returns the full formatted log including '
          . 'start/end time, exit code, and stdout/stderr.',
         params => {
            id => { type => 'integer', required => 1, description => 'Job ID' }
         },
         examples => [ { params => { id => 4 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_log', id => $_[1]->{id} } );
         }
      },

      find_logs => {
         description => 'Get history of past runs for a job (timestamps + exit codes)',
         params => {
            id => { type => 'integer', required => 1, description => 'Job ID' }
         },
         examples => [ { params => { id => 4 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'find_log', id => $_[1]->{id} } );
         }
      },

      # =====================================================================
      # MANAGE (start / stop / etc.)
      # =====================================================================
      manage_job => {
         description =>
            'Perform a lifecycle action on a single job. '
          . 'Common actions: start, kill, hold, release, complete, delete, reset.',
         params => {
            action => {
               type     => 'string',
               required => 1,
               enum     => [qw(start kill hold release ice melt complete delete reset)],
               description => 'Action to perform',
            },
            id => { type => 'integer', required => 1, description => 'Job ID' },
         },
         examples => [
            { params => { action => 'start',   id => 4 } },
            { params => { action => 'reset',   id => 4 } },
            { params => { action => 'delete',  id => 4 } },
         ],
         handler => sub {
            my ( $c, $p ) = @_;
            my $cmd = $p->{action} . '_job';
            $c->app->request( $c->stash('user'),
               { command => $cmd, id => $p->{id} } );
         }
      },

      manage_cluster => {
         description =>
            'Perform a lifecycle action on a cluster (and therefore its jobs). '
          . 'Most common: start (runs the whole workflow), kill, hold, reset, delete.',
         params => {
            action => {
               type     => 'string',
               required => 1,
               enum     => [qw(start kill hold release ice melt complete delete reset)],
               description => 'Action to perform',
            },
            id => { type => 'integer', required => 1, description => 'Cluster ID' },
         },
         examples => [
            { params => { action => 'start',  id => 7 } },
            { params => { action => 'reset',  id => 7 } },
            { params => { action => 'delete', id => 7 } },
         ],
         handler => sub {
            my ( $c, $p ) = @_;
            my $cmd = $p->{action} . '_cluster';
            $c->app->request( $c->stash('user'),
               { command => $cmd, id => $p->{id} } );
         }
      },
   };
}

1;
