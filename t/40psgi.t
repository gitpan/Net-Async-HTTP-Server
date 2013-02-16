#!/usr/bin/perl -w

use strict;
use lib 't/lib';

use Test::More tests => 16;
use Test::Identity;

use IO::Async::Loop;
use IO::Async::Test;

use Net::Async::HTTP::Server::PSGI;

my $CRLF = "\x0d\x0a";

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $received_env;

my $server = Net::Async::HTTP::Server::PSGI->new(
   app => sub {
      # Simplest PSGI app
      $received_env = shift;
      return [
         200,
         [ "Content-Type" => "text/plain" ],
         [ "Hello, world" ],
      ];
   },
);

ok( defined $server, 'defined $server' );

$loop->add( $server );

$server->listen(
   addr => { family => "inet", socktype => "stream", ip => "127.0.0.1" },
   on_listen_error => sub { die "Test failed early - $_[-1]" },
);

my $C = IO::Socket::INET->new(
   PeerHost => $server->read_handle->sockhost,
   PeerPort => $server->read_handle->sockport,
) or die "Cannot connect - $@";

{
   $server->configure( app => sub {
      # Simplest PSGI app
      $received_env = shift;
      return [
         200,
         [ "Content-Type" => "text/plain" ],
         [ "Hello, world" ],
      ];
   } );

   $C->write(
      "GET / HTTP/1.1$CRLF" .
      $CRLF
   );

   wait_for { defined $received_env };

   # Some keys are awkward, handle them first
   ok( defined(delete $received_env->{'psgi.input'}), "psgi.input exists" );
   ok( defined(delete $received_env->{'psgi.errors'}), "psgi.errors exists" );

   identical( delete $received_env->{'net.async.http.server'}, $server, "net.async.http.server is \$server" );
   can_ok( delete $received_env->{'net.async.http.server.req'}, "header" );
   identical( delete $received_env->{'io.async.loop'}, $loop, "io.async.loop is \$loop" );

   is_deeply( $received_env,
      {
         PATH_INFO       => "",
         QUERY_STRING    => "",
         REMOTE_ADDR     => "127.0.0.1",
         REMOTE_PORT     => $C->sockport,
         REQUEST_METHOD  => "GET",
         REQUEST_URI     => "/",
         SCRIPT_NAME     => "",
         SERVER_NAME     => "127.0.0.1",
         SERVER_PORT     => $server->read_handle->sockport,
         SERVER_PROTOCOL => "HTTP/1.1",

         'psgi.version'      => [1,0],
         'psgi.url_scheme'   => "http",
         'psgi.run_once'     => 0,
         'psgi.multiprocess' => 0,
         'psgi.multithread'  => 0,
         'psgi.streaming'    => 1,
         'psgi.nonblocking'  => 1,
      },
      'received $env in PSGI app'
   );

   my $expect = join( "", map "$_$CRLF",
         "HTTP/1.1 200 OK",
         "Content-Length: 12",
         "Content-Type: text/plain",
         '' ) .
      "Hello, world";

   my $buffer = "";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;

   is( $buffer, $expect, 'Received ARRAY-written response' );
}

{
   $server->configure( app => sub {
      my $env = shift;
      my $input = delete $env->{'psgi.input'};

      my $content = "";
      while( $input->read( my $buffer, 1024 ) ) {
         $content .= $buffer;
      }

      return [
         200,
         [ "Content-Type" => "text/plain" ],
         [ "Input was: $content" ],
      ];
   } );

   $C->syswrite(
      "GET / HTTP/1.1$CRLF" .
      "Content-Length: 18$CRLF" .
      $CRLF .
      "Some data on STDIN"
   );

   my $expect = join( "", map "$_$CRLF",
         "HTTP/1.1 200 OK",
         "Content-Length: 29",
         "Content-Type: text/plain",
         '' ) .
      "Input was: Some data on STDIN";

   my $buffer = "";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;

   is( $buffer, $expect, 'Received ARRAY-written response with stdin reading' );
}

{
   $server->configure( app => sub {
      my $env = shift;

      open my $body, "<", \"Here is a IO-like string";

      return [
         200,
         [ "Content-Type" => "text/plain" ],
         $body,
      ];
   } );

   $C->syswrite(
      "GET / HTTP/1.1$CRLF" .
      $CRLF
   );

   my $expect = join( "", map "$_$CRLF",
         "HTTP/1.1 200 OK",
         "Transfer-Encoding: chunked",
         "Content-Type: text/plain",
         '' ) .
      "18$CRLF" . "Here is a IO-like string" . $CRLF .
      "0$CRLF$CRLF";

   my $buffer = "";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;

   is( $buffer, $expect, 'Received IO-written response' );
}

{
   my $responder;
   $server->configure( app => sub {
      my $env = shift;
      return sub { $responder = shift };
   } );

   $C->syswrite(
      "GET / HTTP/1.1$CRLF" .
      $CRLF
   );

   wait_for { defined $responder };

   is( ref $responder, "CODE", '$responder is a CODE ref' );

   $responder->(
      [ 200, [ "Content-Type" => "text/plain" ], [ "body from responder" ] ]
   );

   my $expect = join( "", map "$_$CRLF",
         "HTTP/1.1 200 OK",
         "Content-Length: 19",
         "Content-Type: text/plain",
         '' ) .
      "body from responder";

   my $buffer = "";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;

   is( $buffer, $expect, 'Received responder-written response' );
}

{
   my $responder;
   $server->configure( app => sub {
      my $env = shift;
      return sub { $responder = shift };
   } );

   $C->syswrite(
      "GET / HTTP/1.1$CRLF" .
      $CRLF
   );

   wait_for { defined $responder };

   is( ref $responder, "CODE", '$responder is a CODE ref' );

   my $writer = $responder->(
      [ 200, [ "Content-Type" => "text/plain" ] ]
   );

   my $expect = join( "", map "$_$CRLF",
         "HTTP/1.1 200 OK",
         "Transfer-Encoding: chunked",
         "Content-Type: text/plain",
         '' );

   my $buffer = "";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;

   is( $buffer, $expect, 'Received responder-written header' );

   $buffer =~ s/^.*$CRLF$CRLF//s;

   $writer->write( "Some body " );

   $expect = "A${CRLF}Some body $CRLF";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;
   is( $buffer, "A${CRLF}Some body $CRLF", 'Received partial streamed body chunk' );
   $buffer = "";

   $writer->write( "content here" );
   $writer->close;

   $expect = "C${CRLF}content here$CRLF" .
             "0${CRLF}${CRLF}";
   wait_for_stream { length $buffer >= length $expect } $C => $buffer;

   is( $buffer, $expect, 'Received streamed body chunk and EOF' );
   $buffer = "";
}
