#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use_ok( "Net::Async::HTTP::Server" );
use_ok( "Net::Async::HTTP::Server::Request" );

done_testing;
