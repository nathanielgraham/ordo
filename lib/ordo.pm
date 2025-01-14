package ordo;
use Mojo::Base 'Mojolicious';
use Moo;

has 'logins' => (
  is       => 'rw',
  isa      => sub { die "Not an hash_ref!" unless ref( $_[0] ) eq 'HASH' },
  default  => sub { {} },
);

# This method will run once at server start
sub startup {

  my $self = shift;

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig');

  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to( controller => 'landing', action => 'welcome');
  $r->websocket('/websocket')->to( controller => 'websocket', action => 'default' );

}

1;
