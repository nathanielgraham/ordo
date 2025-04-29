package ordo::Model::Box;
use Moo;
#use Mojo::Base 'MojoX::Model';
#use Data::Dumper;
#use Scalar::Util 'weaken';

has app => (
   is  => 'rw',
   weak_ref => 1,
);

sub add {
   #my ($self, $connection_id, $decoed) = @_;
   my $self = shift;
   my $user_id = shift;
   my $name = shift;
   my $db   = $self->app->sqlite->db;
   #my $user = $self->app->user->{$connection_id};
   #print "CID: $connection_id\n";
   #my $result = $db->select( 'user', ['*'], { id => 1 } )->hash;
   my $id = $db->insert('container', {
      user_id => $user_id,
      name => $name,
   })->last_insert_id;
   #$user->tx->send( encode_json( { response => 'container added' }));
}

sub baz {
   my $self = shift;
   my $result = $self->app->sqlite->db->select( 'user', ['*'], { id => 1 } )->hash;
   $result;
}

1;
