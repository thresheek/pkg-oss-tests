#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, variables in header values.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(5)
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

        # TEST 1: vars
        location /t1 {
            set $val 'hello, world';
            more_set_headers 'X-Foo: $val';
            return 200 hi;
        }

        # TEST 2: vars in both key and val
        # header key is a literal "$val" (not expanded), value is expanded
        location /t2 {
            set $val 'hello, world';
            more_set_headers '$val: $val';
            return 200 hi;
        }

        # TEST 3: vars in input header directives
        # uses proxy_pass so the backend evaluates $host in the content phase,
        # after more_set_input_headers has updated the Host header
        location /t3 {
            set $val 'dog';
            more_set_input_headers 'Host: $val';
            proxy_pass http://127.0.0.1:8080/t3-back;
            proxy_http_version 1.0;
            proxy_set_header Connection close;
            proxy_set_header Host $http_host;
        }

        location /t3-back {
            return 200 $host;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/t1'), qr/X-Foo: hello, world\r\n/, 'var in value');
like(http_get('/t1'), qr/hi\z/, 'var in value body');
like(http_get('/t2'), qr/\$val: hello, world\r\n/, 'var in key is literal');
like(http_get('/t2'), qr/hi\z/, 'var in key body');
like(http_get('/t3'), qr/dog\z/, 'var in input header');

###############################################################################
