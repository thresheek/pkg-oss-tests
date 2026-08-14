#!/usr/bin/perl

# Tests for ngx_http_lua_module, lua_shared_dict and ngx.shared.DICT.

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

    lua_shared_dict mydict 1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:set("k", "hello")
                ngx.say(d:get("k"))
            }
        }

        location /t2 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:set("n", 42)
                ngx.say(d:get("n"))
            }
        }

        location /t3 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:set("del", "bye")
                d:delete("del")
                ngx.say(d:get("del") or "nil")
            }
        }

        location /t4 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:set("ctr", 10)
                d:incr("ctr", 5)
                ngx.say(d:get("ctr"))
            }
        }

        location /t5 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:delete("newctr")
                local val, err = d:incr("newctr", 1, 100)
                ngx.say(val)
            }
        }

        location /t6 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:flush_all()
                d:set("present", 1)
                local keys = d:get_keys()
                local found = false
                for _, k in ipairs(keys) do
                    if k == "present" then found = true end
                end
                ngx.say(found and "yes" or "no")
            }
        }

        location /t7 {
            content_by_lua_block {
                local d = ngx.shared.mydict
                d:set("gone", "yes")
                d:flush_all()
                ngx.say(d:get("gone") or "nil")
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

is(body(http_get('/t1')), "hello\n",  'shdict set and get string');
is(body(http_get('/t2')), "42\n",     'shdict set and get number');
is(body(http_get('/t3')), "nil\n",    'shdict delete');
is(body(http_get('/t4')), "15\n",     'shdict incr existing key');
is(body(http_get('/t5')), "101\n",    'shdict incr with init value');
is(body(http_get('/t6')), "yes\n",    'shdict get_keys');
is(body(http_get('/t7')), "nil\n",    'shdict flush_all');

###############################################################################
