#!/usr/bin/perl

# Tests for ngx_http_geoip2_module, geoip2_proxy_recursive.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geoip2 %%TESTDIR%%/country.mmdb {
        $geo_country_code  default=- country iso_code;
    }

    geoip2_proxy           127.0.0.0/8;
    geoip2_proxy_recursive on;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t6 { return 200 $geo_country_code; }
        location /t7 { return 200 $geo_country_code; }
    }
}

EOF

# Same mmdb as geoip2.t:
#   1.2.3.0/24  -> AU,  2.3.4.0/24  -> US,  127.0.0.0/8 -> CN
$t->write_file('country.mmdb', decode_base64(
	'AAABAAAvAAACAAApAAADAAAvAAAEAAAvAAAFAAAvAAAGAAAvAAAHAAAYAAAvAAAIAAAJAAAvAAAKAAAvAAALAAAvAAAMAAAvAAANAAAvAAAOAAAvAAAvAAAPAAAQAAAvAAARAAAvAAASAAAvAAATAAAvAAAUAAAvAAAVAAAvAAAWAAAvAAAvAAAXAAAvAAB0AAAZAAAvAAAaAAAvAAAbAAAvAAAcAAAvAAAdAAAvAAAeAAAvAAAfAAAvAAAvAAAgAAAvAAAhAAAiAAAvAAAjAAAvAAAkAAAvAAAlAAAvAAAmAAAvAAAvAAAnAAAoAAAvAACYAAAvAAAvAAAqAAAvAAArAAAvAAAsAAAvAAAtAAAvAAAuAAAvAAC0AAAAAAAAAAAAAAAAAAAAAEdjb3VudHJ5SGlzb19jb2RlQkFVRW5hbWVzQmVuSUF1c3RyYWxpYeEgGiAd4iAIIBEgFCAn4SAAICxCVVNNVW5pdGVkIFN0YXRlc+EgGiA94iAIIDogFCBL4SAAIFBCQ05FQ2hpbmHhIBogYeIgCCBeIBQgZ+EgACBsq83vTWF4TWluZC5jb23pSm5vZGVfY291bnTBL0tyZWNvcmRfc2l6ZaEYSmlwX3ZlcnNpb26hBE1kYXRhYmFzZV90eXBlTkdlb0lQMi1Db3VudHJ5SWxhbmd1YWdlcwEEQmVuW2JpbmFyeV9mb3JtYXRfbWFqb3JfdmVyc2lvbqECW2JpbmFyeV9mb3JtYXRfbWlub3JfdmVyc2lvbqBLZGVzY3JpcHRpb27hQmVuSm5naW54LXRlc3RLYnVpbGRfZXBvY2gEAmp+i28='
));

$t->run();

###############################################################################

# t6: XFF chain has a non-trusted IP first; recursive skips trusted 127.0.0.2
#     and resolves 1.2.3.1 -> AU
like(http("GET /t6 HTTP/1.0\r\nHost: localhost\r\n" .
	"X-Forwarded-For: 1.2.3.1, 127.0.0.2\r\n\r\n"),
	qr/\bAU\z/, 'recursive skips trusted, uses non-trusted');

# t7: entire XFF chain is trusted (127.0.0.2 in 127.0.0.0/8); recursive
#     exhausts the chain and falls back to $remote_addr (127.0.0.1) -> CN
like(http("GET /t7 HTTP/1.0\r\nHost: localhost\r\n" .
	"X-Forwarded-For: 127.0.0.2\r\n\r\n"),
	qr/\bCN\z/, 'recursive exhausts chain, falls back to remote_addr');

###############################################################################
