#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.req.* API.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(10)
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

        location /t1 {
            content_by_lua_block {
                local h = ngx.req.get_headers()
                ngx.say(h["x-custom"] or "absent")
            }
        }

        location /t2 {
            content_by_lua_block {
                local h = ngx.req.get_headers()
                ngx.say(h["host"] or "absent")
            }
        }

        location /t3 {
            rewrite_by_lua_block {
                ngx.req.set_header("X-Injected", "lua-value")
            }
            content_by_lua_block {
                local h = ngx.req.get_headers()
                ngx.say(h["x-injected"] or "absent")
            }
        }

        location /t4 {
            content_by_lua_block {
                local args = ngx.req.get_uri_args()
                ngx.say(args["key"] or "absent")
            }
        }

        location /t5 {
            content_by_lua_block {
                ngx.req.set_uri_args({a = "new"})
                ngx.say(ngx.var.arg_a or "absent")
            }
        }

        location /t6 {
            content_by_lua_block {
                ngx.say(ngx.req.get_method())
            }
        }

        location /t7 {
            content_by_lua_block {
                ngx.req.set_method(ngx.HTTP_POST)
                ngx.say(ngx.req.get_method())
            }
        }

        location /t8 {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say(ngx.req.get_body_data() or "empty")
            }
        }

        location /t9 {
            content_by_lua_block {
                ngx.req.read_body()
                local args = ngx.req.get_post_args()
                ngx.say(args["field"] or "absent")
            }
        }

        location /t10 {
            content_by_lua_block {
                ngx.say(ngx.req.get_method())
            }
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

is(body(http("GET /t1 HTTP/1.0\r\nHost: localhost\r\nX-Custom: hello\r\n\r\n")),
	"hello\n", 'get_headers custom');

is(body(http_get('/t2')), "localhost\n", 'get_headers host');

is(body(http_get('/t3')), "lua-value\n", 'set_header visible to get_headers');

is(body(http_get('/t4?key=found')), "found\n", 'get_uri_args');

is(body(http_get('/t5?a=old')), "new\n", 'set_uri_args');

is(body(http_get('/t6')), "GET\n", 'get_method GET');

is(body(http_get('/t7')), "POST\n", 'set_method to POST');

is(body(http("POST /t8 HTTP/1.0\r\nHost: localhost\r\n"
	. "Content-Length: 4\r\n\r\nbody")),
	"body\n", 'read_body + get_body_data');

is(body(http("POST /t9 HTTP/1.0\r\nHost: localhost\r\n"
	. "Content-Type: application/x-www-form-urlencoded\r\n"
	. "Content-Length: 11\r\n\r\nfield=value")),
	"value\n", 'get_post_args');

is(body(http("DELETE /t10 HTTP/1.0\r\nHost: localhost\r\n\r\n")),
	"DELETE\n", 'get_method DELETE');

###############################################################################
