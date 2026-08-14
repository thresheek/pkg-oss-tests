#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.ctx and ngx.location.capture.

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

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            content_by_lua_block {
                ngx.ctx.msg = "hello ctx"
                ngx.say(ngx.ctx.msg)
            }
        }

        location /t2 {
            rewrite_by_lua_block {
                ngx.ctx.phase = "rewrite"
            }
            content_by_lua_block {
                ngx.say(ngx.ctx.phase or "absent")
            }
        }

        location /t3 {
            set $shared "";
            content_by_lua_block {
                ngx.ctx.val = "parent"
                local res = ngx.location.capture("/t3sub")
                ngx.say("parent: ", ngx.ctx.val)
                ngx.say("sub:    ", res.body)
            }
        }
        location /t3sub {
            content_by_lua_block {
                -- subrequest has its own ctx
                ngx.ctx.val = "child"
                ngx.say(ngx.ctx.val)
            }
        }

        location /t4 {
            content_by_lua_block {
                local res = ngx.location.capture("/t4back")
                ngx.print("status=", res.status, " body=", res.body)
            }
        }
        location /t4back {
            content_by_lua_block { ngx.say("captured") }
        }

        location /t5 {
            content_by_lua_block {
                local res = ngx.location.capture("/t5back",
                    {args = {key = "val"}})
                ngx.print(res.body)
            }
        }
        location /t5back {
            content_by_lua_block {
                ngx.say(ngx.var.arg_key or "absent")
            }
        }

        location /t6 {
            content_by_lua_block {
                local res = ngx.location.capture("/t6back",
                    {method = ngx.HTTP_POST, body = "payload"})
                ngx.print(res.body)
            }
        }
        location /t6back {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say(ngx.req.get_body_data() or "empty")
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

is(body(http_get('/t1')), "hello ctx\n",               'ngx.ctx in same phase');
is(body(http_get('/t2')), "rewrite\n",                 'ngx.ctx rewrite to content');

my $r = body(http_get('/t3'));
like($r, qr/^parent: parent$/m,                        'ngx.ctx not leaked to subrequest');
like($r, qr/^sub:\s+child$/m,                          'subrequest has own ngx.ctx');

is(body(http_get('/t4')), "status=200 body=captured\n", 'ngx.location.capture status+body');
is(body(http_get('/t5')), "val\n",                      'ngx.location.capture with args');
is(body(http_get('/t6')), "payload\n",                  'ngx.location.capture POST body');

###############################################################################
