package ordo::Controller::Websocket;
use Mojo::Base 'Mojolicious::Controller';
use ordo::Model::User;
use JSON;

sub default {
   my $self = shift;
   $self->inactivity_timeout(2);
   $self->tx->with_compression;

   my $tx = $self->tx;
   my $connection_id = $tx->connection;

   my $user = ordo::Model::User->new(
      tx             => $tx,
      username       => 'guest',
      remote_address => $tx->remote_address,
   );

   $self->app->user->{$connection_id} = $user;

   $self->on(
      message => sub {
         my ($self, $msg) = @_;
         my $tx = $self->tx;

         $tx->finish if length($msg) > 2048;

         my $decoded = eval { decode_json($msg) };
         if ($@) {
            $tx->send(encode_json({ response => 'invalid json' }));
            return;
         }

         unless (ref $decoded eq 'HASH' && defined $decoded->{command}) {
            $tx->send(encode_json({ error => 'command not found' }));
            $tx->finish;
            return;
         }

         my $cmd = $decoded->{command};

         unless ($user->id || $cmd eq 'login_user') {
            $tx->finish;
            return;
         }

         my $response = $self->app->request($user, $decoded);

         # Register for broadcasts on successful login
         if ($cmd eq 'login_user' && $response->{success}) {
            my $org_id = $user->org_id;
            if ($org_id) {
               push @{$self->app->clients_by_org->{$org_id} //= []}, $tx;
               $self->app->log->debug("WS client registered for org $org_id");
            }
            $self->inactivity_timeout(0);
         }

         $tx->send(encode_json($response));
      }
   );

   $self->on(
      finish => sub {
         my ($self) = shift;
         my $tx = $self->tx;
         my $connection_id = $tx->connection;

         my $user = $self->app->user->{$connection_id};
         if ($user && $user->org_id) {
            my $org_id = $user->org_id;
            delete $self->app->last_warning_cache->{$org_id};
            $self->app->clients_by_org->{$org_id} = [
               grep { $_ != $tx } @{$self->app->clients_by_org->{$org_id} || []}
            ];
            delete $self->app->clients_by_org->{$org_id} if !@{ $self->app->clients_by_org->{$org_id} };
         }

         delete $self->app->user->{$connection_id};
         $self->app->log->info("WebSocket disconnected: $connection_id");
      }
   );

   $self->app->log->info("WebSocket connected: $connection_id");
}

1;
