# lib/ordo/MCP/Tools.pm
package ordo::MCP::Tools;
use Mojo::Base -base;

sub get_tools {
   return {
      # ====================== DOCUMENTATION ======================
      get_documentation => {
         description =>
'Retrieve Ordo documentation. **This is one of the most important tools to call first** in a new session.',
         params => {
            section => {
               type     => 'string',
               required => 0,
               enum     => [
                  'overview',          'quickstart',
                  'core-concepts',     'dashboard',
                  'jobs-and-clusters', 'calendars-and-crons',
                  'handlers',          'settings',
                  'connecting-to-ai',  'advanced-topics',
                  'faq',               'all'
               ],
               description => 'Specific section or "all" for everything'
            },
            format => {
               type     => 'string',
               required => 0,
               enum     => [ 'markdown', 'summary' ],
               default  => 'markdown'
            },
         },
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

      # ====================== BROWSING ======================
      list_jobs => {
         description => 'List jobs and clusters in the hierarchical tree',
         params      => {
            path => {
               type        => 'string',
               required    => 0,
               default     => '/root',
               description => 'Path starting with /root'
            },
            filter => {
               type     => 'string',
               required => 0,
               enum     => [ 'all', 'running', 'failed', 'waiting' ]
            },
         },
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'find_cluster', name => $_[1]->{path} // '/root' }
            );
         }
      },

      get_job_details => {
         description => 'Get full details for a specific job',
         params      => { id => { type => 'integer', required => 1 } },
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_job', id => $_[1]->{id} } );
         }
      },

      get_cluster_details => {
         description => 'Get full details for a specific cluster',
         params      => { id => { type => 'integer', required => 1 } },
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_cluster', id => $_[1]->{id} } );
         }
      },

      # ====================== CREATE ======================
      create_job => {
         description =>
'Create a new job. For complex scripts, wrap with /bin/sh -c "..." or use python3 -c / perl -e.',
         params => {
            name        => { type => 'string',  required => 1 },
            script      => { type => 'string',  required => 1 },
            parent_id   => { type => 'integer', required => 1 },
            description => { type => 'string',  required => 0 },
            server_id   => { type => 'integer', required => 1 },

            # Dependencies
            needs_ids => {
               type     => 'array',
               items    => { type => 'integer' },
               required => 0,
            },
            needs_any_ids => {
               type     => 'array',
               items    => { type => 'integer' },
               required => 0,
            },

            retrys => { type => 'integer', required => 0 },
            loops  => { type => 'integer', required => 0 },
            delay  => { type => 'integer', required => 0 },

            # Max Runtime (job level)
            max_runtime_seconds    => { type => 'integer', required => 0 },
            max_runtime_cluster_id => { type => 'integer', required => 0 },
         },
         handler => sub {
            my ( $c, $p ) = @_;

            my $payload = { %{$p} };    # copy

            # Convert plain 'script' to 'script_b64' expected by backend
            if ( $payload->{script} && !$payload->{script_b64} ) {
               require MIME::Base64;
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};    # clean up
            }

            $c->app->request( $c->stash('user'),
               { command => 'create_job', %$payload } );
         }

      },

      create_cluster => {
         description => 'Create a new cluster',
         params      => {
            name          => { type => 'string',  required => 1 },
            parent_id     => { type => 'integer', required => 0 },
            on_fail_id    => { type => 'integer', required => 0 },
            on_overdue_id => { type => 'integer', required => 0 },
            auto_start    => { type => 'boolean', required => 0, default => 1 },
         },
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'create_cluster', %{ $_[1] } } );
         }
      },

      # ====================== UPDATE ======================

      update_job => {
         description => 'Update configuration of an existing job',
         params      => {
            id          => { type => 'integer', required => 1 },
            newname     => { type => 'string',  required => 0 },
            script      => { type => 'string',  required => 0 },    # optional
            description => { type => 'string',  required => 0 },
            server_id   => { type => 'integer', required => 0 },

            needs_ids => {
               type     => 'array',
               items    => { type => 'integer' },
               required => 0
            },
            needs_any_ids => {
               type     => 'array',
               items    => { type => 'integer' },
               required => 0
            },

            retrys => { type => 'integer', required => 0 },
            loops  => { type => 'integer', required => 0 },
            delay  => { type => 'integer', required => 0 },

            max_runtime_seconds    => { type => 'integer', required => 0 },
            max_runtime_cluster_id => { type => 'integer', required => 0 },
         },
         handler => sub {
            my ( $c, $p ) = @_;
            my $payload = {%$p};

            # Convert plain script to script_b64 if provided
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
'Update configuration of an existing cluster (replaces attach/detach calendar)',
         params => {
            id          => { type => 'integer', required => 1 },
            newname     => { type => 'string',  required => 0 },
            description => { type => 'string',  required => 0 },
            cal_id      => { type => 'integer', required => 0 },
            auto_start  => { type => 'boolean', required => 0 },

            # Dependencies
            needs_ids => {
               type     => 'array',
               items    => { type => 'integer' },
               required => 0,
            },
            needs_any_ids => {
               type     => 'array',
               items    => { type => 'integer' },
               required => 0,
            },

            # Handlers
            on_fail_id    => { type => 'integer', required => 0 },
            on_overdue_id => { type => 'integer', required => 0 },
         },
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'update_cluster', %{ $_[1] } } );
         }
      },

      # ====================== CLONING ======================
      clone_cluster => {
         description =>
           'Clone a cluster (especially useful with on_overdue handler)',
         params => {
            id => { type => 'integer', required => 1 }
         },
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'clone_cluster', %{ $_[1] } } );
         }
      },

      # ====================== CALENDARS ======================
      list_calendars => {
         description =>
           'List all calendars with their crons and attached clusters',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]
              ->app->request( $_[0]->stash('user'), { command => 'find_cal' } );
         }
      },

      create_calendar => {
         description => 'Create a new calendar',
         params      => {
            name        => { type => 'string', required => 1 },
            tz          => { type => 'string', required => 1 },
            description => { type => 'string', required => 0 },
         },
         examples =>
           [ { params => { name => 'nightly', tz => 'America/Chicago' } } ],
         handler => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'create_cal', %{ $_[1] } } );
         }
      },

      delete_calendar => {
         description => 'Delete a calendar',
         params      => { id => { type => 'integer', required => 1 } },
         examples    => [ { params => { id => 1 } } ],
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'delete_cal', id => $_[1]->{id} } );
         }
      },

      add_cron => {
         description => 'Add a cron schedule to a calendar',
         params      => {
            name        => { type => 'string',  required => 1 },
            cal_id      => { type => 'integer', required => 1 },
            description => { type => 'string',  required => 0 },
         },
         examples => [ { params => { name => '0 0 2 * * ? *', cal_id => 1 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'create_cron', %{ $_[1] } } );
         }
      },

      delete_cron => {
         description => 'Delete a cron from a calendar',
         params      => { id => { type => 'integer', required => 1 } },
         examples    => [ { params => { id => 1 } } ],
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'delete_cron', id => $_[1]->{id} } );
         }
      },

      # ====================== SERVERS & UTILITY ======================
      list_servers => {
         description => 'List all monitored servers with status and stats',
         params      => {},
         examples    => [ { params => {} } ],
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'find_monitor' } );
         }
      },

      sync => {
         description =>
'Reconcile scheduler state with actual processes on remote servers (marks missing PIDs as zombie)',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'), { command => 'sync' } );
         }
      },

      # ====================== UTILITY ======================
      read_user => {
         description =>
           'Get current user information (level, token, org, etc.)',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_user' } );
         }
      },

      read_org => {
         description =>
           'Get organization details (tier, rate limits, usage, members)',
         params   => {},
         examples => [ { params => {} } ],
         handler  => sub {
            $_[0]
              ->app->request( $_[0]->stash('user'), { command => 'read_org' } );
         }
      },

      # ====================== LOGS ======================
      read_log => {
         description => 'Read content of a specific log entry',
         params      => {
            id => { type => 'integer', required => 1, description => 'Job ID' }
         },
         examples => [ { params => { id => 3 } } ],
         handler  => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'read_log', id => $_[1]->{id} } );
         }
      },

      find_logs => {
         description => 'Get history of past runs for a job',
         params      => { id => { type => 'integer', required => 1 } },
         examples    => [ { params => { id => 3 } } ],
         handler     => sub {
            $_[0]->app->request( $_[0]->stash('user'),
               { command => 'find_log', id => $_[1]->{id} } );
         }
      },

      # ====================== MANAGE ======================
      manage_job => {
         description =>
'Perform action on a job (start, kill, hold, release, ice, melt, complete, delete, reset)',
         params => {
            action => {
               type     => 'string',
               required => 1,
               enum     =>
                 [qw(start kill hold release ice melt complete delete reset)]
            },
            id => { type => 'integer', required => 1 },
         },
         examples => [ { params => { action => 'start', id => 4 } } ],
         handler  => sub {
            my ( $c, $p ) = @_;
            my $cmd = $p->{action} . '_job';
            $c->app->request( $c->stash('user'),
               { command => $cmd, id => $p->{id} } );
         }
      },

      manage_cluster => {
         description =>
'Perform action on a cluster (start, kill, hold, release, ice, melt, complete, delete, reset)',
         params => {
            action => {
               type     => 'string',
               required => 1,
               enum     =>
                 [qw(start kill hold release ice melt complete delete reset)]
            },
            id => { type => 'integer', required => 1 },
         },
         examples => [ { params => { action => 'start', id => 2 } } ],
         handler  => sub {
            my ( $c, $p ) = @_;
            my $cmd = $p->{action} . '_cluster';
            $c->app->request( $c->stash('user'),
               { command => $cmd, id => $p->{id} } );
         }
      },

      add_server => {
         description => 'Adding servers is only supported through the Web UI.',
         params      => {},
         handler     => sub {
            return {
               success => 0,
               message => 'Use the Web UI Servers tab to add servers.'
            };
         }
      },
   };
}

1;
