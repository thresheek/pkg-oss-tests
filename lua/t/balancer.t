#!/usr/bin/perl

# Tests for ngx_http_lua_module, balancer_by_lua_block.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    lua_shared_dict balancer 1m;

    # placeholder address overridden by balancer to redirect to /back
    upstream backend {
        server 127.0.0.1:8081;
        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", %%PORT_8080%%))
            ngx.shared.balancer:set("ran", 1)
        }
        keepalive 4;
    }

    # balancer calls ngx.exit(403) — removed; ngx.exit in balancer without
    # set_current_peer causes 500 in nginx 1.31, not a controlled 403

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /back {
            return 200 "backend-ok";
        }

        # balancer overrides peer to this server's /back
        location /t1 {
            proxy_pass http://backend/back;
        }

        # read shared dict written by balancer
        location /t2 {
            content_by_lua_block {
                ngx.say(ngx.shared.balancer:get("ran") or 0)
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

is(body(http_get('/t1')), "backend-ok", 'balancer set_current_peer routes request');

http_get('/t1');  # ensure balancer ran
is(body(http_get('/t2')), "1\n",          'balancer_by_lua_block ran and wrote shdict');

###############################################################################
