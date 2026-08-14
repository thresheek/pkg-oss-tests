#!/usr/bin/perl

# Tests for ngx_http_substitutions_filter_module, substitution commands.

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

my $t = Test::Nginx->new()->has(qw/http proxy gzip/)->plan(6)
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

        # backend used by proxy tests (tests 1, 2)
        location /backend {
            default_type text/html;
            return 200 "Find taobao.com here.";
        }

        # TEST 1: the "substitution" command (regex, case-insensitive)
        location /t1 {
            subs_filter 'taobao\.com' 'yaoweibin' ir;
            proxy_pass http://127.0.0.1:8080/backend;
        }

        # TEST 2: the "substitution" command with gzip
        location /t2 {
            gzip             on;
            gzip_http_version 1.0;
            gzip_min_length  1;
            proxy_set_header Accept-Encoding "";
            subs_filter 'taobao\.com' 'yaoweibin' ir;
            proxy_pass http://127.0.0.1:8080/backend;
        }

        # TEST 3: large line, all replacements (ir = regex case-insensitive)
        location /t3.txt {
            root             %%TESTDIR%%;
            default_type     text/plain;
            subs_filter_types text/plain;
            subs_filter 'a' 'b' ir;
        }

        # TEST 4: large line, once only (iro = regex case-insensitive once)
        location /t4.txt {
            root             %%TESTDIR%%;
            default_type     text/plain;
            subs_filter_types text/plain;
            subs_filter 'a' 'b' iro;
        }

        # TEST 5: large line, all replacements (fixed string, no flags)
        location /t5.txt {
            root             %%TESTDIR%%;
            default_type     text/plain;
            subs_filter_types text/plain;
            subs_filter 'a' 'b';
        }

        # TEST 6: large line, once only (o = fixed string once)
        location /t6.txt {
            root             %%TESTDIR%%;
            default_type     text/plain;
            subs_filter_types text/plain;
            subs_filter 'a' 'b' o;
        }
    }
}

EOF

my $big = ('a' x 242 . ' ') x 50 . "\n";
$t->write_file('t3.txt', $big);
$t->write_file('t4.txt', $big);
$t->write_file('t5.txt', $big);
$t->write_file('t6.txt', $big);

$t->run();

###############################################################################

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

# TEST 1
unlike(http_get('/t1'), qr/taobao\.com/, 'substitution');

# TEST 2
like(http("GET /t2 HTTP/1.0\r\nHost: localhost\r\nAccept-Encoding: gzip\r\n\r\n"),
	qr/Content-Encoding: gzip\r\n/, 'substitution with gzip');

# TEST 3
like(body(http_get('/t3.txt')), qr/\A[b \n]+\z/, 'large line all replaced (ir)');

# TEST 4
like(body(http_get('/t4.txt')), qr/\Ab[a \n]+\z/, 'large line once replaced (iro)');

# TEST 5
like(body(http_get('/t5.txt')), qr/\A[b \n]+\z/, 'large line all replaced (fixed string)');

# TEST 6
like(body(http_get('/t6.txt')), qr/\Ab[a \n]+\z/, 'large line once replaced (fixed string)');

###############################################################################
