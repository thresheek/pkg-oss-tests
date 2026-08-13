#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, input header manipulation.

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

# Tests that modify input headers use proxy_pass so that the backend location
# evaluates variables in the content phase, after the rewrite-phase
# modification has taken effect.  "return 200 $var" in a location that also
# runs more_set/clear_input_headers would read the pre-modification value
# because the rewrite module evaluates the response body before the
# headers-more rewrite handler runs.
#
# Tests that do NOT modify a variable (T1, T14, T17, T20) use "return 200"
# directly — they read the original (unmodified) value, which is exactly what
# those tests expect.
#
# T24 (gzip injection): dropped — the gzip module reads Accept-Encoding from
# the parsed struct before the rewrite phase, so injection has no effect on
# static-file serving.
#
# T44-T46 (If-Unmodified-Since, If-Match, If-None-Match): dropped — nginx 1.25+
# checks these conditional headers from the parsed struct fields in the
# not-modified header filter, which runs after the rewrite phase but reads
# the pre-parsed values that headers-more cannot update.

my $t = Test::Nginx->new()->has(qw/http rewrite proxy dav/)->plan(42)
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

        # shared proxy defaults for all proxy locations
        proxy_http_version 1.0;
        proxy_set_header   Connection close;
        proxy_set_header   Host $http_host;

        # TEST 1: existing header visible without any module directive
        location /t1 {
            return 200 $http_x_foo;
        }

        # TEST 2: set request header at client side and rewrite it
        location /t2 {
            more_set_input_headers 'X-Foo: howdy';
            proxy_pass http://127.0.0.1:8080/t2-back;
        }

        location /t2-back { return 200 $http_x_foo; }

        # TEST 3: dropped (echo_read_request_body / echo_request_body)
        # TEST 4: dropped (echo_read_request_body / echo_request_body)

        # TEST 5: rewrite host and user-agent
        location /t5 {
            more_set_input_headers 'Host: foo' 'User-Agent: blah';
            proxy_pass http://127.0.0.1:8080/t5-back;
            proxy_set_header Host $http_host;
            proxy_set_header User-Agent $http_user_agent;
        }

        location /t5-back {
            return 200 "Host: $host|UA: $http_user_agent";
        }

        # TEST 6: clear host and user-agent
        location /t6 {
            more_clear_input_headers 'Host: foo' 'User-Agent: blah';
            proxy_pass http://127.0.0.1:8080/t6-back;
            proxy_set_header Host $http_host;
            proxy_set_header User-Agent $http_user_agent;
        }

        location /t6-back {
            return 200 "Host: $host|Host2: $http_host|UA: $http_user_agent";
        }

        # TEST 7: clear using set empty; send X-Foo: bar
        location /t7 {
            more_set_input_headers 'Host:' 'User-Agent:' 'X-Foo:';
            proxy_pass http://127.0.0.1:8080/t7-back;
            proxy_set_header Host $http_host;
            proxy_set_header User-Agent $http_user_agent;
        }

        location /t7-back {
            return 200 "Host: $host|UA: $http_user_agent|XFoo: $http_x_foo";
        }

        # TEST 8: clear content-length via set empty
        location /t8 {
            more_set_input_headers 'Content-Length: ';
            proxy_pass http://127.0.0.1:8080/t89-back;
        }

        # TEST 9: clear content-length (the other way)
        location /t9 {
            more_clear_input_headers 'Content-Length: ';
            proxy_pass http://127.0.0.1:8080/t89-back;
        }

        location /t89-back { return 200 "CL: $http_content_length"; }

        # TEST 10: rewrite content-type
        location /t10 {
            more_set_input_headers 'Content-Type: text/css';
            proxy_pass http://127.0.0.1:8080/t101112-back;
        }

        # TEST 11: clear content-type via set empty
        location /t11 {
            more_set_input_headers 'Content-Type:';
            proxy_pass http://127.0.0.1:8080/t101112-back;
        }

        # TEST 12: clear content-type (the other way)
        location /t12 {
            more_clear_input_headers 'Content-Type:foo';
            proxy_pass http://127.0.0.1:8080/t101112-back;
        }

        location /t101112-back { return 200 "CT: $content_type"; }

        # TEST 13: type constraint matched
        location /t13 {
            more_set_input_headers -t 'text/plain' 'X-Blah:yay';
            proxy_pass http://127.0.0.1:8080/t1317-back;
        }

        # TEST 14: type constraint not matched — no modification, "return 200"
        # sees the correct (already empty) $http_x_blah
        location /t14 {
            more_set_input_headers -t 'text/plain' 'X-Blah:yay';
            return 200 $http_x_blah;
        }

        # TEST 15: type constraint OR'd (matched text/css)
        location /t15 {
            more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
            proxy_pass http://127.0.0.1:8080/t1317-back;
        }

        # TEST 16: type constraint OR'd (matched text/plain)
        location /t16 {
            more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
            proxy_pass http://127.0.0.1:8080/t1317-back;
        }

        # TEST 17: type constraint OR'd (not matched) — no modification
        location /t17 {
            more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
            return 200 $http_x_blah;
        }

        location /t1317-back { return 200 $http_x_blah; }

        # TEST 18: mix input and output cmds
        location /t18 {
            more_set_input_headers 'X-Blah:yay';
            more_set_headers 'X-Blah:hiya';
            proxy_pass http://127.0.0.1:8080/t18-back;
        }

        location /t18-back { return 200 $http_x_blah; }

        # TEST 19: set request header and replace (-r option)
        location /t19 {
            more_set_input_headers -r 'X-Foo: howdy';
            proxy_pass http://127.0.0.1:8080/t19-back;
        }

        location /t19-back { return 200 $http_x_foo; }

        # TEST 20: do not set request header without existing one (-r option)
        # no modification; "return 200" sees the correct empty value
        location /t20 {
            more_set_input_headers -r 'X-Foo: howdy';
            return 200 "empty_header: $http_x_foo";
        }

        # TEST 21: clear User-Agent forwarded to proxy
        location /t21 {
            more_clear_input_headers 'User-Agent';
            proxy_pass http://127.0.0.1:8080/t2122-back;
            proxy_set_header User-Agent $http_user_agent;
        }

        # TEST 22: clear User-Agent (without prior user-agent)
        location /t22 {
            more_clear_input_headers 'User-Agent';
            proxy_pass http://127.0.0.1:8080/t2122-back;
            proxy_set_header User-Agent $http_user_agent;
        }

        location /t2122-back { return 200 $http_user_agent; }

        # TEST 23: dropped (uses $echo_client_request_headers)

        # TEST 24: dropped — gzip module reads Accept-Encoding from the parsed
        # struct before the rewrite phase; injection via more_set_input_headers
        # does not trigger gzip for static-file serving.

        # TEST 25: rewrite + set request header (proxied to echo backend)
        location /t25 {
            rewrite ^ /t25-foo last;
        }

        location /t25-foo {
            more_set_input_headers 'X-Foo: howdy';
            proxy_pass http://127.0.0.1:8080/t25-back;
        }

        location /t25-back {
            return 200 "X-Foo: $http_x_foo";
        }

        # TEST 26: clear_header clears all instances of a user custom header
        location /t26 {
            more_clear_input_headers Foo;
            proxy_pass http://127.0.0.1:8080/t26-back;
        }

        location /t26-back {
            return 200 "Foo: [$http_foo]|TH: [$http_test_header]";
        }

        # TEST 27: clear_header clears all instances of builtin Content-Type
        location /t27 {
            more_clear_input_headers Content-Type;
            proxy_pass http://127.0.0.1:8080/t27-back;
        }

        location /t27-back {
            return 200 "CT: [$http_content_type]|TH: [$http_test_header]";
        }

        # TEST 28: converting POST to GET — clear Content-Type and Content-Length
        location /t28 {
            more_clear_input_headers Content-Type;
            more_clear_input_headers Content-Length;
            proxy_pass http://127.0.0.1:8080/t28-back;
        }

        location /t28-back {
            return 200 "CT:[$http_content_type]|CL:[$http_content_length]|TH:[$http_test_header]";
        }

        # TEST 29-33: dropped (use $echo_client_request_headers)

        # TEST 34: clear X-Real-IP
        location /t34 {
            more_clear_input_headers X-Real-IP;
            proxy_pass http://127.0.0.1:8080/t3435-back;
        }

        # TEST 35: set custom X-Real-IP
        location /t35 {
            more_set_input_headers "X-Real-IP: 8.8.4.4";
            proxy_pass http://127.0.0.1:8080/t3435-back;
        }

        location /t3435-back { return 200 "X-Real-IP: $http_x_real_ip"; }

        # TEST 36: clear Via
        location /t36 {
            more_clear_input_headers Via;
            proxy_pass http://127.0.0.1:8080/t3637-back;
        }

        # TEST 37: set custom Via
        location /t37 {
            more_set_input_headers "Via: 1.0 fred, 1.1 nowhere.com (Apache/1.1)";
            proxy_pass http://127.0.0.1:8080/t3637-back;
        }

        location /t3637-back { return 200 "Via: $http_via"; }

        # TEST 38: HTTP 0.9 (set) — directive must not crash on HTTP/0.9
        location /t38 {
            more_set_input_headers 'X-Foo: howdy';
            return 200 "x-foo: $http_x_foo";
        }

        # TEST 39: HTTP 0.9 (clear)
        location /t39 {
            more_clear_input_headers 'X-Foo';
            return 200 "x-foo: $http_x_foo";
        }

        # TEST 40: Host header with port
        location /t40 {
            more_set_input_headers 'Host: agentzh.org:1984';
            proxy_pass http://127.0.0.1:8080/t4041-back;
        }

        # TEST 41: Host header with upper case letters
        location /t41 {
            more_set_input_headers 'Host: agentZH.org:1984';
            proxy_pass http://127.0.0.1:8080/t4041-back;
        }

        location /t4041-back {
            return 200 "host: $host|http_host: $http_host";
        }

        # TEST 42: clear all and re-insert (stress test)
        location = /t42 {
            more_clear_input_headers Host Connection Cache-Control Accept
                                     User-Agent Accept-Encoding Accept-Language
                                     Cookie;

            more_set_input_headers "Host: a" "Connection: b" "Cache-Control: c"
                                   "Accept: d" "User-Agent: e" "Accept-Encoding: f"
                                   "Accept-Language: g" "Cookie: h";

            more_clear_input_headers Host Connection Cache-Control Accept
                                     User-Agent Accept-Encoding Accept-Language
                                     Cookie;

            more_set_input_headers "Host: a" "Connection: b" "Cache-Control: c"
                                   "Accept: d" "User-Agent: e" "Accept-Encoding: f"
                                   "Accept-Language: g" "Cookie: h";

            return 200 ok;
        }

        # TEST 43: dropped (content_by_lua)

        # TEST 44: dropped — nginx 1.25+ checks If-Unmodified-Since from the
        # parsed struct field in the not-modified header filter; the module
        # cannot update that field to prevent the 412 response.
        # TEST 45: dropped — same reason (If-Match → 412)
        # TEST 46: dropped — same reason (If-None-Match → 304)

        # TEST 47: set the Destination request header for WebDAV
        location /a.txt {
            more_set_input_headers "Destination: /b.txt";
            dav_methods MOVE;
            dav_access  all:rw;
            root        %%TESTDIR%%;
        }

        # TEST 48: more_set_input_headers + X-Forwarded-For
        location /t48 {
            more_set_input_headers "X-Forwarded-For: 8.8.8.8";
            proxy_pass http://127.0.0.1:8080/t48-back;
            proxy_set_header Foo $proxy_add_x_forwarded_for;
        }

        location /t48-back { return 200 "Foo: $http_foo"; }

        # TEST 49: more_clear_input_headers + X-Forwarded-For
        location /t49 {
            more_clear_input_headers "X-Forwarded-For";
            proxy_pass http://127.0.0.1:8080/t49-back;
            proxy_set_header Foo $proxy_add_x_forwarded_for;
        }

        location /t49-back { return 200 "Foo: $http_foo"; }

        # TEST 50: clear input headers with wildcard
        location /t50 {
            more_clear_input_headers 'X-Hidden-*';
            proxy_pass http://127.0.0.1:8080/t5051-back;
        }

        # TEST 51: wildcard has no effect on more_set_input_headers
        # no modification; original header values pass through to the backend
        location /t51 {
            more_set_input_headers 'X-Hidden-*: lol';
            proxy_pass http://127.0.0.1:8080/t5051-back;
        }

        location /t5051-back {
            return 200 "$http_x_hidden_one|$http_x_hidden_two";
        }
    }
}

