#!/usr/bin/perl

# Tests for ngx_http_lua_module, phase handlers and ngx.get_phase.

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

    lua_shared_dict phases 1m;

    server_rewrite_by_lua_block {
        ngx.ctx.server_rewrote = "server-rewrite"
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # rewrite_by_lua_block
        location /t1 {
            rewrite_by_lua_block {
                ngx.ctx.phase = "rewrite"
            }
            content_by_lua_block {
                ngx.say(ngx.ctx.phase or "absent")
            }
        }

        # access_by_lua_block allow
        location /t2 {
            access_by_lua_block {
                -- allow all
            }
            content_by_lua_block { ngx.say("ok") }
        }

        # access_by_lua_block deny
        location /t3 {
            access_by_lua_block { ngx.exit(403) }
            content_by_lua_block { ngx.say("unreachable") }
        }

        # header_filter_by_lua_block
        location /t4 {
            content_by_lua_block { ngx.say("body") }
            header_filter_by_lua_block {
                ngx.header["X-Phase"] = "filtered"
            }
        }

        # body_filter_by_lua_block
        location /t5 {
            content_by_lua_block { ngx.say("hello") }
            body_filter_by_lua_block {
                if ngx.arg[1] then
                    ngx.arg[1] = string.upper(ngx.arg[1])
                end
            }
        }

        # log_by_lua_block
        location /t6 {
            content_by_lua_block { ngx.say("ok") }
            log_by_lua_block {
                ngx.log(ngx.NOTICE, "log_by_lua_block: ran")
            }
        }

        # server_rewrite_by_lua_block (set at http level above)
        location /t7 {
            content_by_lua_block {
                ngx.say(ngx.ctx.server_rewrote or "absent")
            }
        }

        # ngx.get_phase in rewrite
        location /t9 {
            rewrite_by_lua_block {
                ngx.ctx.rphase = ngx.get_phase()
            }
            content_by_lua_block {
                ngx.say(ngx.ctx.rphase)
            }
        }

        # ngx.get_phase in access
        location /t10 {
            access_by_lua_block {
                ngx.ctx.aphase = ngx.get_phase()
            }
            content_by_lua_block {
                ngx.say(ngx.ctx.aphase)
            }
        }

        # ngx.get_phase in content
        location /t11 {
            content_by_lua_block {
                ngx.say(ngx.get_phase())
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

is(body(http_get('/t1')), "rewrite\n",              'rewrite_by_lua_block sets ctx');
is(body(http_get('/t2')), "ok\n",                   'access_by_lua_block allow');
like(http_get('/t3'),      qr/ 403 /,               'access_by_lua_block deny');
like(http_get('/t4'),      qr/X-Phase: filtered/,   'header_filter_by_lua_block');
is(body(http_get('/t5')), "HELLO\n",                'body_filter_by_lua_block');

http_get('/t6');
like($t->read_file('error.log'), qr/log_by_lua_block: ran/, 'log_by_lua_block');

is(body(http_get('/t7')), "server-rewrite\n",       'server_rewrite_by_lua_block');
is(body(http_get('/t9')), "rewrite\n",              'get_phase in rewrite');
is(body(http_get('/t10')), "access\n",              'get_phase in access');
is(body(http_get('/t11')), "content\n",             'get_phase in content');

###############################################################################
