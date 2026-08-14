#!/usr/bin/perl

# Tests for ngx_http_substitutions_filter_module, regex substitution and bypass.

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

        location /backend {
            default_type text/html;
            return 200 "Find taobao.com here.";
        }

        # TEST 1: the "regex substitution" command
        location /t1 {
            subs_filter 'taobao.com' 'yaoweibin' ir;
            proxy_pass http://127.0.0.1:8080/backend;
        }

        # TEST 2: the "subs_filter_bypass" directive, one variable
        location /t2 {
            set $bypass "1";
            subs_filter 'taobao.com' 'yaoweibin' ir;
            subs_filter_bypass $bypass;
            proxy_pass http://127.0.0.1:8080/backend;
        }

        # TEST 3: the "subs_filter_bypass" directive, two variables
        location /t3 {
            set $foo "0";
            set $bypass "1";
            subs_filter 'taobao.com' 'yaoweibin' ir;
            subs_filter_bypass $foo $bypass;
            proxy_pass http://127.0.0.1:8080/backend;
        }

        # TEST 4: the "subs_filter_bypass" directive, raw string "1"
        location /t4 {
            subs_filter 'taobao.com' 'yaoweibin' ir;
            subs_filter_bypass "1";
            proxy_pass http://127.0.0.1:8080/backend;
        }

        # TEST 5: the "subs_filter_bypass" directive, raw string "0" (not bypassed)
        location /t5 {
            subs_filter 'taobao.com' 'yaoweibin' ir;
            subs_filter_bypass "0";
            proxy_pass http://127.0.0.1:8080/backend;
        }
    }
}

EOF

$t->run();

###############################################################################

unlike(http_get('/t1'), qr/taobao\.com/, 'regex substitution');
like(http_get('/t2'),   qr/taobao\.com/, 'bypass variable active');
like(http_get('/t3'),   qr/taobao\.com/, 'bypass multiple variables active');
like(http_get('/t4'),   qr/taobao\.com/, 'bypass raw string 1');
unlike(http_get('/t5'), qr/taobao\.com/, 'bypass raw string 0 not active');

###############################################################################
