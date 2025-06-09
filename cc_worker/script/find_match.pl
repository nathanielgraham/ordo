#!/usr/bin/env perl

use strict;
use warnings;
use Proc::ProcessTable;

my $match = shift;

exit unless $match;

my $t = Proc::ProcessTable->new;

my %cmd;
foreach my $p ( @{ $t->table } ) {
   if ($p->cmndline =~ /$match/ && $p->pid != $$) {
      next if $p->cmndline =~ /openssh/;
      $cmd{$p->pid} = $p->cmndline;
   }
}

print map { $_ } keys %cmd if scalar keys %cmd == 1;
