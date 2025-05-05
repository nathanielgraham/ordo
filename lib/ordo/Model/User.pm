package ordo::Model::User;
use Moo;

has 'id' => ( is => 'rw', );

has 'org_id' => ( is => 'rw', );

has 'tx' => ( is => 'rw', );

has 'level' => (
   is => 'rw',
   default => sub { 0 },
);

has 'request_count' => ( 
   is => 'rw', 
   default => sub { 0 },
);

has 'remote_address' => ( is => 'rw', );

1;
