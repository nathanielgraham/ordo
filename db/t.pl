use Mojo::SQLite;
use Data::Dumper;
use feature 'say';

my $sql = Mojo::SQLite->new('ordo.db');
#print $sql->db->query('select sqlite_version() as version')->hash->{version};
print $sql->db->query('select * from user')->hash;
my $db = $sql->db;

my $id = $db->select('user', ['*'], {username => 'admin'})->hash;

print Dumper($id);

__END__
while (my $next = $results->hash) {
  say print Dumper($next);
}


