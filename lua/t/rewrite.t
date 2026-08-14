#!/usr/bin/perl

# Tests for ngx_http_lua_module, rewrite_by_lua_block specific scenarios.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(4)
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

        # t1: lua_need_request_body on — body readable in rewrite phase
        location /t1 {
            lua_need_request_body on;
            rewrite_by_lua_block {
                ngx.say(ngx.var.request_body or "nil")
                ngx.exit(200)
            }
        }

        # t2: lua_need_request_body off (default) — body not read
        location /t2 {
            rewrite_by_lua_block {
                ngx.say(ngx.var.request_body or "nil")
                ngx.exit(200)
            }
        }

        # t3: nginx variable set in rewrite phase, read in content phase
        location /t3 {
            set $shared "";
            rewrite_by_lua_block {
                ngx.var.shared = "from-rewrite"
            }
            content_by_lua_block {
                ngx.say(ngx.var.shared)
            }
        }

        # t4: ngx.location.capture_multi in rewrite phase
        location /t4 {
            rewrite_by_lua_block {
                local r1, r2 = ngx.location.capture_multi{
                    { "/t4a" },
                    { "/t4b" },
                }
                ngx.say(r1.body .. r2.body)
                ngx.exit(200)
            }
        }
        location /t4a { return 200 "A"; }
        location /t4b { return 200 "B"; }

        # rewrite_by_lua_no_postpone is NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF only
        # (not location-level); tested implicitly via redirect.t TEST 7/8
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

is(body(http("POST /t1 HTTP/1.0\r\nHost: localhost\r\n"
	. "Content-Length: 5\r\n\r\nhello")),
	"hello\n", 'lua_need_request_body on — body readable in rewrite');

is(body(http("POST /t2 HTTP/1.0\r\nHost: localhost\r\n"
	. "Content-Length: 5\r\n\r\nhello")),
	"nil\n", 'lua_need_request_body off — body not read');

is(body(http_get('/t3')), "from-rewrite\n",
	'nginx variable shared from rewrite to content phase');

is(body(http_get('/t4')), "AB\n",
	'capture_multi parallel subrequests in rewrite phase');

###############################################################################
