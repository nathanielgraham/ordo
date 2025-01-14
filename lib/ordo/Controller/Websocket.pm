package ordo::Controller::Websocket;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON 'j';

sub default {
  my $self = shift;

  $self->inactivity_timeout(0);
  $self->tx->with_compression;

  my $connection_id = $self->tx->connection;
  $self->app->logins->{ $connection_id } = $self->tx;

  $self->on(
    message => sub {
      my ( $self, $msg ) = @_;
      my $aref = eval { j($msg) };
      if ($@) {
        $self->tx->req_error;
        $self->tx->send( "failed" );
      }
      else {
        $self->tx->send( "hello $connection_id received: $msg" );
      }
    }
  );

  # Disconnected
  $self->on(
    finish => sub {
      my $self = shift;
      #cleanup logins
      delete $self->app->logins->{$connection_id};
      $self->app->log->debug("Logout: $connection_id" );
    }
  );
}

1;

