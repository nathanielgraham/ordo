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

my $ua = Mojo::UserAgent->new(inactivity_timeout => 0);
my $ws = 'ws://0.0.0.0:3000/websocket';
my $user = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
my $host = hostname;

$ua->websocket(
  $ws => sub {
    my ( $ua, $tx ) = @_;

    unless ($tx->is_websocket) {
      AnyEvent::ReadLine::Gnu->print("WebSocket handshake failed!\n");
      exit 0;
    }

    $tx->send('[ "login", { "bookmark":"1d53c9a4e58a0b76f4ab7ad900d8db7814f4d27e"} ]');
    #$tx->send('{"command":"login","bookmark":"1d53c9a4e58a0b76f4ab7ad900d8db7814f4d27e"}');
    my $request_number = 1;

     # black  red  green  yellow  blue  magenta  cyan  white
    #my $prompt = colored('ordo', 'green') . ':' . colored('box1', 'cyan') . '>';
    my $prompt = 'ordo> ';
    #color('reset');

    my $rl = new AnyEvent::ReadLine::Gnu
     prompt  => $prompt,
     on_line => sub {
      my $i = shift;
      exit 0 if $i && $i =~ /quit/i;
      my $json;
      eval {
         my $request = decode_json($i);
         $request->[1]->{request_id} = ++$request_number;
         $json = encode_json($request);
      };
      if ($@) {
         AnyEvent::ReadLine::Gnu->print("unable to parse json.\n");
         return;
      }
      if ( $json && !$tx->is_finished ) {
        $tx->send($json);
        AnyEvent::ReadLine::Gnu->print("Sent request_id: $request_number\n");
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
        AnyEvent::ReadLine::Gnu->print($json);
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
