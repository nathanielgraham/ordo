package ordo;
use Mojo::Base 'Mojolicious';
use ordo::Model::Users;
use JSON;

# This method will run once at server start
sub startup {

   my $self = shift;

   # Load configuration from config file
   my $config = $self->plugin('NotYAMLConfig');

   # Configure the application
   $self->secrets( $config->{secrets} );

   # Helpers
   $self->helper( users => sub { state $users = ordo::Model::Users->new } );
   $self->helper( request => \&request );

   # Router
   my $r = $self->routes;

   # Normal route to controller
   $r->get('/')->to( controller => 'landing', action => 'welcome' );
   $r->websocket('/websocket')->to( controller => 'websocket', action => 'default' );
}

sub request {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->users->user->{$connection_id};

   my %command = (
      'login'       => \&login,
      'register'    => \&register,
   );

   die                unless ref $decoded eq 'HASH';
   die "no such user" unless ref $user eq 'ordo::Model::User';

   if ( exists $command{ $decoded->{command} } ) {
      $command{ $decoded->{command} }($self, $connection_id, $decoded);
      return;
   }
   else {
      $user->tx->send( encode_json( { response => 'no such command' } ) );
      return;
   }

   #$user->tx->send( "you sent " . encode_json($decoded) );

}

# Helper helpers
sub login {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->users->user->{$connection_id};
   $user->tx->send( "you want to login" );
   return;
}

sub register {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->users->user->{$connection_id};
   $user->tx->send( "you want to register" );
   return;
}

1;
