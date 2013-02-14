#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2;

use_ok( "Net::Async::HTTP::Server" );
use_ok( "Net::Async::HTTP::Server::Request" );
