package ordo;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use ordo::Model::Users;
use JSON;
use Digest::SHA qw(hmac_sha1_hex);

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
   $self->helper( sqlite => sub { state $sql = Mojo::SQLite->new('db/ordo.db') } );

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
   }
   else {
      $user->tx->send( encode_json( { response => 'no such command' } ) );
   }
}

# request helpers
sub login {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->users->user->{$connection_id};
   my $db = $self->app->sqlite->db;
   if (defined $decoded->{bookmark}) {
      my $results = $db->select('user', ['*'], { bookmark => $decoded->{bookmark} })->hash;
      if ($results->{id}) { # user found
         # update user
         while (my ($p, $v) = each %$results) {
            $user->$p($v);
         }
         $user->tx->send( encode_json ( { response => 'logged in as ' . $user->username } ) );
      }
      else {
         $user->tx->send( encode_json ( { response => 'user not found' } ) );
      }
   }
   elsif (defined $decoded->{username} && defined $decoded->{password}) {
      $user->tx->send( encode_json ( { response => 'password login not implemented' } ) );
   }
   else {
      $user->tx->send( encode_json ( { response => 'login failed' } ) );
   }
   return;
}

sub register {
   my ( $self, $connection_id, $decoded ) = @_;
   my $user = $self->app->users->user->{$connection_id};
   my $db = $self->app->sqlite->db;

   if (defined $decoded->{username}) {
      my $name_length = length( $decoded->{username} );
      my $results = $db->select('user', ['*'], { username => $decoded->{username} })->hash;
      if ( $name_length < 3 || $name_length > 20 ) { 
         $user->tx->send( encode_json ( { response => 'invalid username length' } ) );
      }
      elsif ( defined $results->{id} ) { # username taken
         $user->tx->send( encode_json ( { response => 'username already taken' } ) );
      }
      else { # username available
         if ( $decoded->{password} ) {

            # generate password hash
            my $hash = hmac_sha1_hex( $decoded->{password}, $self->secrets );
            $decoded->{password} = $hash;
         }

         # generate bookmark
         my $bookmark = hmac_sha1_hex( $decoded->{username}, $self->secrets );

         # insert new user
         # my $id = $db->insert('user', {username => 'Daniel'})->last_insert_id;

         $user->tx->send( encode_json ( { response => 'registration not implemented' } ) );
      }
   }
   else {
      $user->tx->send( encode_json ( { response => 'username is required' } ) );
   }
   # generate bookmark
   # generate password hash
  
   return;
}

1;
