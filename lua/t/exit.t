#!/usr/bin/perl

# Tests for ngx_http_lua_module, ngx.exit, ngx.redirect, ngx.exec.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(9)
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
            content_by_lua_block { ngx.exit(403) }
        }

        location /t2 {
            content_by_lua_block { ngx.exit(404) }
        }

        location /t3 {
            content_by_lua_block { ngx.exit(501) }
        }

        location /t4 {
            content_by_lua_block { ngx.exit(ngx.OK) }
        }

        location /t5 {
            content_by_lua_block {
                ngx.say("hi")
                ngx.exit(200)
            }
        }

        location /t6 {
            content_by_lua_block { ngx.redirect("/t5") }
        }

        location /t7 {
            content_by_lua_block { ngx.redirect("/t5", 301) }
        }

        location /t8 {
            content_by_lua_block { ngx.exec("/t5") }
        }

        location /t9 {
            content_by_lua_block {
                ngx.status = 201
                ngx.say("created")
                ngx.exit(201)
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

like(http_get('/t1'), qr/ 403 /,            'ngx.exit 403');
like(http_get('/t2'), qr/ 404 /,            'ngx.exit 404');
like(http_get('/t3'), qr/ 501 /,            'ngx.exit 501');
is(body(http_get('/t4')), '',               'ngx.exit ngx.OK empty body');
is(body(http_get('/t5')), "hi\n",           'ngx.exit 200 with body');
like(http_get('/t6'), qr/ 302 /,            'ngx.redirect 302');
like(http_get('/t6'), qr/Location:/,        'ngx.redirect location header');
like(http_get('/t7'), qr/ 301 /,            'ngx.redirect 301');
is(body(http_get('/t8')), "hi\n",           'ngx.exec internal redirect');

###############################################################################
