package ordo::Model::UserHelper;
use Moo;
use Digest::SHA qw(hmac_sha1_hex);

has sqlite => (
   is       => 'rw',
   weak_ref => 1,
);

sub info {
   my ( $self, $user, $d ) = @_;
   my $info = $self->sqlite->db->select( 'user', ['*'], { id => $user->id } )->hash;

   return {
      id             => $info->{id},
      org_id         => $info->{org_id},
      username       => $info->{username},
      token          => $info->{token},
      level          => $info->{level},
      email          => $info->{email},
      remote_address => $user->remote_address,
   };
}

sub login {
   my ( $self, $user, $d ) = @_;

   my $results = {};
   my ( $message, $success );

   if ( defined $d->{token} ) {
      $results = $self->sqlite->db->select( 'user', ['*'], { token => $d->{token} } )->hash;
   }
   elsif ( defined $d->{username} && defined $d->{password} ) {
      $results = $self->sqlite->db->select( 'user', ['*'], { username => $d->{username} } )->hash;
      if ( $results->{password} ne hmac_sha1_hex( $d->{password}, $self->app->secrets->[0] ) ) {
         $results = {};
      }
   }

   if ( $results->{id} ) {
      $user->id( $results->{id} );
      $user->level( $results->{level} );
      $user->org_id( $results->{org_id} );
      $message = 'logged in as ' . $results->{username};
      $success = 1;
   }
   else {
      $message = 'login failed';
      $success = 0;
   }

   return { message => $message, success => $success, user_id => $user->id };
}

sub add {
   my ( $self, $user, $d ) = @_;

   my $db = $self->sqlite->db;
   my ($org_id, $user_id);

   my $user_insert = {
      username       => $d->{username},
      email          => $d->{email},
      remote_address => $user->tx->remote_address,
      level          => defined $d->{level} || 1,
   };

   eval {
      my $tx = $db->begin;

      # generate org bookmark
      my $bookmark = hmac_sha1_hex( $d->{username}, $self->app->secrets->[1] );

      $org_id = $d->{org_id} || $db->insert( 'org', { name => $d->{username}, bookmark => $bookmark } )->last_insert_id;

      # generate login token
      my $token = hmac_sha1_hex( $d->{username}, $self->app->secrets->[0] );
      $user_insert->{org_id} = $org_id;
      $user_insert->{token} = $token;
      $user_id = $db->insert( 'user', $user_insert )->last_insert_id;
      $tx->commit;
   };

   return $@ ? { error => $@, success => 0 } 
             : { success => 1 };
}

1;