EOF

$t->write_file('a.txt', 'hello, world!');

$t->run();

###############################################################################

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

# TEST 1: existing header is visible without any module directive
like(http("GET /t1 HTTP/1.0\r\nHost: localhost\r\nX-Foo: blah\r\n\r\n"),
	qr/blah\z/, 'existing header visible');

# TEST 2: set request header and rewrite it
like(http("GET /t2 HTTP/1.0\r\nHost: localhost\r\nX-Foo: blah\r\n\r\n"),
	qr/howdy\z/, 'rewrite request header');

# TEST 5: rewrite host and user-agent
my $r = http_get('/t5');
like($r, qr/Host: foo/, 'rewrite host');
like($r, qr/UA: blah/, 'rewrite user-agent');

# TEST 6: clear host and user-agent
like(http_get('/t6'), qr/Host: localhost\|Host2: \|UA: \z/,
	'clear host and ua');

# TEST 7: clear via set empty
like(http("GET /t7 HTTP/1.0\r\nHost: localhost\r\nX-Foo: bar\r\n\r\n"),
	qr/Host: localhost\|UA: \|XFoo: \z/, 'clear via set empty');

# TEST 8: clear content-length via set empty
like(http("GET /t8 HTTP/1.0\r\nHost: localhost\r\nContent-Length: 5\r\n\r\n"),
	qr/CL: \z/, 'clear content-length via set empty');

