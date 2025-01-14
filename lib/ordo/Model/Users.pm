package ordo::Model::Users;
use Moo;
use ordo::Model::User;

has 'user' => (
  is  => 'rw',
  isa => sub { die "Not a hash!" unless ref( $_[0] ) eq 'HASH' },
  default => sub { return {} },
);

sub add {
   my ($self, $tx) = @_;
   my $connection_id = $tx->connection;
   #$self->connected->{ $connection_id } = $tx;
   $self->user->{ $connection_id } = ordo::Model::User->new( tx => $tx );
}

sub remove {
   my ($self, $connection_id) = @_;
   delete $self->user->{ $connection_id };
}

1;

