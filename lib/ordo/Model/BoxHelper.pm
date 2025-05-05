package ordo::Model::BoxHelper;
use Moo;

has app => (
   is  => 'rw',
   weak_ref => 1,
);

sub start {
   my ($self, $user, $d) = @_;
}

sub kill {
   my ($self, $user, $d) = @_;
}
sub add {
   my ($self, $user, $d) = @_;
}
sub delete {
   my ($self, $user, $d) = @_;
}

sub update {
   my ($self, $user, $d) = @_;
}

sub info {
   my ($self, $user, $d) = @_;
   my $info = $self->app->sqlite->db->select( 'user', ['*'], { id => $user->id } )->hash;

   return {
      id             => $info->{id},
      username       => $info->{username},
      token       => $info->{token},
      level          => $info->{level},
      email          => $info->{email},
      remote_address => $user->remote_address,
   };
}

sub login {
   my ($self, $user, $d) = @_;

   my $results = {};
   my ($message, $success);

   if (defined $d->{token}) {
      $results = $self->app->sqlite->db->select( 'user', ['*'], { token => $d->{token} } )->hash;
   } 
   elsif ( defined $d->{username} && defined $d->{password} ) {
      $results = $self->app->sqlite->db->select( 'user', ['*'], { username => $d->{username} } )->hash;
      if ( $results->{password} ne hmac_sha1_hex( $d->{password}, $self->app->secrets->[0] ) ) {
         $results = {};
      }
   }

   if ($results->{id}) {
      $user->id($results->{id});
      $message = 'logged in as ' . $results->{username};
      $success = 1;
   }
   else {
      $message = 'login failed';
      $success = 0;
   }

   return { message => $message, success => $success };
}

sub xadd {
   my ($self, $user, $d) = @_;

   return { message => 'insufficient privileges' } unless $self->info($user)->{level} >= 3;

   my $db = $self->app->sqlite->db;
   if ( defined $d->{username} ) {
      my $name_length = length( $d->{username} );
      my $results     = $db->select( 'user', ['*'], { username => $d->{username} } )->hash;
      if ( $name_length < 3 || $name_length > 20 ) {
         return { message => 'invalid username length' };
      }
      elsif ( defined $results->{id} ) {    # username taken
         return { message => 'username already taken' };
      }
      else {                                # username available

         my $insert_hash = {
            username       => $d->{username},
            email          => $d->{email},
            #remote_address => $self->tx->remote_address,
            level          => defined $d->{level} || 1,
         };

         if ( $d->{password} ) {

            # generate password hash
            my $password_hash =
              hmac_sha1_hex( $d->{password}, $self->app->secrets->[0] );
            $insert_hash->{password} = $password_hash;
         }

         # generate token
         my $token =
           hmac_sha1_hex( $d->{username}, $self->app->secrets->[0] );
         $insert_hash->{token} = $token;

         # insert new user
         my $id        = $db->insert( 'user', $insert_hash )->last_insert_id;
         if ($id) {
            $insert_hash->{id} = $id;
            $insert_hash->{success} = 1;
         }
         return $insert_hash; 
      }
   }
   else {
      return { message => 'username required' };
   }
}

1;
