#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.socket.tcp and ngx.req.socket.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(5)
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

        # echo server used as cosocket target
        location /echo {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data() or ""
                ngx.print(data)
            }
        }

        # t1: connect + send + receive
        location /t1 {
            content_by_lua_block {
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                local ok, err = sock:connect("127.0.0.1", %%PORT_8080%%)
                if not ok then
                    ngx.say("connect failed: ", err)
                    return
                end
                local req = "GET /echo HTTP/1.0\r\nHost: localhost\r\n"
                    .. "Content-Length: 5\r\n\r\nhello"
                sock:send(req)
                -- read status line
                local line = sock:receive("*l")
                ngx.say(line and "connected" or "no data")
                sock:close()
            }
        }

        # t2: receive with fixed size
        location /t2 {
            content_by_lua_block {
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                sock:connect("127.0.0.1", %%PORT_8080%%)
                sock:send("GET /t2back HTTP/1.0\r\nHost: localhost\r\n\r\n")
                -- skip headers
                repeat
                    local line = sock:receive("*l")
                until not line or line == ""
                local body = sock:receive(7)
                ngx.say(body)
                sock:close()
            }
        }
        location /t2back {
            return 200 "7chars!";
        }

        # t3: receiveuntil
        location /t3 {
            content_by_lua_block {
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                sock:connect("127.0.0.1", %%PORT_8080%%)
                sock:send("GET /t3back HTTP/1.0\r\nHost: localhost\r\n\r\n")
                local reader = sock:receiveuntil("\r\n")
                local line = reader()
                ngx.say(line and "got-status" or "fail")
                sock:close()
            }
        }
        location /t3back {
            return 200 "data";
        }

        # t4: ngx.req.socket for raw body reading
        location /t4 {
            lua_need_request_body off;
            content_by_lua_block {
                local sock, err = ngx.req.socket()
                if not sock then
                    ngx.say("no sock: ", err)
                    return
                end
                local data = sock:receive(5)
                ngx.say(data or "empty")
            }
        }

        # t5: connection refused to non-listening port
        location /t5 {
            content_by_lua_block {
                local sock = ngx.socket.tcp()
                sock:settimeout(200)
                local ok, err = sock:connect("127.0.0.1", 1)
                ngx.say(ok and "ok" or "refused")
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

is(body(http_get('/t1')),  "connected\n",   'tcp cosocket connect + receive line');
is(body(http_get('/t2')),  "7chars!\n",     'tcp cosocket receive fixed size');
is(body(http_get('/t3')),  "got-status\n",  'tcp cosocket receiveuntil');

is(body(http("POST /t4 HTTP/1.0\r\nHost: localhost\r\n"
	. "Content-Length: 5\r\n\r\nhello")),
	"hello\n", 'ngx.req.socket raw body read');

is(body(http_get('/t5')),  "refused\n",     'tcp cosocket connection refused');

###############################################################################
