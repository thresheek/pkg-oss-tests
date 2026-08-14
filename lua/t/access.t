#!/usr/bin/perl

# Tests for ngx_http_lua_module, access_by_lua_block specific scenarios.

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

        # t1: satisfy any + deny all + ngx.exit(ngx.OK) — lua grants access
        location /t1 {
            satisfy any;
            deny    all;
            access_by_lua_block { ngx.exit(ngx.OK) }
            content_by_lua_block { ngx.say("allowed") }
        }

        # t2: satisfy any + deny all + ngx.DECLINED — lua abstains; 403
        location /t2 {
            satisfy any;
            deny    all;
            access_by_lua_block { ngx.exit(ngx.DECLINED) }
            content_by_lua_block { ngx.say("allowed") }
        }

        # t3: satisfy any + deny all + bare return — same as ngx.OK; 200
        location /t3 {
            satisfy any;
            deny    all;
            access_by_lua_block {
                -- bare return from chunk is treated as ngx.exit(ngx.OK)
                return
            }
            content_by_lua_block { ngx.say("allowed") }
        }

        # t4: no satisfy + deny all + access_by_lua ngx.exit(500)
        #     ngx_access fires first and denies; lua never runs -> 403
        location /t4 {
            deny    all;
            access_by_lua_block { ngx.exit(500) }
            content_by_lua_block { ngx.say("allowed") }
        }

        # t5: access phase is not run in subrequests
        location /t5 {
            content_by_lua_block {
                local res = ngx.location.capture("/t5_sub")
                ngx.say("body:[" .. res.body .. "]")
            }
        }
        location /t5_sub {
            access_by_lua_block {
                -- this must NOT run in a subrequest
                ngx.say("access-ran")
                ngx.exit(200)
            }
            content_by_lua_block { ngx.say("content") }
        }

        # t6: IP-based gate — client is always 127.0.0.1 in tests
        location /t6 {
            access_by_lua_block {
                if ngx.var.remote_addr == "127.0.0.1" then
                    ngx.exit(ngx.HTTP_FORBIDDEN)
                end
            }
            content_by_lua_block { ngx.say("allowed") }
        }

        # t7: POST body inspection gate — redirect on prohibited content
        location /t7 {
            lua_need_request_body on;
            access_by_lua_block {
                local body = ngx.var.request_body or ""
                if string.find(body, "bad") then
                    ngx.redirect("/t7_blocked")
                end
            }
            content_by_lua_block { ngx.say("allowed") }
        }
        location /t7_blocked {
            return 200 "blocked";
        }

        # t8: access phase short-circuits content phase
        location /t8 {
            access_by_lua_block {
                ngx.say("from-access")
                ngx.exit(ngx.HTTP_OK)
            }
            content_by_lua_block { ngx.say("from-content") }
        }

        # t9: ngx.exit(ngx.OK) — content handler runs normally; no premature
        #     header commit from access phase
        location /t9 {
            access_by_lua_block { ngx.exit(ngx.OK) }
            content_by_lua_block {
                ngx.header["X-Phase"] = "content"
                ngx.say("from-content")
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

like(http_get('/t1'), qr/ 200 /, 'satisfy any: lua OK overrides deny all');
like(http_get('/t2'), qr/ 403 /, 'satisfy any: ngx.DECLINED does not grant access');
like(http_get('/t3'), qr/ 200 /, 'satisfy any: bare return grants access');
like(http_get('/t4'), qr/ 403 /, 'no satisfy: ngx_access denies before lua runs');

is(body(http_get('/t5')), "body:[content\n]\n",
	'access_by_lua_block not run in subrequests');

like(http_get('/t6'), qr/ 403 /, 'IP gate via ngx.var.remote_addr');

like(http("POST /t7 HTTP/1.0\r\nHost: localhost\r\n"
	. "Content-Length: 19\r\n\r\nthis is bad content"),
	qr/Location:.*t7_blocked/, 'body gate: prohibited content triggers redirect');

my $r = http_get('/t8');
like($r,    qr/from-access/,    'access phase short-circuits content');
unlike($r,  qr/from-content/,   'content handler not reached after access exit');

$r = http_get('/t9');
like($r, qr/X-Phase: content/, 'ngx.exit(OK) in access: content handler sets headers');

###############################################################################
