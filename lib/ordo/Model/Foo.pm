package ordo::Model::Foo;
use Moo;
#use Mojo::Base 'MojoX::Model';
#use Data::Dumper;
#use Scalar::Util 'weaken';

has app => (
   is  => 'rw',
   weak_ref => 1,
);

=pod
sub new {
  my $class = shift;
  my $app = shift;
  my $hash = { app => $app };
  weaken $hash->{app};
  return bless $hash, $class;
}
=cut

sub baz {
   my $self = shift;
   my $result = $self->app->sqlite->db->select( 'user', ['*'], { id => 1 } )->hash;
   $result;
}

1;
