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

has 'first_name' => ( is => 'rw', );
has 'last_name'  => ( is => 'rw', );
has 'bookmark' => (
   is        => 'rw',
   predicate => 'has_bookmark',
);
has 'password'   => ( is => 'rw', );
has 'email'      => ( is => 'rw', );
has 'reg_date'   => ( is => 'rw', );
has 'last_visit' => ( is => 'rw', );

sub BUILD {
   my $self = shift;
   $self->username('guest') unless $self->has_username;
   $self->last_visit(time);
}

1;

