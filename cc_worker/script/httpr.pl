#!/usr/bin/perl
use strict;
use warnings;
use AnyEvent;
use AnyEvent::HTTP;

# Configuration
my $url = 'https://example.com';
my $interval = 60; # seconds

# Create event loop
my $cv = AnyEvent->condvar;

# Set up timer for periodic requests
my $timer;
$timer = AnyEvent->timer(
    after => 0, # Start immediately
    interval => $interval,
    cb => sub {
        print "Making request to $url at ", scalar(localtime), "\n";
        
        # Make non-blocking HTTP request
        http_get $url, sub {
            my ($body, $hdr) = @_;
            if ($hdr->{Status} =~ /^2/) {
                print "Success: $hdr->{Status} $hdr->{Reason}\n";
            } else {
                print "Failed: $hdr->{Status} $hdr->{Reason}\n";
            }
        };
    }
);

# Start the event loop
print "Starting event loop...\n";
$cv->recv;
