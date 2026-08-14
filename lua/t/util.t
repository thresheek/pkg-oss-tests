#!/usr/bin/perl

# Tests for ngx_http_lua_module, utility functions and ngx.timer.at.

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

    lua_shared_dict util 1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            content_by_lua_block {
                ngx.say(ngx.encode_base64("hello"))
            }
        }

        location /t2 {
            content_by_lua_block {
                ngx.say(ngx.decode_base64("aGVsbG8="))
            }
        }

        location /t3 {
            content_by_lua_block {
                ngx.say(ngx.escape_uri("hello world"))
            }
        }

        location /t4 {
            content_by_lua_block {
                ngx.say(ngx.unescape_uri("hello%20world"))
            }
        }

        location /t5 {
            content_by_lua_block {
                ngx.say(ngx.md5("hello"))
            }
        }

        location /t6 {
            content_by_lua_block {
                local t = ngx.time()
                ngx.say(t > 0 and "positive" or "not positive")
            }
        }

        location /t7 {
            content_by_lua_block {
                ngx.say(ngx.today())
            }
        }

        location /t8 {
            content_by_lua_block {
                local n = ngx.now()
                local t = ngx.time()
                ngx.say(n >= t and "ok" or "fail")
            }
        }

        location /t9 {
            content_by_lua_block {
                ngx.sleep(0)
                ngx.say("after sleep")
            }
        }

        location /t10 {
            content_by_lua_block {
                local d = ngx.shared.util
                d:set("timer", 0)
                local ok, err = ngx.timer.at(0, function()
                    ngx.shared.util:set("timer", 1)
                end)
                ngx.sleep(0.05)
                ngx.say(d:get("timer"))
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

is(body(http_get('/t1')), "aGVsbG8=\n",                          'encode_base64');
is(body(http_get('/t2')), "hello\n",                              'decode_base64');
is(body(http_get('/t3')), "hello%20world\n",                      'escape_uri');
is(body(http_get('/t4')), "hello world\n",                        'unescape_uri');
is(body(http_get('/t5')), "5d41402abc4b2a76b9719d911017c592\n",   'md5');
is(body(http_get('/t6')), "positive\n",                           'ngx.time positive');
like(body(http_get('/t7')), qr/\A\d{4}-\d{2}-\d{2}\n\z/,        'ngx.today format');
is(body(http_get('/t8')), "ok\n",                                 'ngx.now >= ngx.time');
is(body(http_get('/t9')), "after sleep\n",                        'ngx.sleep(0)');
is(body(http_get('/t10')), "1\n",                                 'ngx.timer.at fires');

###############################################################################
