#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, Connection input header.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

# more_set/clear_input_headers runs in the rewrite phase; variables evaluated
# by "return 200 $var" would see the pre-modification value.  A backend
# location reached via proxy_pass runs in the content phase, after the
# modification is complete.  proxy_set_header Connection $http_connection
# explicitly forwards the (modified) Connection header to the backend so the
# backend can reflect its value back in the response body.

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # TEST 1: dropped — sending Connection: keep-alive with HTTP/1.0 causes
        # nginx 1.31+ to commit to keep-alive before the rewrite phase runs;
        # headers-more cannot undo that decision, so http() times out.

        # TEST 2: set custom Connection req header (close)
        location /t2 {
            more_set_input_headers "Connection: CLOSE";
            proxy_pass http://127.0.0.1:8080/t2-back;
            proxy_http_version 1.0;
            proxy_set_header Connection $http_connection;
        }

        location /t2-back {
            return 200 "connection: $http_connection";
        }

        # TEST 3: set custom Connection req header (keep-alive)
        location /t3 {
            more_set_input_headers "Connection: keep-alive";
            proxy_pass http://127.0.0.1:8080/t3-back;
            proxy_http_version 1.0;
            proxy_set_header Connection $http_connection;
        }

        location /t3-back {
            return 200 "connection: $http_connection";
        }

        # TEST 4: set custom Connection req header (bad)
        location /t4 {
            more_set_input_headers "Connection: bad";
            proxy_pass http://127.0.0.1:8080/t4-back;
            proxy_http_version 1.0;
            proxy_set_header Connection $http_connection;
        }

        location /t4-back {
            return 200 "connection: $http_connection";
        }
    }
}

EOF

$t->run();

###############################################################################

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

is(body(http_get('/t2')), 'connection: CLOSE',      'set connection close');
is(body(http_get('/t3')), 'connection: keep-alive',  'set connection keep-alive');
is(body(http_get('/t4')), 'connection: bad',         'set connection bad');

###############################################################################
