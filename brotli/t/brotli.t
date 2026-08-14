#!/usr/bin/perl

# Tests for ngx_brotli_filter_module, Accept-Encoding negotiation.

###############################################################################

use warnings;
use strict;

use Test::More;
use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/)->plan(18)
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

        brotli            on;
        brotli_comp_level 1;
        brotli_min_length 1;
        brotli_types      text/plain;

        location /txt {
            default_type text/plain;
            return 200 "brotli nginx filter";
        }

        location /html {
            default_type text/html;
            return 200 "brotli nginx filter html";
        }
    }
}

EOF

$t->run();

###############################################################################

# Precomputed brotli-compressed bodies: quality=1, lgwin=10.
# Generated with Python brotli 1.2.0:
#   brotli.compress(b"brotli nginx filter",      quality=1, lgwin=10)
#   brotli.compress(b"brotli nginx filter html", quality=1, lgwin=10)
my $br_plain = decode_base64('AwmAYnJvdGxpIG5naW54IGZpbHRlcgM=');
my $br_html  = decode_base64('gwuAYnJvdGxpIG5naW54IGZpbHRlciBodG1sAw==');

sub req {
	my ($uri, $ae) = @_;
	return http(
		"GET $uri HTTP/1.0\r\n" .
		"Host: localhost\r\n" .
		"Accept-Encoding: $ae\r\n\r\n"
	);
}

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

# test 2: compressed 404 (text/html is always a brotli type)
like(req('/nonexistent', 'br'), qr/Content-Encoding: br/, 'compressed 404');

# test 3: A-E: 'gzip, br'
my $r = req('/txt', 'gzip, br');
like($r, qr/Content-Encoding: br/, 'gzip, br - encoding');
is(body($r), $br_plain, 'gzip, br - content');

# test 4: A-E: 'gzip, br, deflate'
$r = req('/txt', 'gzip, br, deflate');
like($r, qr/Content-Encoding: br/, 'gzip, br, deflate - encoding');
is(body($r), $br_plain, 'gzip, br, deflate - content');

# test 5: A-E: 'gzip, br;q=1, deflate'
$r = req('/txt', 'gzip, br;q=1, deflate');
like($r, qr/Content-Encoding: br/, 'gzip, br;q=1, deflate - encoding');
is(body($r), $br_plain, 'gzip, br;q=1, deflate - content');

# test 6: A-E: 'br;q=0.001'
$r = req('/txt', 'br;q=0.001');
like($r, qr/Content-Encoding: br/, 'br;q=0.001 - encoding');
is(body($r), $br_plain, 'br;q=0.001 - content');

# test 7: A-E: 'bro'
like(body(req('/txt', 'bro')), qr/\Abrotli nginx filter\z/, 'bro token');

# test 8: A-E: 'bo'
like(body(req('/txt', 'bo')), qr/\Abrotli nginx filter\z/, 'bo token');

# test 9: A-E: 'br;q=0'
like(body(req('/txt', 'br;q=0')), qr/\Abrotli nginx filter\z/, 'br;q=0');

# test 10: A-E: 'br;q=0.'
like(body(req('/txt', 'br;q=0.')), qr/\Abrotli nginx filter\z/, 'br;q=0.');

# test 11: A-E: 'br;q=0.0'
like(body(req('/txt', 'br;q=0.0')), qr/\Abrotli nginx filter\z/, 'br;q=0.0');

# test 12: A-E: 'br;q=0.00'
like(body(req('/txt', 'br;q=0.00')), qr/\Abrotli nginx filter\z/, 'br;q=0.00');

# test 13: A-E: 'br ; q = 0.000'
like(body(req('/txt', 'br ; q = 0.000')), qr/\Abrotli nginx filter\z/,
	'br ; q = 0.000');

# test 14: A-E: 'bar' on text/html (always a brotli type)
like(body(req('/html', 'bar')), qr/\Abrotli nginx filter html\z/, 'bar token');

# test 15: A-E: 'b' on text/html
like(body(req('/html', 'b')), qr/\Abrotli nginx filter html\z/, 'b token');

###############################################################################