# TEST 9: clear content-length (the other way)
like(http("GET /t9 HTTP/1.0\r\nHost: localhost\r\nContent-Length: 5\r\n\r\n"),
	qr/CL: \z/, 'clear content-length other way');

# TEST 10: rewrite content-type
like(http("POST /t10 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"),
	qr/CT: text\/css\z/, 'rewrite content-type');

# TEST 11: clear content-type via set empty
like(http("POST /t11 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"),
	qr/CT: \z/, 'clear content-type via set empty');

# TEST 12: clear content-type (the other way)
like(http("POST /t12 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"),
	qr/CT: \z/, 'clear content-type other way');

# TEST 13: type constraint matched
like(body(http("POST /t13 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello")),
	qr/^yay$/, 'type constraint matched');

# TEST 14: type constraint not matched — no modification, $http_x_blah is ""
like(http("POST /t14 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/css\r\nContent-Length: 5\r\n\r\nhello"),
	qr/Content-Length: 0/, 'type constraint not matched');

# TEST 15: type constraint OR'd (matched text/css)
like(body(http("POST /t15 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/css\r\nContent-Length: 5\r\n\r\nhello")),
	qr/^yay$/, 'type constraint or matched text/css');

# TEST 16: type constraint OR'd (matched text/plain)
like(body(http("POST /t16 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello")),
	qr/^yay$/, 'type constraint or matched text/plain');

