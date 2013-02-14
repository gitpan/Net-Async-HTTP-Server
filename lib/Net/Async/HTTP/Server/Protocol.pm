#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Net::Async::HTTP::Server::Protocol;

use strict;
use warnings;
use base qw( IO::Async::Protocol::Stream );

our $VERSION = '0.02';

use Carp;

use Net::Async::HTTP::Server::Request;

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

      push @{ $self->{responder_queue} }, my $req = Net::Async::HTTP::Server::Request->new( $self, $request );
      $self->parent->_received_request( $req );

      return undef;
   };
}

sub _flush_responders
{
   my $self = shift;

   my $queue = $self->{responder_queue};
   while( @$queue and defined $queue->[0]{response} ) {
      my $head = $queue->[0];

      $self->write( $head->{response},

         $head->protocol eq "HTTP/1.0" ?
            ( on_flush => sub { $self->close; } ) : (),
      );
      $head->{response} = "";

      $head->{is_done} ? shift @$queue : return;
   }
}

0x55AA;
