#!/usr/bin/perl

# Tests for ngx_http_substitutions_filter_module, content-type filtering.

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

my $t = Test::Nginx->new()->has(qw/http/)->plan(3)
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

        # TEST 1: default filter type (text/html) — substitution happens
        location /t1 {
            default_type text/html;
            subs_filter 'tom' 'yaoweibin' ir;
            return 200 "tom and jerry";
        }

        # TEST 2: subs_filter_types text/css on text/plain response — no match
        location /t2 {
            default_type      text/plain;
            subs_filter_types text/css;
            subs_filter 'tom' 'yaoweibin' ir;
            return 200 "tom and jerry";
        }

        # TEST 3: subs_filter_types text/xml on text/xml response — substitution happens
        location /t3 {
            default_type      text/xml;
            subs_filter_types text/xml;
            subs_filter 'tom' 'yaoweibin' ir;
            return 200 "tom and jerry";
        }
    }
}

EOF

$t->run();

###############################################################################

unlike(http_get('/t1'), qr/tom/, 'default type text/html substitution happens');
like(http_get('/t2'),   qr/tom/, 'type mismatch no substitution');
unlike(http_get('/t3'), qr/tom/, 'text/xml type substitution happens');

###############################################################################
