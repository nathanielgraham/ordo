package ordo::Controller::Websocket;
use Mojo::Base 'Mojolicious::Controller';
use JSON;

sub default {
   my $self = shift;

   $self->inactivity_timeout(0);
   $self->tx->with_compression;

   my $connection_id = $self->tx->connection;
   $self->app->users->add( $self->tx );

   $self->on(
      message => sub {
         my ( $self, $msg ) = @_;
         my $decoded = eval { decode_json($msg) };
         if ($@) {
            $self->tx->send(encode_json( { response => 'invalid json' }));
         }
         else {
            if ( ref $decoded eq 'HASH' && defined $decoded->{command} ) {
               #$self->tx->send( { response => 'invalid command format' } );
               $self->app->request( $connection_id, $decoded );
            }
            else {
               $self->tx->send( encode_json( { response => 'command not found' } ) );
            }
         }
      }
   );

   # Disconnected
   $self->on(
      finish => sub {
         my $self = shift;

         # cleanup
         $self->app->users->remove($connection_id);
         $self->app->log->info("Logout: $connection_id");
      }
   );
   $self->app->log->info("Login: $connection_id");
}

1;

