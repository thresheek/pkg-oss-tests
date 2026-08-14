#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.var and set_by_lua_block.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(7)
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
                ngx.say(ngx.var.arg_who or "nobody")
            }
        }

        location /t2 {
            content_by_lua_block {
                ngx.say(ngx.var.request_uri)
            }
        }

        location /t3 {
            set $myvar "nginx-value";
            content_by_lua_block {
                ngx.say(ngx.var.myvar)
            }
        }

        location /t4 {
            set $myvar "";
            content_by_lua_block {
                ngx.var.myvar = "lua-written"
                ngx.say(ngx.var.myvar)
            }
        }

        location /t5 {
            set_by_lua_block $sum {
                return tostring(
                    tonumber(ngx.var.arg_a) + tonumber(ngx.var.arg_b)
                )
            }
            content_by_lua_block { ngx.say(ngx.var.sum) }
        }

        location /t6 {
            set_by_lua_block $upper {
                return string.upper(ngx.var.arg_s)
            }
            content_by_lua_block { ngx.say(ngx.var.upper) }
        }

        location /t7 {
            content_by_lua_block {
                ngx.say(ngx.var["http_x_custom"] or "absent")
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

is(body(http_get('/t1?who=lua')),   "lua\n",            'ngx.var.arg_who');
is(body(http_get('/t2?a=1')),       "/t2?a=1\n",        'ngx.var.request_uri');
is(body(http_get('/t3')),           "nginx-value\n",    'read nginx config var');
is(body(http_get('/t4')),           "lua-written\n",    'write nginx var from lua');
is(body(http_get('/t5?a=3&b=7')),   "10\n",             'set_by_lua_block sum');
is(body(http_get('/t6?s=hello')),   "HELLO\n",          'set_by_lua_block string op');
like(
	http("GET /t7 HTTP/1.0\r\nHost: localhost\r\nX-Custom: sentinel\r\n\r\n"),
	qr/sentinel/, 'ngx.var\["http_*"\] reads request header'
);

###############################################################################
