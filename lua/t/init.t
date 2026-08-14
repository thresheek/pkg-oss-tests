#!/usr/bin/perl

# Tests for ngx_http_lua_module, init_by_lua_block, init_worker_by_lua_block,
# exit_worker_by_lua_block.

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

    lua_shared_dict init 1m;

    init_by_lua_block {
        -- runs once in master process before workers fork
        ngx.shared.init:set("init_by_lua", 1)
    }

    init_worker_by_lua_block {
        -- runs once per worker process at startup
        local d = ngx.shared.init
        local v = d:get("init_worker_count") or 0
        d:set("init_worker_count", v + 1)
    }

    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "exit_worker_by_lua_block: ran")
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            content_by_lua_block {
                ngx.say(ngx.shared.init:get("init_by_lua") or 0)
            }
        }

        location /t2 {
            content_by_lua_block {
                local v = ngx.shared.init:get("init_worker_count") or 0
                ngx.say(v > 0 and "yes" or "no")
            }
        }

        location /t3 {
            content_by_lua_block {
                -- init_by_lua sets shared dict before workers start;
                -- verify workers can read it
                ngx.say(ngx.shared.init:get("init_by_lua") or 0)
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

is(body(http_get('/t1')), "1\n",    'init_by_lua_block sets shared dict');
is(body(http_get('/t2')), "yes\n",  'init_worker_by_lua_block ran');
is(body(http_get('/t3')), "1\n",    'init_by_lua_block value visible to workers');

$t->stop();
like($t->read_file('error.log'), qr/exit_worker_by_lua_block: ran/,
	'exit_worker_by_lua_block ran on shutdown');

###############################################################################
