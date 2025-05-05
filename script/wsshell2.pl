#!/usr/bin/env perl

use strict;
use warnings;
use Mojo::UserAgent;
use Term::ReadLine::Perl5;
use EV;
use AE;
use JSON;
use feature qw(say);

#use Term::ANSIColor;
use Sys::Hostname;
use Data::Dumper;

my $ua   = Mojo::UserAgent->new( inactivity_timeout => 0 );
my $ws   = 'ws://0.0.0.0:3000/websocket';

$ua->websocket(
   $ws => sub {
      my ( $ua, $tx ) = @_;

      unless ( $tx->is_websocket ) {
         print("WebSocket handshake failed!\n");
         exit 0;
      }

      $tx->send('[ "login", { "token":"1bb6eda29b864133bf8fc776d11dc8c0b228f9dc", "request_id":"0" } ]');

      my $request_number = 0;
      my $prompt         = '> ';

   my $term = Term::ReadLine->new('test');
    $term->event_loop(sub {
      my $data = shift;
      $data->[1] = AE::cv();
      $data->[1]->recv();
    }, sub {
       my $fh = shift;
       my $data = [];
       $data->[0] = AE::io($fh, 0, sub { $data->[1]->send() });
       return $data;
    });

      # black  red  green  yellow  blue  magenta  cyan  white
      #my $prompt = colored('ordo', 'green') . ':' . colored('box1', 'cyan') . '>';
      #my $prompt = "ordo> ";
      #color('reset');

      $tx->on(
         finish => sub {
            my ( $tx, $code ) = @_;
            print("WebSocket closed with code $code.\n");
            exit 0;
         }
      );

      $tx->on(
         message => sub {
            my ( $tx, $msg ) = @_;
            my $json = to_json( decode_json($msg), { pretty => 1 } );
            $term->OUT(undef);
            say($json);
            $term->OUT(\*STDOUT);
            #$rl->{prompt} = "junk:$request_number> ";
            #$rl->{display_prompt} = "junk:$request_number> ";
            #$term->readline('> ');
         }
      );

      $term->OUT(undef);
      while ( defined( $_ = $term->readline('prompt>') ) ) {
         $tx->send($_);
      }
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
