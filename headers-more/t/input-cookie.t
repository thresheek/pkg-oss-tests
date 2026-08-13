#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, Cookie input header.

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

# Tests that modify request headers use proxy_pass so that the backend
# location reflects variable values in the content phase (after the
# rewrite-phase modification has taken effect).

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(5)
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

        error_page 400 = /err;

        # TEST 1: clear cookie (with existing cookies)
        location /t1 {
            more_clear_input_headers Cookie;
            proxy_pass http://127.0.0.1:8080/t1-back;
            proxy_http_version 1.0;
            proxy_set_header Connection close;
        }

        location /t1-back {
            return 200 "$cookie_foo|$cookie_baz|$http_cookie";
        }

        # TEST 2: clear cookie (without existing cookies) — no modification,
        # "return 200" sees the correct (already empty) values
        location /t2 {
            more_clear_input_headers Cookie;
            return 200 "$cookie_foo|$cookie_baz|$http_cookie";
        }

        # TEST 3: set one custom cookie (with existing cookies)
        location /t3 {
            more_set_input_headers "Cookie: boo=123";
            proxy_pass http://127.0.0.1:8080/t3-back;
            proxy_http_version 1.0;
            proxy_set_header Connection close;
        }

        location /t3-back {
            return 200 "$cookie_foo|$cookie_baz|$cookie_boo|$http_cookie";
        }

        # TEST 4: set one custom cookie (without existing cookies)
        location /t4 {
            more_set_input_headers "Cookie: boo=123";
            proxy_pass http://127.0.0.1:8080/t4-back;
            proxy_http_version 1.0;
            proxy_set_header Connection close;
        }

        location /t4-back {
            return 200 "$cookie_foo|$cookie_baz|$cookie_boo|$http_cookie";
        }

        # TEST 5: bad request — verify no segfault when setting cookies
        location = /err {
            more_set_input_headers "Cookie: foo=bar";
            return 200 "${cookie_foo}ok";
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

like(body(http("GET /t1 HTTP/1.0\r\nHost: localhost\r\nCookie: foo=bar\r\nCookie: baz=blah\r\n\r\n")),
	qr/^\|\|$/, 'clear cookie with existing cookies');
like(body(http_get('/t2')),
	qr/^\|\|$/, 'clear cookie without existing cookies');
like(body(http("GET /t3 HTTP/1.0\r\nHost: localhost\r\nCookie: foo=bar\r\nCookie: baz=blah\r\n\r\n")),
	qr/^\|\|123\|boo=123$/, 'set cookie with existing cookies');
like(body(http_get('/t4')),
	qr/^\|\|123\|boo=123$/, 'set cookie without existing cookies');
like(body(http("GeT / HTTP/1.0\r\nHost: localhost\r\n\r\n")),
	qr/ok\z/, 'bad request no segfault');

###############################################################################
