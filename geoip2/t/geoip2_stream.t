#!/usr/bin/perl

# Tests for ngx_stream_geoip2_module, variable lookup.

###############################################################################

use warnings;
use strict;

use Test::More;
use MIME::Base64;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http stream stream_return/)->plan(1)
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
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    geoip2 %%TESTDIR%%/country.mmdb {
        $geo_stream_cc  default=- country iso_code;
    }

    server {
        listen  127.0.0.1:8081;
        return  $geo_stream_cc;
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

# Client connects from 127.0.0.1, which maps to CN via 127.0.0.0/8
is(stream('127.0.0.1:' . port(8081))->read(), 'CN', 'stream country code');

###############################################################################
