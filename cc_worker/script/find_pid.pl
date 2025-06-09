#!/usr/bin/env perl

use strict;
use warnings;
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
