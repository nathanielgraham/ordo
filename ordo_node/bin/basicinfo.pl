#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../modules";
use SysInfo;
use JSON::PP qw(encode_json);

# One-shot node identity collected during _install_monitor / upgrade_monitor.
# Do not call this from the per-minute stats poll.
print encode_json( node_identity() );
