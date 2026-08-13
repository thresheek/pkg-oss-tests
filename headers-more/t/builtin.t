#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, built-in header manipulation.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(38)
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

        # TEST 1: set Server
        location /t1 {
            more_set_headers 'Server: Foo';
            return 200 hi;
        }

        # TEST 2: clear Server
        location /t2 {
            more_clear_headers 'Server: ';
            return 200 hi;
        }

        # TEST 3: set Content-Type
        location /t3 {
            default_type 'text/plan';
            more_set_headers 'Content-Type: text/css';
            return 200 hi;
        }

        # TEST 4: set Content-Type (on 404)
        location /t4 {
            default_type 'text/plan';
            more_set_headers 'Content-Type: text/css';
            return 404;
        }

        # TEST 5: clear Content-Type
        location /t5 {
            default_type 'text/plain';
            more_clear_headers 'Content-Type: ';
            return 404;
        }

        # TEST 6: clear Content-Type (colon not required)
        location /t6 {
            default_type 'text/plain';
            more_set_headers 'Content-Type: Hello';
            more_clear_headers 'Content-Type';
            return 404;
        }

        # TEST 7: clear Content-Type (value ignored)
        location /t7 {
            default_type 'text/plain';
            more_set_headers 'Content-Type: Hello';
            more_clear_headers 'Content-Type: blah';
            return 404;
        }

        # TEST 8: clear Content-Type (case insensitive)
        location /t8 {
            default_type 'text/plain';
            more_set_headers 'Content-Type: Hello';
            more_clear_headers 'content-type: blah';
            return 404;
        }

        # TEST 9: clear Content-Type using set empty
        location /t9 {
            default_type 'text/plain';
            more_set_headers 'Content-Type: Hello';
            more_set_headers 'content-type:';
            return 404;
        }

        # TEST 10: clear Content-Type using setting key only
        location /t10 {
            default_type 'text/plain';
            more_set_headers 'Content-Type: Hello';
            more_set_headers 'content-type';
            return 404;
        }

        # TEST 11: set content-length
        # only the header value is asserted; body truncation is client-side
        location /t11 {
            more_set_headers 'Content-Length: 2';
            return 200 hello;
        }

        # TEST 12: set content-length multiple times (last wins)
        location /t12 {
            more_set_headers 'Content-Length: 2';
            more_set_headers 'Content-Length: 4';
            return 200 hello;
        }

        # TEST 13: clear content-length
        location /t13 {
            more_set_headers 'Content-Length: 4';
            more_set_headers 'Content-Length:';
            return 200 hello;
        }

        # TEST 14: clear content-length (another way)
        location /t14 {
            more_set_headers 'Content-Length: 4';
            more_clear_headers 'Content-Length';
            return 200 hello;
        }

        # TEST 15: clear content-type
        location /t15 {
            default_type 'text/plain';
            more_set_headers 'Content-Type:';
            return 200 hello;
        }

        # TEST 16: clear content-type (the other way)
        location /t16 {
            default_type 'text/plain';
            more_clear_headers 'Content-Type:';
            return 200 hello;
        }

        # TEST 17: set Charset
        location /t17 {
            default_type 'text/plain';
            more_set_headers 'Charset: gbk';
            return 200 hello;
        }

        # TEST 18: clear Charset
        location /t18 {
            default_type 'text/plain';
            more_set_headers 'Charset: gbk';
            more_clear_headers 'Charset';
            return 200 hello;
        }

        # TEST 19: clear Charset (the other way: using set)
        location /t19 {
            default_type 'text/plain';
            more_set_headers 'Charset: gbk';
            more_set_headers 'Charset: ';
            return 200 hello;
        }

        # TEST 20: set Vary (proxy overrides upstream Vary)
        location = /t20-foo {
            more_set_headers 'Vary: gbk';
            return 200 hello;
        }

        location /t20 {
            more_set_headers 'Vary: hello';
            proxy_pass http://127.0.0.1:8080/t20-foo;
        }
    }
}

EOF

$t->run();

###############################################################################

# TEST 1
like(http_get('/t1'), qr/Server: Foo\r\n/, 'set server');
like(http_get('/t1'), qr/hi\z/, 'set server body');

# TEST 2
unlike(http_get('/t2'), qr/Server:/, 'clear server');
like(http_get('/t2'), qr/hi\z/, 'clear server body');

# TEST 3
like(http_get('/t3'), qr/Content-Type: text\/css\r\n/, 'set content-type');
like(http_get('/t3'), qr/hi\z/, 'set content-type body');

# TEST 4
like(http_get('/t4'), qr/Content-Type: text\/css\r\n/, 'set content-type on 404');
like(http_get('/t4'), qr/ 404 /, 'set content-type 404 status');

# TEST 5
unlike(http_get('/t5'), qr/Content-Type:/, 'clear content-type');
like(http_get('/t5'), qr/ 404 /, 'clear content-type 404 status');

# TEST 6
unlike(http_get('/t6'), qr/Content-Type:/, 'clear content-type no colon');
like(http_get('/t6'), qr/ 404 /, 'clear content-type no colon 404 status');

# TEST 7
unlike(http_get('/t7'), qr/Content-Type:/, 'clear content-type value ignored');
like(http_get('/t7'), qr/ 404 /, 'clear content-type value ignored 404 status');

# TEST 8
unlike(http_get('/t8'), qr/Content-Type:/, 'clear content-type case insensitive');
like(http_get('/t8'), qr/ 404 /, 'clear content-type case insensitive 404 status');

# TEST 9
unlike(http_get('/t9'), qr/Content-Type:/, 'clear content-type set empty');
like(http_get('/t9'), qr/ 404 /, 'clear content-type set empty 404 status');

# TEST 10
unlike(http_get('/t10'), qr/Content-Type:/, 'clear content-type key only');
like(http_get('/t10'), qr/ 404 /, 'clear content-type key only 404 status');

# TEST 11 — only the header value is checked; actual body truncation is client behaviour
like(http_get('/t11'), qr/Content-Length: 2\r\n/, 'set content-length');

# TEST 12
like(http_get('/t12'), qr/Content-Length: 4\r\n/, 'set content-length multiple');

# TEST 13
unlike(http_get('/t13'), qr/Content-Length:/, 'clear content-length');
like(http_get('/t13'), qr/hello\z/, 'clear content-length body');

# TEST 14
unlike(http_get('/t14'), qr/Content-Length:/, 'clear content-length other way');
like(http_get('/t14'), qr/hello\z/, 'clear content-length other way body');

# TEST 15
unlike(http_get('/t15'), qr/Content-Type:/, 'clear content-type via set empty');
like(http_get('/t15'), qr/hello\z/, 'clear content-type via set empty body');

# TEST 16
unlike(http_get('/t16'), qr/Content-Type:/, 'clear content-type other way');
like(http_get('/t16'), qr/hello\z/, 'clear content-type other way body');

# TEST 17
like(http_get('/t17'), qr/Charset: gbk\r\n/, 'set charset');
like(http_get('/t17'), qr/hello\z/, 'set charset body');

# TEST 18
unlike(http_get('/t18'), qr/Charset:/, 'clear charset');
like(http_get('/t18'), qr/hello\z/, 'clear charset body');

# TEST 19
unlike(http_get('/t19'), qr/Charset:/, 'clear charset via set');
like(http_get('/t19'), qr/hello\z/, 'clear charset via set body');

# TEST 20
like(http_get('/t20'), qr/Vary: hello\r\n/, 'set vary overrides upstream');
like(http_get('/t20'), qr/hello\z/, 'set vary body');

###############################################################################
