#!/usr/bin/perl

use strict;
use warnings;

use Net::Async::HTTP::Server;
use IO::Async::Loop;

use HTTP::Response;

my $loop = IO::Async::Loop->new();

my $httpserver = Net::Async::HTTP::Server->new(
   on_request => sub {
      my $self = shift;
      my ( $req, $token ) = @_;

      my $response = HTTP::Response->new( 200 );
      $response->add_content( "Hello, world!\n" );
      $response->content_type( "text/plain" );

      $self->respond( $token, $response );
   },
);

$loop->add( $httpserver );

$httpserver->listen(
   addr => { family => "inet6", socktype => "stream", port => 8080 },
   on_listen_error => sub { die "Cannot listen - $_[-1]\n" },
);

$loop->run;
