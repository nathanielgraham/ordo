
use strict;
use warnings;
use Data::Dumper;
use Sys::Statistics::Linux;
#my $lxs = Sys::Statistics::Linux->new( processes => 1 );
#sleep(1);
#my $stat = $lxs->get;
#my @top5 = $stat->pstop( ttime => 5 );
#print Dumper(\@top5);
#print Dumper($stat);

use Data::Dumper;

my $lsx = Sys::Statistics::Linux->new(
    sysinfo   => 1,
    cpustats  => 1,
    procstats => 1,
    memstats  => 1,
    pgswstats => 1,
    netstats  => 1,
    sockstats => 1,
    diskstats => 1,
    diskusage => 1,
    loadavg   => 1,
    filestats => 1,
    processes => 1,
);

sleep(1);
my $stat = $lsx->get();
my $cpu = $stat->procstats;
print  Dumper($cpu);

