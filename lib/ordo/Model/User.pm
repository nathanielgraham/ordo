package ordo::Model::User;
use Moo;

has 'id' => ( is => 'rw', );

has 'org_id' => ( is => 'rw', );

has 'root_cluster_id' => ( is => 'rw', );

has 'base_cluster_id' => ( is => 'rw', );

has 'token' => ( is => 'rw', );

has 'is_execution_token' => ( 
   is => 'rw', 
);

has 'tx' => ( is => 'rw', );

has 'level' => (
   is => 'rw',
   default => sub { 0 },
);

has 'request_count' => ( 
   is => 'rw', 
   default => sub { 0 },
);

has 'email' => ( is => 'rw', );

has 'team' => ( 
   is => 'rw', 
   default => sub { [] },
);

has 'remote_address' => ( is => 'rw', );

1;