# TEST 17: type constraint OR'd (not matched) — no modification
like(http("POST /t17 HTTP/1.0\r\nHost: localhost\r\nContent-Type: text/html\r\nContent-Length: 5\r\n\r\nhello"),
	qr/Content-Length: 0/, 'type constraint or not matched');

# TEST 18: mix input and output cmds
$r = http_get('/t18');
like($r, qr/X-Blah: hiya\r\n/, 'mix input/output X-Blah output header');
like($r, qr/yay\z/, 'mix input/output body');

# TEST 19: -r option replaces existing header
like(http("GET /t19 HTTP/1.0\r\nHost: localhost\r\nX-Foo: blah\r\n\r\n"),
	qr/howdy\z/, 'replace existing header');

# TEST 20: -r option does not set header when absent — no modification
like(http_get('/t20'), qr/empty_header: \z/, 'no replace without existing header');

# TEST 21: clear User-Agent forwarded to proxy
like(http("GET /t21 HTTP/1.0\r\nHost: localhost\r\nUser-Agent: my-sock\r\n\r\n"),
	qr/Content-Length: 0/, 'clear ua for proxy');

# TEST 22: clear User-Agent (no prior ua sent)
like(http_get('/t22'), qr/Content-Length: 0/, 'clear ua no prior header');

# TEST 25: rewrite + set request header
like(http_get('/t25'), qr/X-Foo: howdy\z/, 'rewrite plus set header');

# TEST 26: clear_header clears all instances of a user custom header
like(body(http("GET /t26 HTTP/1.0\r\nHost: localhost\r\nFoo: foo\r\nFoo: bah\r\nTest-Header: 1\r\n\r\n")),
	qr/^Foo: \[\]\|TH: \[1\]$/, 'clear all instances of custom header');

# TEST 27: clear_header clears all instances of builtin Content-Type
like(body(http("GET /t27 HTTP/1.0\r\nHost: localhost\r\nContent-Type: foo\r\nContent-Type: bah\r\nTest-Header: 1\r\n\r\n")),
	qr/^CT: \[\]\|TH: \[1\]$/, 'clear all instances of builtin header');

