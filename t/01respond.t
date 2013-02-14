#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use IO::Async::Test;
use IO::Async::Loop;

use IO::Async::Stream;
use HTTP::Response;

use Net::Async::HTTP::Server;

my $CRLF = "\x0d\x0a";

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $server = Net::Async::HTTP::Server->new(
   on_request => sub {
      my ( $self, $req ) = @_;

      my $response = HTTP::Response->new( 200 );
      $response->content_type( "text/plain" );
      $response->add_content( "Response to " . join " ", $req->method, $req->path, "with " . length( $req->body ) . " bytes" );

      $req->respond( $response );
   },
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

   $client->write( "GET / HTTP/1.1$CRLF$CRLF" );

   my $buffer = "";
   wait_for_stream { $buffer =~ m/$CRLF$CRLF/ } $client => $buffer;

   is( $buffer,
      "HTTP/1.1 200 OK$CRLF" .
      "Content-Length: 30$CRLF" .
      "Content-Type: text/plain$CRLF" .
      $CRLF .
      "Response to GET / with 0 bytes",
      '$buffer from GET /' );
}

{
   my $client = connect_client;

   $client->write( "PUT /doc HTTP/1.1$CRLF" .
                   "Content-Type: text/plain$CRLF" .
                   "Content-Length: 13$CRLF" .
                   "$CRLF" .
                   "Hello, world!" );

   my $buffer = "";
   wait_for_stream { $buffer =~ m/$CRLF$CRLF/ } $client => $buffer;

   is( $buffer,
      "HTTP/1.1 200 OK$CRLF" .
      "Content-Length: 34$CRLF" .
      "Content-Type: text/plain$CRLF" .
      $CRLF .
      "Response to PUT /doc with 13 bytes",
      '$buffer from PUT' );
}

{
   my $client = connect_client;

   $client->write( "GET / HTTP/1.0$CRLF$CRLF" );

   my $buffer = "";
   wait_for_stream { $buffer =~ m/$CRLF$CRLF/ } $client => $buffer;

   ok( $client->read( my $tmp, 1 ) == 0, '$client no longer connected after HTTP/1.0 response' );
}

{
   my $client = connect_client;

   $client->write( "GET /one HTTP/1.1$CRLF$CRLF" .
                   "GET /two HTTP/1.1$CRLF$CRLF" );

   my $buffer = "";
   wait_for_stream { $buffer =~ m/$CRLF$CRLF.*$CRLF$CRLF/s } $client => $buffer;

   is( $buffer,
       "HTTP/1.1 200 OK$CRLF" .
       "Content-Length: 33$CRLF" .
       "Content-Type: text/plain$CRLF" .
       $CRLF .
       "Response to GET /one with 0 bytes" .
    
       "HTTP/1.1 200 OK$CRLF" .
       "Content-Length: 33$CRLF" .
       "Content-Type: text/plain$CRLF" .
       $CRLF .
       "Response to GET /two with 0 bytes",
      '$buffer from two pipelined GETs' );
}

my @pending;
$server->configure(
   on_request => sub { shift; push @pending, $_[0] },
);

{
   my $client = connect_client;

   $client->write( "GET /three HTTP/1.1$CRLF$CRLF" .
                   "GET /four HTTP/1.1$CRLF$CRLF" );

   wait_for { @pending == 2 };

   my ( $first, $second ) = @pending;

   my $response;
   $response = HTTP::Response->new( 200 );
   $response->add_content( "Response to second" );
   $second->respond( $response );

   $response = HTTP::Response->new( 200 );
   $response->add_content( "Response to first" );
   $first->respond( $response );

   my $buffer = "";
   wait_for_stream { $buffer =~ m/$CRLF$CRLF.*$CRLF$CRLF/s } $client => $buffer;

   is( $buffer,
       "HTTP/1.1 200 OK$CRLF" .
       "Content-Length: 17$CRLF" .
       $CRLF .
       "Response to first" .
    
       "HTTP/1.1 200 OK$CRLF" .
       "Content-Length: 18$CRLF" .
       $CRLF .
       "Response to second",
      '$buffer from two pipelined GETs responded in reverse order' );
}

done_testing;
