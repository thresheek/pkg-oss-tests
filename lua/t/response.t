#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.header and ngx.status.

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
                ngx.header["X-Foo"] = "bar"
                ngx.say("ok")
            }
        }

        location /t2 {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/xml"
                ngx.say("ok")
            }
        }

        location /t3 {
            content_by_lua_block {
                ngx.header["Set-Cookie"] = {"a=1", "b=2"}
                ngx.say("ok")
            }
        }

        location /t4 {
            content_by_lua_block {
                ngx.status = 201
                ngx.say("created")
            }
        }

        location /t5 {
            content_by_lua_block {
                ngx.say(ngx.status)
            }
        }

        location /t6 {
            content_by_lua_block {
                ngx.header["X-Foo"] = "bar"
                ngx.header["X-Foo"] = nil
                ngx.say("ok")
            }
        }

        location /t7 {
            content_by_lua_block {
                ngx.header.Via = "my-proxy"
                ngx.say("ok")
            }
        }
    }
}

EOF

$t->run();

###############################################################################

my $r;

$r = http_get('/t1');
like($r, qr/X-Foo: bar/,         'ngx.header set');

$r = http_get('/t2');
like($r, qr!Content-Type: text/xml!, 'ngx.header content-type');

$r = http_get('/t3');
my @cookies = ($r =~ /Set-Cookie: (\S+)/g);
is(scalar @cookies, 2,            'ngx.header multi-value count');
ok((grep { $_ eq 'a=1' } @cookies) && (grep { $_ eq 'b=2' } @cookies),
	'ngx.header multi-value values');

like($r = http_get('/t4'), qr/ 201 /, 'ngx.status = 201');

like(http_get('/t5'), qr/\b200\b/,   'read ngx.status default 200');

$r = http_get('/t6');
unlike($r, qr/X-Foo:/,           'ngx.header nil removes header');

like(http_get('/t7'), qr/Via: my-proxy/, 'ngx.header dot notation');

###############################################################################
