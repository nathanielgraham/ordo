package ordo::Model::JobHelper;
use Moo;
use JSON;
use Net::OpenSSH;

has app => (
   is  => 'rw',
   weak_ref => 1,
);

sub start {
   my ($self, $user, $d) = @_;
   return { success => 0, message => "missing job_id" } unless $d->{job_id};
   my $job_info = $self->app->sqlite->db->select('job', ['*'], { id => $d->{job_id} } )->hash;
   my $server_info = $self->app->sqlite->db->select('server', ['*'], { id => $job_info->{server_id} } )->hash;
   my $encoded = encode_json({
      remote_command => $job_info->{remote_command},
      job_id => $job_info->{id},
      token => $self->app->user_helper->info($user)->{token},
   });

   my $basedir = $server_info->{basedir} ? "$server_info->{basedir}/" : ''; 

   my $cmd = $basedir . "scripts/start_job.pl '$encoded'";

   eval {
      my $ssh = Net::OpenSSH->new($server_info->{hostname}, user => $server_info->{username}, port => 22);
      $ssh->error and
         die "Couldn't establish SSH connection: ". $ssh->error;

      $ssh->system({ stdout_discard => 1 }, $cmd) or
         die "remote command failed: " . $ssh->error;
   };

   my $exit = $? >> 8;

   return { username => $server_info->{username}, error => $@, hostname => $server_info->{hostname}, exit => $exit } if $@;

   my ($success, $state_id);
   if ($exit) {
      $success = 0;
      $state_id = $job_info->{state}; # remote command failed
   }
   else {
      $success = 1;
      $state_id = 3; # starting
   }

   $self->update($user, { job_id => $d->{job_id}, state_id => $state_id });
   return { success => 1, job_id => $d->{job_id}, state_id => $state_id };
}

sub update {
   my ($self, $user, $d) = @_;
   my $update_hash = { map { $_ => $d->{$_} } grep { $d->{$_} } qw(box_id server_id pid state_id remote_command) };
   eval {
      $self->app->sqlite->db->update('job', $update_hash, { id => $d->{job_id} } );
   };

   if ($@) {
      $update_hash->{success} = 0;
      return $update_hash
   }

   # state hooks
   my %state_id_hook = (
      5 => \&finish, # complete
      6 => \&failed, # failed
   );

   if ( exists $state_id_hook{ $update_hash->{state_id} } ) {
      $state_id_hook{ $update_hash->{state_id} }( $self, $user, $d );
   }

   $update_hash->{success} = 1;
   return $update_hash;
}

sub failed {
   my ($self, $user, $d) = @_;
}

sub finish {
   my ($self, $user, $d) = @_;

   my $sql = q/
      select j.*, jn.*
      from job j left join job_need jn
      on j.id = jn.job_id
   /;
   # set status = Complete
   # find jobs that need this one
   # start them if needs met
   # else
   # if all jobs in box are complete, call box_complete()

}

sub kill {
   my ($self, $user, $d) = @_;
}

sub add {
   my ($self, $user, $d) = @_;
   my @required = qw(box_id server_id name remote_command); 
   my @optional = qw(description out_log_path err_log_path);
   my @missing = grep { !$d->{$_} } @required;
   return { success => 0, message => "missing parameters: @missing" } if scalar @missing;
   my $insert_hash = { user_id => $user->id, map { $_ => $d->{$_} } grep { $d->{$_} } (@required, @optional) };
   my $id = $self->app->sqlite->db->insert('job', $insert_hash)->last_insert_id;
   my $success = $id ? 1 : 0;
   return { success => $success, id => $id };
}

sub delete {
   my ($self, $user, $d) = @_;
}

sub info {
   my ($self, $user, $d) = @_;
}

1;
