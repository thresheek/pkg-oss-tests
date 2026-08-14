#!/usr/bin/perl

# Tests for ngx_brotli_filter_module, HTTP/2.

###############################################################################

use warnings;
use strict;

use Test::More;
use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        http2        on;
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

# Precomputed brotli-compressed body: quality=1, lgwin=10.
# Generated with Python brotli 1.2.0:
#   brotli.compress(b"brotli nginx filter",      quality=1, lgwin=10)
#   brotli.compress(b"brotli nginx filter html", quality=1, lgwin=10)
my $br_plain = decode_base64('AwmAYnJvdGxpIG5naW54IGZpbHRlcgM=');
my $br_html  = decode_base64('gwuAYnJvdGxpIG5naW54IGZpbHRlciBodG1sAw==');

sub h2_body {
	my ($frames) = @_;
	return join '', map { $_->{data} }
		grep { $_->{type} eq 'DATA' } @$frames;
}

# test 17: H2 A-E: 'gzip, br'
my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ headers => [
	{ name => ':method',          value => 'GET',       mode => 0 },
	{ name => ':scheme',          value => 'http',      mode => 0 },
	{ name => ':path',            value => '/txt'                 },
	{ name => ':authority',       value => 'localhost', mode => 1 },
	{ name => 'accept-encoding',  value => 'gzip, br'            },
]});
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
my ($hframe) = grep { $_->{type} eq 'HEADERS' } @$frames;

is($hframe->{headers}->{'content-encoding'}, 'br',
	'h2 gzip, br - encoding');
is(h2_body($frames), $br_plain, 'h2 gzip, br - content');

# test 18: H2 A-E: 'b' on text/html
$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method',          value => 'GET',       mode => 0 },
	{ name => ':scheme',          value => 'http',      mode => 0 },
	{ name => ':path',            value => '/html'                },
	{ name => ':authority',       value => 'localhost', mode => 1 },
	{ name => 'accept-encoding',  value => 'b'                   },
]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

is(h2_body($frames), 'brotli nginx filter html', 'h2 b token');

###############################################################################
