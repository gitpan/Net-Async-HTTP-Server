#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Net::Async::HTTP::Server;

use strict;
use warnings;
use base qw( IO::Async::Listener );

our $VERSION = '0.04';

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
       my ( $req ) = @_;

       my $response = HTTP::Response->new( 200 );
       $response->add_content( "Hello, world!\n" );
       $response->content_type( "text/plain" );

       $req->respond( $response );
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

=head2 on_request $req

Invoked when a new HTTP request is received. It will be passed a
L<Net::Async::HTTP::Server::Request> object.

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
   );

   $self->add_child( $conn );

   return $conn;
}

sub _received_request
{
   my $self = shift;
   my ( $request ) = @_;

   $self->invoke_event( on_request => $request );
}

=head1 TODO

=over 2

=item *

Don't use L<HTTP::Message> objects as underlying implementation

=item *

Consider how to do streaming request inbound

=item *

Lots more testing

=back

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
