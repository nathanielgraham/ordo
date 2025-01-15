package ordo::Model::User;
use Moo;

has 'username' => (
   is        => 'rw',
   clearer   => 1,
   predicate => 'has_username',
);

has 'tx' => (
   is       => 'rw',
   required => 1,
);

has 'id' => ( is => 'rw', );
has 'level' => ( is => 'rw', );
has 'bookmark' => (
   is        => 'rw',
   predicate => 'has_bookmark',
);
has 'password'   => ( is => 'rw', );
has 'email'      => ( is => 'rw', );
has 'remote_address'  => ( is => 'rw', );
has 'creation_time' => ( is => 'rw', );

sub BUILD {
   my $self = shift;
   $self->username('guest') unless $self->has_username;
}

1;

