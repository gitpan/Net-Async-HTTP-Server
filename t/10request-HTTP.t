#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use IO::Async::Test;
use IO::Async::Loop;

use IO::Async::Stream;

use Net::Async::HTTP::Server;

my $CRLF = "\x0d\x0a";

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my @pending;
my $server = Net::Async::HTTP::Server->new(
   on_request => sub { push @pending, $_[1] },
);

ok( defined $server, 'defined $server' );

$loop->add( $server );

sub connect_client
{
   my ( $S1, $S2 ) = IO::Async::OS->socketpair( undef, "stream" );
   $server->on_stream( IO::Async::Stream->new( handle => $S2 ) );
   return $S1;
}

{
   my $client = connect_client;

   $client->write( "GET /some/path HTTP/1.1$CRLF$CRLF" );

   wait_for { @pending };

   my $req = ( shift @pending )->as_http_request;

   isa_ok( $req, "HTTP::Request" );

   is( $req->method, "GET", '$req->method' );
   is( $req->uri->path, "/some/path", '$req->uri->path' );
}

done_testing;
