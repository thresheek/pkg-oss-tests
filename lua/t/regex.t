#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.re.* PCRE regex API.

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
            content_by_lua_block {
                local m = ngx.re.match("hello world", "(\\w+)\\s(\\w+)")
                if m then
                    ngx.say(m[0], "|", m[1], "|", m[2])
                else
                    ngx.say("no match")
                end
            }
        }

        location /t2 {
            content_by_lua_block {
                local m = ngx.re.match("hello", "\\d+")
                ngx.say(m and "match" or "no match")
            }
        }

        location /t3 {
            content_by_lua_block {
                local from, to = ngx.re.find("hello world", "world")
                ngx.say(from, " ", to)
            }
        }

        location /t4 {
            content_by_lua_block {
                local s = ngx.re.sub("hello world", "world", "lua")
                ngx.say(s)
            }
        }

        location /t5 {
            content_by_lua_block {
                local s = ngx.re.gsub("aabbcc", "[ac]", "x")
                ngx.say(s)
            }
        }

        location /t6 {
            content_by_lua_block {
                local it = ngx.re.gmatch("one two three", "\\w+")
                local words = {}
                while true do
                    local m = it()
                    if not m then break end
                    words[#words+1] = m[0]
                end
                ngx.say(table.concat(words, ","))
            }
        }

        location /t7 {
            content_by_lua_block {
                local m = ngx.re.match("Hello", "hello", "i")
                ngx.say(m and m[0] or "no match")
            }
        }

        location /t8 {
            content_by_lua_block {
                local from, to, err = ngx.re.find("foo123bar", "(\\d+)")
                ngx.say(from, " ", to)
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

is(body(http_get('/t1')), "hello world|hello|world\n", 'ngx.re.match captures');
is(body(http_get('/t2')), "no match\n",                 'ngx.re.match no match');
is(body(http_get('/t3')), "7 11\n",                     'ngx.re.find offsets');
is(body(http_get('/t4')), "hello lua\n",                'ngx.re.sub single');
is(body(http_get('/t5')), "xxbbxx\n",                   'ngx.re.gsub global');
is(body(http_get('/t6')), "one,two,three\n",             'ngx.re.gmatch iterator');
is(body(http_get('/t7')), "Hello\n",                    'ngx.re.match case insensitive');
is(body(http_get('/t8')), "4 6\n",                      'ngx.re.find with capture');

###############################################################################
