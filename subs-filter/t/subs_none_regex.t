#!/usr/bin/perl

# Tests for ngx_http_substitutions_filter_module, fixed-string and variable matching.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(3)
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

        # TEST 1: the "substitution" command with build-in variable matching
        location /t1 {
            default_type      text/plain;
            subs_filter_types text/plain;
            subs_filter http://$host https://$host;
            return 200 "http://localhost";
        }

        # TEST 2: the "substitution" command with custom variable matching
        location /t2 {
            default_type      text/plain;
            subs_filter_types text/plain;
            set $foo foo;
            subs_filter $foo bar;
            return 200 "barfoobar";
        }

        # TEST 3: the "substitution" command with insensitive matching
        location /t3 {
            default_type      text/plain;
            subs_filter_types text/plain;
            subs_filter foobar hello;
            subs_filter foobar world i;
            return 200 "FoObAr";
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/t1'), qr/https:\/\/localhost\z/, 'built-in variable matching');
like(http_get('/t2'), qr/barbarbar\z/, 'custom variable matching');
like(http_get('/t3'), qr/world\z/, 'case insensitive matching');

###############################################################################
