#!/usr/bin/perl

# Tests for ngx_http_substitutions_filter_module, fixed string substitution.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(1)
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

        # TEST 1: the "fix string substitution" command (no flags = fixed string)
        location /t1 {
            subs_filter 'taobao.com' 'yaoweibin';
            proxy_pass http://127.0.0.1:8080/backend;
        }
    }
}

EOF

$t->run();

###############################################################################

unlike(http_get('/t1'), qr/taobao\.com/, 'fixed string substitution');

###############################################################################
