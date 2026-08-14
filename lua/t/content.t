#!/usr/bin/perl

# Tests for ngx_http_lua_module, content output directives.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(8)
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
            content_by_lua_block { ngx.say("hello world") }
        }

        location /t2 {
            content_by_lua_block {
                ngx.print("hello")
                ngx.print(" world")
            }
        }

        location /t3 {
            content_by_lua_block { ngx.say(nil) }
        }

        location /t4 {
            content_by_lua_block { ngx.say(true, " ", false) }
        }

        location /t5 {
            content_by_lua_block { ngx.say(123) }
        }

        location /t6 {
            content_by_lua_block { ngx.say({10, {0, 5}, 15}) }
        }

        location /t7 {
            content_by_lua_file %%TESTDIR%%/hello.lua;
        }

        location /t8 {
            content_by_lua_block {
                ngx.say("who: " .. (ngx.var.arg_who or "nobody"))
            }
        }
    }
}

EOF

$t->write_file('hello.lua', 'ngx.say("from file")');

$t->run();

###############################################################################

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

is(body(http_get('/t1')), "hello world\n",    'say string');
is(body(http_get('/t2')), "hello world",       'print string no newline');
is(body(http_get('/t3')), "nil\n",             'say nil');
is(body(http_get('/t4')), "true false\n",      'say booleans');
is(body(http_get('/t5')), "123\n",             'say number');
is(body(http_get('/t6')), "100515\n",          'say iolist');
is(body(http_get('/t7')), "from file\n",       'content_by_lua_file');
is(body(http_get('/t8?who=lua')), "who: lua\n", 'ngx.var.arg_* in content');

###############################################################################
