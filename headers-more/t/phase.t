#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, header set on deny phase.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(2)
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

        # TEST 1: simple set (1 arg)
        location /foo {
            deny all;
            more_set_headers 'X-Foo: Blah';
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/foo'), qr/X-Foo: Blah\r\n/, 'header set on 403');
like(http_get('/foo'), qr/ 403 /, 'deny returns 403');

###############################################################################
