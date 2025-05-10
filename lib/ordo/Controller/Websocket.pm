package ordo::Controller::Websocket;
use Mojo::Base 'Mojolicious::Controller';
use ordo::Model::User;
use JSON;

sub default {
   my $self = shift;

   $self->inactivity_timeout(2);
   $self->tx->with_compression;

   my $connection_id = $self->tx->connection;

   my $user = ordo::Model::User->new(
      tx => $self->tx,
      username => 'guest',
      remote_address => $self->tx->remote_address,
   );

   $self->app->user->{$connection_id} = $user;
    
   $self->on(
      message => sub {
         my ( $self, $msg ) = @_;
         $self->tx->finish if length($msg) > 2048;
         my $decoded = eval { decode_json($msg) };
         if ($@) {
            $self->tx->send(encode_json( { response => 'invalid json' }));
         }
         else {
            if ( ref $decoded eq 'HASH' && defined $decoded->{command} ) {
               my $cmd = $decoded->{command};
               if ($self->app->user->{$connection_id}->id || $cmd eq 'login_user') {
                  my $response = $self->app->request( $user, $decoded );

                  # never timeout if logged in
                  $self->inactivity_timeout(0) if $cmd eq 'login_user' && $response->{success};
                  $self->tx->send( encode_json( $response ) );
               }
               else {
                  $self->tx->finish;
               }
            }
            else {
               $self->tx->send( encode_json( { error => 'command not found' } ) );
               $self->tx->finish;
            }
         }
      }
   );

   # Disconnected
   $self->on(
      finish => sub {
         my $self = shift;

         # cleanup
         delete $self->app->user->{$connection_id};
         $self->app->log->info("Logout: $connection_id");
      }
   );
   $self->app->log->info("Login: $connection_id");
}

1;

