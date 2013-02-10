#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Net::Async::HTTP::Server;

use strict;
use warnings;
use base qw( IO::Async::Listener );

our $VERSION = '0.01';

use Carp;

use Net::Async::HTTP::Server::Protocol;

=head1 NAME

C<Net::Async::HTTP::Server> - serve HTTP with C<IO::Async>

=head1 SYNOPSIS

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

=head1 DESCRIPTION

This module allows a program to respond asynchronously to HTTP requests, as
part of a program based on L<IO::Async>. An object in this class listens on a
single port and invokes the C<on_request> callback or subclass method whenever
an HTTP request is received, allowing the program to respond to it.

=cut

=head1 EVENTS

=head2 on_request $req, $token

Invoked when a new HTTP request is received. It will be passed an
L<HTTP::Request> object and an opaque token used to respond. This token should
be passed to the C<respond> method.

=cut

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( on_request )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->SUPER::configure( %params );
}

sub _add_to_loop
{
   my $self = shift;

   $self->can_event( "on_request" ) or croak "Expected either a on_request callback or an ->on_request method";

   $self->SUPER::_add_to_loop( @_ );
}

sub on_stream
{
   my $self = shift;
   my ( $stream ) = @_;
 
   my $conn = Net::Async::HTTP::Server::Protocol->new(
      transport => $stream,
#      on_closed => $self->_capture_weakself( sub {
#         my $self = shift;
#         $self->remove_child( $_[0] );
#      } ),
   );
 
   $self->add_child( $conn );
 
   return $conn;
}

sub _received_request
{
   my $self = shift;
   my ( $request, $conn, $responder ) = @_;

   $self->invoke_event( on_request => $request, [ $conn, $responder ] );
}

=head1 METHODS

=cut

# Demux all these to the conn
foreach (qw( respond )) {
   my $m = $_;
   no strict 'refs';
   *$m = sub {
      my $self = shift;
      my $token = shift;
      $token->[0]->$m( $token->[1], @_ );
   };
}

=head2 $server->respond( $token, $response )

Respond to the request earlier received with the given token, using the given
L<HTTP::Response> object.

=cut

=head1 TODO

=over 2

=item *

Streaming/chunked content response API. Likely

 $self->respond_header( $token, $response );
 $self->respond_chunk( $token, $content ); ...
 $self->respond_eof( $token );

=item *

Consider how to do streaming request inbound

=item *

PSGI app container

=item *

Lots more testing

=back

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
