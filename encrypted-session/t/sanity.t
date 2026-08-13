#!/usr/bin/perl

# Tests for ngx_http_encrypted_session_module, encrypt and decrypt.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(10)
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

        encrypted_session_key "abcdefghijklmnopqrstuvwxyz123456";

        # TEST 1: key with default iv
        location /t1 {
            encrypted_session_expires 0;
            set $a 'abc';
            set_encrypt_session $res $a;
            set_decrypt_session $b $res;
            return 200 $b;
        }

        # TEST 2: key with custom iv
        location /t2 {
            encrypted_session_iv "12345678";
            encrypted_session_expires 0;
            set $a 'abc';
            set_encrypt_session $res $a;
            set_decrypt_session $b $res;
            return 200 $b;
        }

        # TEST 3: key with custom iv, short expires
        location /t3 {
            encrypted_session_iv "12345678";
            encrypted_session_expires 3;
            set $a 'abc';
            set_encrypt_session $res $a;
            set_decrypt_session $b $res;
            return 200 $b;
        }

        # TEST 4: key with custom iv, 1d expires
        location /t4 {
            encrypted_session_iv "12345678";
            encrypted_session_expires 1d;
            set_encrypt_session $res '1234';
            set_decrypt_session $b $res;
            return 200 $b;
        }

        # TEST 5: round-trip with uid value
        location /t5 {
            encrypted_session_iv "12345678";
            encrypted_session_expires 1d;
            set $uid 1315;
            set_encrypt_session $session $uid;
            set_decrypt_session $uid2 $session;
            return 200 $uid2;
        }

        # TEST 6: bad ciphertext (bad md5 checksum)
        location /t6 {
            encrypted_session_iv "12345678";
            encrypted_session_expires 1d;
            set $session "not valid encrypted session data";
            set_decrypt_session $uid $session;
            return 200 "[$uid]";
        }

        # TEST 7: bad ciphertext (bad md5 checksum, different corruption)
        location /t7 {
            encrypted_session_iv "12345678";
            encrypted_session_expires 1d;
            set $session "also not a valid encrypted session";
            set_decrypt_session $uid $session;
            return 200 "[$uid]";
        }

        # TEST 8: dropped (requires content_by_lua + ngx.sleep)

        # TEST 9, 10, 11: variable expires set inside if blocks
        location ~* '^/t/(\S+)' {
            set $duration $1;
            encrypted_session_iv "12345678";
            encrypted_session_expires 0;
            if ($duration = '8d') {
                encrypted_session_expires 8d;
            }
            if ($duration = '1d') {
                encrypted_session_expires 1d;
            }
            if ($duration = '16d') {
                encrypted_session_expires 16d;
            }
            set $a 'abc';
            set_encrypt_session $res $a;
            set_decrypt_session $b $res;
            return 200 $b;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/t1'), qr/abc\z/, 'key with default iv');
like(http_get('/t2'), qr/abc\z/, 'key with custom iv');
like(http_get('/t3'), qr/abc\z/, 'key with custom iv, expires 3s');
like(http_get('/t4'), qr/1234\z/, 'key with custom iv, expires 1d');
like(http_get('/t5'), qr/1315\z/, 'round-trip uid');
like(http_get('/t6'), qr/\[\]\z/, 'bad ciphertext');
like(http_get('/t7'), qr/\[\]\z/, 'bad ciphertext (2)');
like(http_get('/t/8d'),  qr/abc\z/, 'variable expires 8d');
like(http_get('/t/1d'),  qr/abc\z/, 'variable expires 1d');
like(http_get('/t/16d'), qr/abc\z/, 'variable expires 16d');

###############################################################################