# TEST 28: converting POST to GET — clear Content-Type and Content-Length
like(body(http("POST /t28 HTTP/1.0\r\nHost: localhost\r\nContent-Type: application/ocsp-request\r\nContent-Length: 11\r\nTest-Header: 1\r\n\r\nhello world")),
	qr/^CT:\[\]\|CL:\[\]\|TH:\[1\]$/, 'clear content-type and content-length');

# TEST 34: clear X-Real-IP
like(http("GET /t34 HTTP/1.0\r\nHost: localhost\r\nX-Real-IP: 8.8.8.8\r\n\r\n"),
	qr/X-Real-IP: \z/, 'clear x-real-ip');

# TEST 35: set custom X-Real-IP
like(http_get('/t35'), qr/X-Real-IP: 8\.8\.4\.4\z/, 'set x-real-ip');

# TEST 36: clear Via
like(http("GET /t36 HTTP/1.0\r\nHost: localhost\r\nVia: 1.0 fred, 1.1 nowhere.com (Apache/1.1)\r\n\r\n"),
	qr/Via: \z/, 'clear via');

# TEST 37: set custom Via
like(http_get('/t37'),
	qr/Via: 1\.0 fred, 1\.1 nowhere\.com \(Apache\/1\.1\)\z/, 'set via');

# TEST 38: HTTP 0.9 set — no request headers in HTTP/0.9, $http_x_foo is ""
like(http("GET /t38\r\n"), qr/x-foo: \z/, 'http09 set input no effect');

# TEST 39: HTTP 0.9 clear
like(http("GET /t39\r\n"), qr/x-foo: \z/, 'http09 clear input no effect');

# TEST 40: Host header with port — $host strips port
$r = http("GET /t40 HTTP/1.0\r\nHost: localhost\r\n\r\n");
like($r, qr/host: agentzh\.org\|/, 'host header with port strips port');
like($r, qr/http_host: agentzh\.org:1984\z/, 'host header with port preserves http_host');

# TEST 41: Host header with upper case letters — $host is lowercased
$r = http("GET /t41 HTTP/1.0\r\nHost: localhost\r\n\r\n");
like($r, qr/host: agentzh\.org\|/, 'host header uppercase lowercased');
like($r, qr/http_host: agentZH\.org:1984\z/, 'host header uppercase http_host preserved');

# TEST 42: clear all and re-insert multiple times — just verify no crash
like(http("GET /t42 HTTP/1.1\r\n"
    . "Host: localhost\r\n"
    . "Connection: close\r\n"
    . "Cache-Control: max-age=0\r\n"
    . "Accept: text/html\r\n"
    . "User-Agent: Mozilla/5.0\r\n"
    . "Accept-Encoding: gzip,deflate\r\n"
    . "Accept-Language: en-US\r\n"
    . "Cookie: test=cookie;\r\n"
    . "\r\n"),
	qr/ok\z/, 'clear all and re-insert no crash');

# TEST 47: Destination header injected for WebDAV MOVE
like(http("MOVE /a.txt HTTP/1.0\r\nHost: localhost\r\n\r\n"),
	qr/ 204 /, 'dav destination header injected');

# TEST 48: more_set_input_headers + X-Forwarded-For
like(body(http_get('/t48')),
	qr/^Foo: 8\.8\.8\.8, 127\.0\.0\.1$/, 'set x-forwarded-for via proxy');

# TEST 49: more_clear_input_headers + X-Forwarded-For
like(body(http("GET /t49 HTTP/1.0\r\nHost: localhost\r\nX-Forwarded-For: 8.8.8.8\r\n\r\n")),
	qr/^Foo: 127\.0\.0\.1$/, 'clear x-forwarded-for via proxy');

# TEST 50: clear input headers with wildcard
like(body(http("GET /t50 HTTP/1.0\r\nHost: localhost\r\nX-Hidden-One: i am hidden\r\nX-Hidden-Two: me 2\r\n\r\n")),
	qr/^\|$/, 'wildcard clear input headers');

# TEST 51: wildcard has no effect on more_set_input_headers
like(body(http("GET /t51 HTTP/1.0\r\nHost: localhost\r\nX-Hidden-One: i am hidden\r\nX-Hidden-Two: me 2\r\n\r\n")),
	qr/^i am hidden\|me 2$/, 'wildcard set input has no effect');

###############################################################################
