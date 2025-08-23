#!/usr/bin/env perl

use strict;
use warnings;

use lib ("$ENV{HOME}/perl5/lib/perl5/lib/perl5", "$ENV{HOME}/perl5/lib/perl5");
use local::lib;
use Proc::ProcessTable;

my $pid = shift;

exit unless $pid && $pid =~ /^\d+$/;

my $t = Proc::ProcessTable->new;

foreach my $p ( @{ $t->table } ) {
   if ($p->pid == $pid) {
      print $p->pid;
      last;
   }
}
