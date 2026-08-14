#!/usr/bin/perl

# Tests for ngx_stream_lua_module, stream content_by_lua_block and
# preread_by_lua_block.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http stream/)->plan(2)
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
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    # t1: content_by_lua_block — write response from Lua
    server {
        listen  127.0.0.1:8081;
        content_by_lua_block {
            ngx.say("stream-hello")
        }
    }

    # t2: preread_by_lua_block — runs before content phase
    server {
        listen  127.0.0.1:8082;
        preread_by_lua_block {
            ngx.log(ngx.NOTICE, "preread_by_lua_block: ran")
        }
        content_by_lua_block {
            ngx.say("preread-ok")
        }
    }
}

EOF

$t->run();

###############################################################################

is(stream('127.0.0.1:' . port(8081))->read(), "stream-hello\n",
	'stream content_by_lua_block ngx.say');

is(stream('127.0.0.1:' . port(8082))->read(), "preread-ok\n",
	'stream preread_by_lua_block runs before content');

###############################################################################
