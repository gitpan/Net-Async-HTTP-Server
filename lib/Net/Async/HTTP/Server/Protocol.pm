#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Net::Async::HTTP::Server::Protocol;

use strict;
use warnings;
use base qw( IO::Async::Protocol::Stream );

our $VERSION = '0.01';

use HTTP::Request;

my $CRLF = "\x0d\x0a";

sub on_read
{
   my $self = shift;
   my ( $buffref, $eof ) = @_;

   return 0 unless $$buffref =~ s/^(.*?$CRLF$CRLF)//s;
   my $header = $1;

   my $request = HTTP::Request->parse( $header );
   my $request_body_len = $request->content_length || 0;
   return sub {
      return 0 unless length($$buffref) >= $request_body_len;

      $request->add_content( substr( $$buffref, 0, $request_body_len, "" ) );

      push @{ $self->{responder_queue} }, [ undef, $request ];
      $self->parent->_received_request( $request, $self, $self->{responder_queue}[-1] );

      return undef;
   };
}

sub respond
{
   my $self = shift;
   my ( $responder, $response ) = @_;

   my $request = $responder->[1];

   defined $response->protocol or
      $response->protocol( $request->protocol );
   defined $response->content_length or
      $response->content_length( length $response->content );

   $responder->[0] = $response->as_string( $CRLF );

   my $queue = $self->{responder_queue};
   while( @$queue and defined $queue->[0][0] ) {
      my $head = shift @$queue;

      $self->write( $head->[0],

         $head->[1]->protocol eq "HTTP/1.0" ?
            ( on_flush => sub { $self->close; } ) : (),
      );
   }
}

0x55AA;
