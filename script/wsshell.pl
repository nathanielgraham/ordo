#!/usr/bin/env perl

use strict;
use warnings;
use Mojo::UserAgent;
use AnyEvent::ReadLine::Gnu;
use EV;
use JSON;
#use Term::ANSIColor;
use Sys::Hostname;
use Data::Dumper;
use feature qw(say);

my $ua = Mojo::UserAgent->new(inactivity_timeout => 0);
my $ws = 'ws://0.0.0.0:3000/websocket';

$ua->websocket(
  $ws => sub {
    my ( $ua, $tx ) = @_;

    unless ($tx->is_websocket) {
      AnyEvent::ReadLine::Gnu->print("WebSocket handshake failed!\n");
      exit 0;
    }

    #my $request_number = 0;
    $tx->send('{ "command":"login_user", "token":"73ce858641425b45481b0bdf579a02bca51857cf" }');

    my $rl = new AnyEvent::ReadLine::Gnu
     prompt  => "ordo> ",
     on_line => sub {
      my $i = shift;
      return unless $i;
      exit 0 if $i && $i =~ /quit/i;
      my $json;
      eval {
         my $request = decode_json($i);
         #$request->{request_id} = ++$request_number;
         $json = encode_json($request);
      };
      if ($@) {
         AnyEvent::ReadLine::Gnu->print("wrong json format.\n");
         return;
      }
      if ( $json && !$tx->is_finished ) {
        $tx->send($json);
        #$request_number++;
        #AnyEvent::ReadLine::Gnu->print("Sent with request_id: $request_number\n");
      }
    };

    $tx->on(
      finish => sub {
        my ( $tx, $code ) = @_;
        AnyEvent::ReadLine::Gnu->print("WebSocket closed with code $code.\n");
        exit 0;
      }
    );

    $tx->on(
      message => sub {
        my ( $tx, $msg ) = @_;
        my $json = to_json( decode_json($msg), { pretty => 1} );
        AnyEvent::ReadLine::Gnu->print("\n$json\n");
      }
    );

  }
);

EV::run;

=head1 NAME

wsshell.pl - WebSocket Shell

=head1 VERSION

0.03

=cut

our $VERSION = '0.03';

=head1 DESCRIPTION

This is a command line interface to the ordo job scheduler. It establishes a websocket connection to the server and allows you to receive and send JSON encoded messages from the command line.  

=head1 PREREQUESITES

Mojo::UserAgent;
AnyEvent::ReadLine::Gnu;
EV;

=head1 LICENSE AND COPYRIGHT

Copyright 2025 Nathaniel Graham.

This program is free software; you can redistribute it and/or modify it
under the terms of the MIT license.

=head1 SCRIPT CATEGORIES

Networking

=cut
