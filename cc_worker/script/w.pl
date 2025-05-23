BEGIN {
    use Cwd;
    our $directory = cwd;
}

use Data::Dumper;
use Net::OpenSSH;
use File::Spec;
use Sys::Hostname;
use FindBin qw($Bin);



print $comm;
my $ssh = Net::OpenSSH->new('localhost', user => 'remote5', port => 22, async => 1);
$ssh->error and die "unable to connect to remote host: " . $ssh->error;

my $r = $ssh->scp_put({ recursive => 1}, "$Bin/../../cc_worker")
  or die "scp failed: " . $ssh->error;

__END__
my $r = $ssh->scp_put(q/sysinfo.pl/)
  or die "scp failed: " . $ssh->error;

my $pid = $ssh->system(q/perl install.pl/) 
  or die "remote command failed: " . $ssh->error;

my $pid = $ssh->system(q/perl sysinfo.pl '{"token":"1bb6eda29b864133bf8fc776d11dc8c0b228f9dc"}'/)
  or die "remote command failed: " . $ssh->error;


#my @cmd = $ssh->make_remote_command('/usr/bin/perl');
#my $ipc = IPC::PerlSSH->new(Command => \@cmd);
#my @r = $ipc->eval($comm);



__END__

my $ips = IPC::PerlSSH->new( Host => "localhost", User => 'remote8' );

     $ips->eval( "use POSIX qw( uname )" );
     my @remote_uname = $ips->eval( 'my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<); return $username' );

print Dumper(@remote_uname);
