#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use JSON::PP;

my $hex  = pop @ARGV or die "missing arg";
my $json = pack( 'H*', $hex );
my $pids = decode_json($json) or die $!;
exit unless $pids && ref $pids eq 'ARRAY';

my ($alive, $zombies) = &find_pids( $pids );
my @alive_pids = map { $_->{pid} } @{ $alive }; 

print encode_json({ alive => \@alive_pids, zombies => $zombies });

