#!/usr/bin/perl

# Tests for ngx_http_headers_more_filter_module, output header set and clear.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(83)
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

        # server-level directives for tests 27-30; fire on 404 + text/html
        more_set_headers -s 404 -t 'text/html' 'X-status2: howdy3';
        more_set_headers -s 404 -t 'text/html' 'X-status: yeah';

        # TEST 1: simple set (1 arg)
        location /t1 {
            more_set_headers 'X-Foo: Blah';
            return 200 hi;
        }

        # TEST 2: simple set (2 args)
        location /t2 {
            more_set_headers 'X-Foo: Blah' 'X-Bar: hi';
            return 200 hi;
        }

        # TEST 3: two sets in a single location
        location /t3 {
            more_set_headers 'X-Foo: Blah';
            more_set_headers 'X-Bar: hi';
            return 200 hi;
        }

        # TEST 4: two sets in a single location (for 404 too)
        location /t4 {
            more_set_headers 'X-Foo: Blah';
            more_set_headers 'X-Bar: hi';
            return 404;
        }

        # TEST 5: set a header then clear it (500)
        location /t5 {
            more_set_headers 'X-Foo: Blah';
            more_set_headers 'X-Foo:';
            return 500;
        }

        # TEST 6: set a header only when 500 (matched)
        location /t6 {
            more_set_headers -s 500 'X-Mine: Hiya';
            more_set_headers -s 404 'X-Yours: Blah';
            return 500;
        }

        # TEST 7: set a header only when 500 (not matched with 200)
        location /t7 {
            more_set_headers -s 500 'X-Mine: Hiya';
            more_set_headers -s 404 'X-Yours: Blah';
            return 200 hello;
        }

        # TEST 8: set a header only when 500 (not matched with 404)
        location /t8 {
            more_set_headers -s 500 'X-Mine: Hiya';
            more_set_headers -s 404 'X-Yours: Blah';
            return 404;
        }

        # TEST 9: more conditions (503)
        location /t9 {
            more_set_headers -s '503 404' 'X-Mine: Hiya';
            more_set_headers -s ' 404  413 ' 'X-Yours: Blah';
            return 503;
        }

        # TEST 10: more conditions (404)
        location /t10 {
            more_set_headers -s '503 404' 'X-Mine: Hiya';
            more_set_headers -s ' 404   413 ' 'X-Yours: Blah';
            return 404;
        }

        # TEST 11: more conditions (413)
        location /t11 {
            more_set_headers -s '503 404' 'X-Mine: Hiya';
            more_set_headers -s ' 404   413  ' 'X-Yours: Blah';
            return 413;
        }

        # TEST 12: simple -t (matched)
        location /t12 {
            default_type 'text/css';
            more_set_headers -t 'text/css' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 13: simple -t (not matched)
        location /t13 {
            default_type 'text/plain';
            more_set_headers -t 'text/css' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 14: multiple -t (not matched)
        location /t14 {
            default_type 'text/plain';
            more_set_headers -t 'text/javascript' -t 'text/css' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 15: multiple -t (matched text/plain)
        location /t15 {
            default_type 'text/plain';
            more_set_headers -t 'text/javascript' -t 'text/plain' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 16: multiple -t (matched text/javascript)
        location /t16 {
            default_type 'text/javascript';
            more_set_headers -t 'text/javascript' -t 'text/plain' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 17: multiple -t (matched) with extra spaces
        location /t17 {
            default_type 'text/javascript';
            more_set_headers -t ' text/javascript  ' -t 'text/plain' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 18: multiple -t merged
        location /t18 {
            default_type 'text/javascript';
            more_set_headers -t ' text/javascript  text/plain' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 19: multiple -t merged (2)
        location /t19 {
            default_type 'text/plain';
            more_set_headers -t ' text/javascript  text/plain' 'X-CSS: yes';
            return 200 hi;
        }

        # TEST 20: multiple -s option in a directive (not matched with 200)
        location /t20 {
            more_set_headers -s 404 -s 500 'X-status: howdy';
            return 200 hi;
        }

        # TEST 21: multiple -s option in a directive (matched 404)
        # location-level X-status: howdy overrides server-level X-status: yeah
        location /t21 {
            more_set_headers -s 404 -s 500 'X-status: howdy';
            return 404;
        }

        # TEST 22: multiple -s option in a directive (matched 500)
        location /t22 {
            more_set_headers -s 404 -s 500 'X-status: howdy';
            return 500;
        }

        # TEST 23: -s mixed with -t (matched 404 + text/html)
        # more_clear_headers cancels server-level X-status: yeah so the
        # location's conditional set is the only one visible
        location /t23 {
            default_type 'text/html';
            more_clear_headers 'X-status';
            more_set_headers -s 404 -s 200 -t 'text/html' 'X-status: howdy2';
            return 404;
        }

        # TEST 24: -s mixed with -t (not matched — type mismatch)
        location /t24 {
            default_type 'text/html';
            more_clear_headers 'X-status';
            more_set_headers -s 404 -s 200 -t 'text/plain' 'X-status: howdy2';
            return 404;
        }

        # TEST 25: -s mixed with -t (matched 200 + text/html)
        location /t25 {
            default_type 'text/html';
            more_clear_headers 'X-status';
            more_set_headers -s 404 -s 200 -t 'text/html' 'X-status: howdy2';
            return 200 hi;
        }

        # TEST 26: -s mixed with -t (not matched — status mismatch)
        location /t26 {
            default_type 'text/html';
            more_clear_headers 'X-status';
            more_set_headers -s 500 -s 200 -t 'text/html' 'X-status: howdy2';
            return 404;
        }

        # TEST 27: merge from the upper level (server-level X-status2 fires)
        # server-level X-status: yeah also fires for this 404 response, which
        # is accepted — we do not assert !X-status here to avoid the conflict
        location /t27 {
            default_type 'text/html';
            more_set_headers -s 500 -s 200 -t 'text/html' 'X-status: howdy2';
            return 404;
        }

        # TEST 28: server-level (404-only) does not fire; location fires for 200
        location /t28 {
            default_type 'text/html';
            more_set_headers -s 500 -s 200 -t 'text/html' 'X-status: howdy2';
            return 200 yeah;
        }

        # TEST 29: location-level X-status: nope overrides server-level X-status: yeah
        location /t29 {
            default_type 'text/html';
            more_set_headers -s 404 -t 'text/html' 'X-status: nope';
            return 404;
        }

        # TEST 30: location X-status2: nope overrides server X-status2: howdy3;
        # server-level X-status: yeah also fires and is preserved
        location /t30 {
            default_type 'text/html';
            more_set_headers -s 404 -t 'text/html' 'X-status2: nope';
            return 404;
        }

        # TEST 31: clear headers with wildcard
        location = /t31-back {
            add_header X-Hidden-One "i am hidden";
            add_header X-Hidden-Two "me 2";
            return 200 hi;
        }

        location /t31 {
            more_clear_headers 'X-Hidden-*';
            proxy_pass http://127.0.0.1:8080/t31-back;
        }

        # TEST 32: clear duplicate headers
        location = /t32-back {
            add_header pragma no-cache;
            add_header pragma no-cache;
            return 200 hi;
        }

        location /t32 {
            more_clear_headers 'pragma';
            proxy_pass http://127.0.0.1:8080/t32-back;
        }

        # TEST 33: HTTP 0.9 (set) — module must not crash; no response headers
        location /t33 {
            more_set_headers 'X-Foo: howdy';
            return 200 ok;
        }

        # TEST 34: use the -a option to append a Set-Cookie field
        location /t34 {
            more_set_headers -a 'Set-Cookie: name=lynch';
            return 200 ok;
        }

        # TEST 35: original Set-Cookie is preserved when using -a
        location /t35 {
            more_set_headers 'Set-Cookie: name=lynch';
            more_set_headers -a 'Set-Cookie: born=1981';
            return 200 ok;
        }

        # TEST 36: dropped (--- must_die: -a on builtin Server header)
        # TEST 37: dropped (--- must_die: -a on more_clear_headers)
    }
}

EOF

$t->run();

###############################################################################

my $r;

# TEST 1: simple set (1 arg)
$r = http_get('/t1');
like($r, qr/X-Foo: Blah\r\n/, 'simple set header');
like($r, qr/hi\z/, 'simple set body');

# TEST 2: simple set (2 args)
$r = http_get('/t2');
like($r, qr/X-Foo: Blah\r\n/, 'simple set 2 args X-Foo');
like($r, qr/X-Bar: hi\r\n/, 'simple set 2 args X-Bar');
like($r, qr/hi\z/, 'simple set 2 args body');

# TEST 3: two sets in a single location
$r = http_get('/t3');
like($r, qr/X-Foo: Blah\r\n/, 'two sets X-Foo');
like($r, qr/X-Bar: hi\r\n/, 'two sets X-Bar');
like($r, qr/hi\z/, 'two sets body');

# TEST 4: two sets (for 404 too)
$r = http_get('/t4');
like($r, qr/X-Foo: Blah\r\n/, 'set on 404 X-Foo');
like($r, qr/X-Bar: hi\r\n/, 'set on 404 X-Bar');
like($r, qr/ 404 /, 'set on 404 status');

# TEST 5: set a header then clear it (500)
$r = http_get('/t5');
unlike($r, qr/X-Foo:/, 'set then clear X-Foo absent');
unlike($r, qr/X-Bar:/, 'set then clear X-Bar absent');
like($r, qr/ 500 /, 'set then clear status');

# TEST 6: set a header only when 500 (matched)
$r = http_get('/t6');
like($r, qr/X-Mine: Hiya\r\n/, 'status 500 matched X-Mine');
unlike($r, qr/X-Yours:/, 'status 500 not 404 X-Yours absent');
like($r, qr/ 500 /, 'status 500 matched status');

# TEST 7: set a header only when 500 (not matched with 200)
$r = http_get('/t7');
unlike($r, qr/X-Mine:/, 'status 200 not 500 X-Mine absent');
unlike($r, qr/X-Yours:/, 'status 200 not 404 X-Yours absent');
like($r, qr/hello\z/, 'status 200 body');

# TEST 8: set a header only when 500 (not matched with 404)
$r = http_get('/t8');
unlike($r, qr/X-Mine:/, 'status 404 not 500 X-Mine absent');
like($r, qr/X-Yours: Blah\r\n/, 'status 404 matched X-Yours');
like($r, qr/ 404 /, 'status 404 matched status');

# TEST 9: more conditions (503)
$r = http_get('/t9');
like($r, qr/X-Mine: Hiya\r\n/, 'multi status 503 X-Mine');
unlike($r, qr/X-Yours:/, 'multi status 503 not 404/413 X-Yours absent');
like($r, qr/ 503 /, 'multi status 503 status');

# TEST 10: more conditions (404)
$r = http_get('/t10');
like($r, qr/X-Mine: Hiya\r\n/, 'multi status 404 X-Mine');
like($r, qr/X-Yours: Blah\r\n/, 'multi status 404 X-Yours');
like($r, qr/ 404 /, 'multi status 404 status');

# TEST 11: more conditions (413)
$r = http_get('/t11');
unlike($r, qr/X-Mine:/, 'multi status 413 not 503/404 X-Mine absent');
like($r, qr/X-Yours: Blah\r\n/, 'multi status 413 X-Yours');
like($r, qr/ 413 /, 'multi status 413 status');

# TEST 12: simple -t (matched)
$r = http_get('/t12');
like($r, qr/X-CSS: yes\r\n/, 'type filter matched X-CSS');
like($r, qr/hi\z/, 'type filter matched body');

# TEST 13: simple -t (not matched)
$r = http_get('/t13');
unlike($r, qr/X-CSS:/, 'type filter not matched X-CSS absent');
like($r, qr/hi\z/, 'type filter not matched body');

# TEST 14: multiple -t (not matched)
$r = http_get('/t14');
unlike($r, qr/X-CSS:/, 'multi type filter not matched X-CSS absent');
like($r, qr/hi\z/, 'multi type filter not matched body');

# TEST 15: multiple -t (matched text/plain)
$r = http_get('/t15');
like($r, qr/X-CSS: yes\r\n/, 'multi type filter matched text/plain');
like($r, qr/hi\z/, 'multi type filter matched text/plain body');

# TEST 16: multiple -t (matched text/javascript)
$r = http_get('/t16');
like($r, qr/X-CSS: yes\r\n/, 'multi type filter matched text/javascript');
like($r, qr/hi\z/, 'multi type filter matched text/javascript body');

# TEST 17: multiple -t (matched) with extra spaces
$r = http_get('/t17');
like($r, qr/X-CSS: yes\r\n/, 'type filter extra spaces matched');
like($r, qr/hi\z/, 'type filter extra spaces body');

# TEST 18: multiple -t merged
$r = http_get('/t18');
like($r, qr/X-CSS: yes\r\n/, 'type filter merged matched');
like($r, qr/hi\z/, 'type filter merged body');

# TEST 19: multiple -t merged (2)
$r = http_get('/t19');
like($r, qr/X-CSS: yes\r\n/, 'type filter merged 2 matched');
like($r, qr/hi\z/, 'type filter merged 2 body');

# TEST 20: multiple -s option in a directive (not matched with 200)
$r = http_get('/t20');
unlike($r, qr/X-status: howdy/, 'multi -s not matched 200 X-status absent');
like($r, qr/hi\z/, 'multi -s not matched 200 body');

# TEST 21: multiple -s option in a directive (matched 404)
$r = http_get('/t21');
like($r, qr/X-status: howdy\r\n/, 'multi -s matched 404 X-status');
like($r, qr/ 404 /, 'multi -s matched 404 status');

# TEST 22: multiple -s option in a directive (matched 500)
$r = http_get('/t22');
like($r, qr/X-status: howdy\r\n/, 'multi -s matched 500 X-status');
like($r, qr/ 500 /, 'multi -s matched 500 status');

# TEST 23: -s mixed with -t (matched 404 + text/html)
$r = http_get('/t23');
like($r, qr/X-status: howdy2\r\n/, '-s and -t matched X-status');
like($r, qr/ 404 /, '-s and -t matched status');

# TEST 24: -s mixed with -t (not matched — type mismatch)
$r = http_get('/t24');
unlike($r, qr/X-status:/, '-s and -t type mismatch X-status absent');
like($r, qr/ 404 /, '-s and -t type mismatch status');

# TEST 25: -s mixed with -t (matched 200 + text/html)
$r = http_get('/t25');
like($r, qr/X-status: howdy2\r\n/, '-s and -t matched 200 X-status');
like($r, qr/hi\z/, '-s and -t matched 200 body');

# TEST 26: -s mixed with -t (not matched — status mismatch)
$r = http_get('/t26');
unlike($r, qr/X-status: howdy/, '-s and -t status mismatch X-status absent');
like($r, qr/ 404 /, '-s and -t status mismatch status');

# TEST 27: merge from upper level (server-level X-status2 fires)
# X-status: yeah also fires from server-level — see config comment
$r = http_get('/t27');
like($r, qr/X-status2: howdy3\r\n/, 'server-level X-status2 fires');
like($r, qr/ 404 /, 'server-level merge status');

# TEST 28: server-level (404-only) does not fire for 200
$r = http_get('/t28');
unlike($r, qr/X-status2:/, 'server-level 404-only absent for 200');
like($r, qr/X-status: howdy2\r\n/, 'location-level fires for 200');
like($r, qr/yeah\z/, 'server-level absent for 200 body');

# TEST 29: location-level overrides server-level (same header)
$r = http_get('/t29');
like($r, qr/X-status: nope\r\n/, 'location overrides server X-status');
like($r, qr/ 404 /, 'location overrides server status');

# TEST 30: append settings by inheritance (different header)
$r = http_get('/t30');
like($r, qr/X-status: yeah\r\n/, 'append inheritance server X-status');
like($r, qr/X-status2: nope\r\n/, 'append inheritance location X-status2');
like($r, qr/ 404 /, 'append inheritance status');

# TEST 31: clear headers with wildcard
$r = http_get('/t31');
unlike($r, qr/X-Hidden-One:/, 'wildcard clear X-Hidden-One absent');
unlike($r, qr/X-Hidden-Two:/, 'wildcard clear X-Hidden-Two absent');
like($r, qr/hi\z/, 'wildcard clear body');

# TEST 32: clear duplicate headers
$r = http_get('/t32');
unlike($r, qr/pragma:/, 'clear duplicate pragma absent');
like($r, qr/hi\z/, 'clear duplicate body');

# TEST 33: HTTP 0.9 — no response headers at all, body returned directly
$r = http("GET /t33\r\n");
unlike($r, qr/X-Foo:/, 'http09 no X-Foo header');
like($r, qr/ok/, 'http09 body ok');

# TEST 34: -a option appends Set-Cookie
$r = http_get('/t34');
like($r, qr/Set-Cookie: name=lynch\r\n/, '-a option set-cookie');
like($r, qr/ok\z/, '-a option body');

# TEST 35: -a preserves existing Set-Cookie, appends new one
$r = http_get('/t35');
like($r, qr/Set-Cookie: name=lynch\r\nSet-Cookie: born=1981\r\n/, '-a preserves order');
like($r, qr/ok\z/, '-a preserves order body');

###############################################################################
