#!/usr/bin/perl

# Tests for ngx_http_geoip2_module, variable lookup.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geoip2 %%TESTDIR%%/country.mmdb {
        $geo_country_code  default=- source=$arg_ip country iso_code;
        $geo_country_name  default=- source=$arg_ip country names en;
        $geo_build_epoch   metadata build_epoch;
        $geo_proxy_cc      default=- country iso_code;
    }

    geoip2_proxy 127.0.0.1;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 { return 200 $geo_country_code; }
        location /t2 { return 200 $geo_country_code; }
        location /t3 { return 200 $geo_country_name; }
        location /t4 { return 200 $geo_build_epoch;  }
        location /t5 { return 200 $geo_proxy_cc;     }
    }
}

EOF

# Pre-generated with Python mmdb_writer 1.2.0 (ip_version=4, type=GeoIP2-Country):
#   1.2.3.0/24  -> {country: {iso_code: "AU", names: {en: "Australia"}}}
#   2.3.4.0/24  -> {country: {iso_code: "US", names: {en: "United States"}}}
#   127.0.0.0/8 -> {country: {iso_code: "CN", names: {en: "China"}}}
$t->write_file('country.mmdb', decode_base64(
	'AAABAAAvAAACAAApAAADAAAvAAAEAAAvAAAFAAAvAAAGAAAvAAAHAAAYAAAvAAAIAAAJAAAvAAAKAAAvAAALAAAvAAAMAAAvAAANAAAvAAAOAAAvAAAvAAAPAAAQAAAvAAARAAAvAAASAAAvAAATAAAvAAAUAAAvAAAVAAAvAAAWAAAvAAAvAAAXAAAvAAB0AAAZAAAvAAAaAAAvAAAbAAAvAAAcAAAvAAAdAAAvAAAeAAAvAAAfAAAvAAAvAAAgAAAvAAAhAAAiAAAvAAAjAAAvAAAkAAAvAAAlAAAvAAAmAAAvAAAvAAAnAAAoAAAvAACYAAAvAAAvAAAqAAAvAAArAAAvAAAsAAAvAAAtAAAvAAAuAAAvAAC0AAAAAAAAAAAAAAAAAAAAAEdjb3VudHJ5SGlzb19jb2RlQkFVRW5hbWVzQmVuSUF1c3RyYWxpYeEgGiAd4iAIIBEgFCAn4SAAICxCVVNNVW5pdGVkIFN0YXRlc+EgGiA94iAIIDogFCBL4SAAIFBCQ05FQ2hpbmHhIBogYeIgCCBeIBQgZ+EgACBsq83vTWF4TWluZC5jb23pSm5vZGVfY291bnTBL0tyZWNvcmRfc2l6ZaEYSmlwX3ZlcnNpb26hBE1kYXRhYmFzZV90eXBlTkdlb0lQMi1Db3VudHJ5SWxhbmd1YWdlcwEEQmVuW2JpbmFyeV9mb3JtYXRfbWFqb3JfdmVyc2lvbqECW2JpbmFyeV9mb3JtYXRfbWlub3JfdmVyc2lvbqBLZGVzY3JpcHRpb27hQmVuSm5naW54LXRlc3RLYnVpbGRfZXBvY2gEAmp+i28='
));

$t->run();

###############################################################################

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

# t1: known IP -> country code
like(http_get('/t1?ip=1.2.3.1'), qr/\bAU\z/, 'country code');

# t2: unknown IP -> default value
is(body(http_get('/t2?ip=9.9.9.9')), '-', 'unknown ip default');

# t3: nested name lookup
like(http_get('/t3?ip=2.3.4.1'), qr/United States\z/, 'country name');

# t4: metadata build_epoch is a positive integer
like(body(http_get('/t4')), qr/\A\d+\z/, 'metadata build_epoch');

# t5: geoip2_proxy — client is 127.0.0.1 (trusted), XFF carries real IP
like(http("GET /t5 HTTP/1.0\r\nHost: localhost\r\n" .
	"X-Forwarded-For: 1.2.3.1\r\n\r\n"),
	qr/\bAU\z/, 'geoip2_proxy');

###############################################################################
