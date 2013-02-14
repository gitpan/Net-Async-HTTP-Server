#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Net::Async::HTTP::Server::Request;

use strict;
use warnings;

our $VERSION = '0.02';

use Carp;

my $CRLF = "\x0d\x0a";

=head1 NAME

C<Net::Async::HTTP::Server::Request> - represents a single outstanding request

=head1 DESCRIPTION

Objects in this class represent a single outstanding request received by a
L<Net::Async::HTTP::Server> instance. It allows access to the data received
from the web client and allows responding to it.

=cut

sub new
{
   my $class = shift;
   my ( $conn, $request ) = @_;

   return bless {
      conn => $conn,
      req  => $request,

      is_done => 0,
   }, $class;
}

=head1 METHODS

=cut

=head2 $method = $request->method

Return the method name from the request header.

=cut

sub method
{
   my $self = shift;
   return $self->{req}->method;
}

=head2 $path = $request->path

Return the path name from the request header.

=cut

sub path
{
   my $self = shift;
   return $self->{req}->uri->path;
}

=head2 $protocol = $request->protocol

Return the protocol version from the request header. This will be the full
string, such as C<HTTP/1.1>.

=cut

sub protocol
{
   my $self = shift;
   return $self->{req}->protocol;
}

=head2 $body = $request->body

Return the body content from the request as a string of bytes.

=cut

sub body
{
   my $self = shift;
   return $self->{req}->content;
}

=head2 $req = $request->as_http_request

Returns the data of the request as an L<HTTP::Request> object.

=cut

sub as_http_request
{
   my $self = shift;
   return $self->{req};
}

=head2 $request->respond( $response )

Respond to the request using the given L<HTTP::Response> object.

=cut

sub respond
{
   my $self = shift;
   my ( $response ) = @_;

   $self->{is_done} and croak "This request has already been completed";

   defined $response->protocol or
      $response->protocol( $self->protocol );
   defined $response->content_length or
      $response->content_length( length $response->content );

   $self->{response} = $response->as_string( $CRLF );
   $self->{is_done}  = 1;

   $self->{conn}->_flush_responders;
}

=head2 $request->respond_chunk_header( $response )

=head2 $request->respond_chunk( $data )

=head2 $request->respond_chunk_eof

Respond to the request using the given L<HTTP::Response> object to send in
HTTP/1.1 chunked encoding mode.

The headers in the C<$response> will be sent (which will be modified to set
the C<Transfer-Encoding> header). Each call to C<respond_chunk> will send
another chunk of data. C<respond_chunk_eof> will send the final EOF chunk.

If the C<$response> already contained content, that will be sent as one chunk
immediately after the header is sent.

=cut

sub respond_chunk_header
{
   my $self = shift;
   my ( $response ) = @_;

   $self->{is_done} and croak "This request has already been completed";

   defined $response->protocol or
      $response->protocol( $self->protocol );
   defined $response->header( "Transfer-Encoding" ) or
      $response->header( "Transfer-Encoding" => "chunked" );

   my $content = $response->content;

   $self->{response} = $response->as_string( $CRLF );
   # Trim any content from the header as it would need to be chunked
   $self->{response} =~ s/$CRLF$CRLF.*$/$CRLF$CRLF/s;

   $self->{conn}->_flush_responders;

   $self->respond_chunk( $response->content ) if length $response->content;
}

sub respond_chunk
{
   my $self = shift;
   my ( $data ) = @_;

   $self->{is_done} and croak "This request has already been completed";

   $self->{response} .= sprintf "%X$CRLF%s$CRLF", length $data, $data;

   $self->{conn}->_flush_responders;
}

sub respond_chunk_eof
{
   my $self = shift;

   $self->{is_done} and croak "This request has already been completed";

   $self->{response} .= "0$CRLF$CRLF";
   $self->{is_done} = 1;

   $self->{conn}->_flush_responders;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
