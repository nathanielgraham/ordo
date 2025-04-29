package ordo::Model::User;
use Moo;

has 'id' => ( is => 'rw', );
has 'tx' => ( is => 'rw', );
has 'request_count' => ( 
   is => 'rw', 
   default => sub { 0 },
);
has 'remote_address' => ( is => 'rw', );

1;
