# lib/ordo/MCP/Tools.pm
package ordo::MCP::Tools;
use Mojo::Base -base;

sub get_tools {
    return {
        # ====================== BROWSING ======================
        list_jobs => {
            description =>
'List jobs and clusters in the hierarchical tree (same as the main UI view)',
            params => {
                path => {
                    type        => 'string',
                    required    => 0,
                    default     => '/root',
                    description =>
                      'Path starting with /root (e.g. "/root/nightly-backup")'
                },
                filter => {
                    type     => 'string',
                    required => 0,
                    enum     => [ 'all', 'running', 'failed', 'waiting' ]
                },
            },
            examples => [
                {
                    params      => { path => '/root' },
                    description => 'Show everything under root'
                },
            ],
            handler => sub {
                $_[0]->app->request(
                    $_[0]->stash('user'),
                    {
                        command => 'find_cluster',
                        name    => $_[1]->{path} // '/root'
                    }
                );
            }
        },

        get_job_details => {
            description => 'Get full details for a specific job',
            params      => { id => { type => 'integer', required => 1 } },
            examples    => [ { params => { id => 4 } } ],
            handler     => sub {
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'read_job', id => $_[1]->{id} } );
            }
        },

        get_cluster_details => {
            description => 'Get full details for a specific cluster',
            params      => { id => { type => 'integer', required => 1 } },
            examples    => [ { params => { id => 2 } } ],
            handler     => sub {
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'read_cluster', id => $_[1]->{id} } );
            }
        },

        # ====================== CALENDARS ======================
        list_calendars => {
            description =>
              'List all calendars with their crons and attached clusters',
            params   => {},
            examples => [ { params => {} } ],
            handler  => sub {
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'find_cal' } );
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
            examples =>
              [ { params => { name => '0 0 2 * * ? *', cal_id => 1 } } ],
            handler => sub {
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

        attach_calendar => {
            description => 'Attach a calendar to a cluster',
            params      => {
                cluster_id  => { type => 'integer', required => 1 },
                calendar_id => { type => 'integer', required => 1 },
            },
            examples => [ { params => { cluster_id => 2, calendar_id => 1 } } ],
            handler  => sub {
                $_[0]->app->request(
                    $_[0]->stash('user'),
                    {
                        command => 'update_cluster',
                        id      => $_[1]->{cluster_id},
                        cal_id  => $_[1]->{calendar_id}
                    }
                );
            }
        },

        detach_calendar => {
            description => 'Detach calendar from a cluster',
            params   => { cluster_id => { type => 'integer', required => 1 } },
            examples => [ { params => { cluster_id => 2 } } ],
            handler  => sub {
                $_[0]->app->request(
                    $_[0]->stash('user'),
                    {
                        command => 'update_cluster',
                        id      => $_[1]->{cluster_id},
                        cal_id  => undef
                    }
                );
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
                $_[0]
                  ->app->request( $_[0]->stash('user'), { command => 'sync' } );
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
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'read_org' } );
            }
        },

        # ====================== LOGS ======================
        read_log => {
            description => 'Read content of a specific log entry',
            params      => {
                id =>
                  { type => 'integer', required => 1, description => 'Job ID' }
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

        # ====================== CREATE ======================
        create_job => {
            description =>
'Create a new job. For complex or multi-line scripts, wrap them with /bin/sh -c "..." and use only single or double quotes. You can also use python3 -c or perl -e.',

            params => {
                name        => { type => 'string',  required => 1 },
                script      => { type => 'string',  required => 1 },
                parent_id   => { type => 'integer', required => 1 },
                description => { type => 'string',  required => 0 },

                server => {
                    type        => 'string',
                    description => 'Server name (e.g. "snarf")'
                },
                server_id => {
                    type        => 'integer',
                    description => 'Server ID (preferred for uniqueness)'
                },
            },

            # === This enforces "either server OR server_id" ===
            anyOf =>
              [ { required => ['server'] }, { required => ['server_id'] } ],
            examples => [
                {
                    params => {
                        name   => "python-system-report",
                        script =>
q{python3 -c 'import psutil, datetime; disk=psutil.disk_usage("/"); print(f"[{datetime.datetime.now()}] Disk Usage: {disk.percent}%")'},
                        server    => "snarf",
                        parent_id => 1
                    },
                    description => "Python disk usage report"
                },
                {
                    params => {
                        name   => "perl-log-check",
                        script =>
q{perl -e 'use strict; open my $fh, ">>", "/tmp/perl-report.log" or die; print $fh "Report at " . localtime() . "\n";'},
                        server    => "snarf",
                        parent_id => 1
                    },
                    description => "Perl one-liner that writes to /tmp"
                }
            ],
            handler => sub {
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'create_job', %{ $_[1] } } );
            }
        },

        create_cluster => {
            description => 'Create a new cluster',
            params      => {
                name      => { type => 'string',  required => 1 },
                parent_id => { type => 'integer', required => 0 },
            },
            examples => [ { params => { name => 'nightly', parent_id => 1 } } ],
            handler  => sub {
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
                script      => { type => 'string',  required => 0 },
                description => { type => 'string',  required => 0 },

                server => {
                    type        => 'string',
                    required    => 0,
                    description => 'Server name'
                },
                server_id => {
                    type        => 'integer',
                    required    => 0,
                    description => 'Server ID'
                },
            },
            anyOf =>
              [ { required => ['server'] }, { required => ['server_id'] } ],
            examples => [ { params => { id => 5, newname => 'better-name' } } ],
            handler  => sub {
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'update_job_config', %{ $_[1] } } );
            }
        },

        update_cluster => {
            description => 'Update configuration of an existing cluster',
            params      => {
                id          => { type => 'integer', required => 1 },
                newname     => { type => 'string',  required => 0 },
                description => { type => 'string',  required => 0 },
                cal_id      => { type => 'integer', required => 0 },
            },
            examples =>
              [ { params => { id => 2, newname => 'production-nightly' } } ],
            handler => sub {
                $_[0]->app->request( $_[0]->stash('user'),
                    { command => 'update_cluster', %{ $_[1] } } );
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
                    enum     => [
                        qw(start kill hold release ice melt complete delete reset)
                    ]
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
                    enum     => [
                        qw(start kill hold release ice melt complete delete reset)
                    ]
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

        # ====================== PLACEHOLDER ======================
        add_server => {
            description =>
'Add a new server. This action is only available through the Web UI for security reasons.',
            params   => {},
            examples => [],
            handler  => sub {
                return {
                    success => 0,
                    message =>
'Adding servers is only supported through the Web UI. Please use the Servers tab in Ordo.'
                };
            }
        },
    };
}

1;
