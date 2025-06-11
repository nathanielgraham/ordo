#!/usr/bin/env perl

use strict;
use warnings;
use Proc::ProcessTable;
use JSON::PP;
use Data::Dumper;

my $sortby = shift || 'pctcpu';

my $count = shift || 20;
exit unless $count =~ /^\d+$/;

my ($sort) = grep { $sortby eq $_ } (qw(pid ppid start priority time size rss pctmem pctcpu));

exit unless $sort;

my $t = Proc::ProcessTable->new;

my @procs;
foreach my $p ( @{ $t->table } ) {

   #my ($cmndline) = substr($p->cmndline, 0, 20);

   push @procs,
     {
      pid      => $p->pid,
      tty_dev  => $p->ttydev,
      state    => $p->state,
      start    => $p->start,
      ppid     => $p->ppid,
      priority => $p->priority,
      time     => $p->time,
      ctime    => $p->ctime,
      size     => $p->size,
      rss      => $p->rss,
      wchan    => $p->wchan,
      fname    => $p->fname,
      pctcpu   => $p->pctcpu,
      pctmem   => $p->pctmem,
      cmndline => $p->cmndline,
      fname    => $p->fname,
     };
}

my @sorted = (sort { $b->{$sort} <=> $a->{$sort} } @procs);
@sorted = @sorted[0..$count];

my $json = JSON::PP->new->ascii->pretty->allow_nonref;
print $json->encode(\@sorted);
