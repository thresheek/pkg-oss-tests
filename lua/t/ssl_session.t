#!/usr/bin/perl

# Tests for ngx_http_lua_module, ssl_session_store_by_lua_block and
# ssl_session_fetch_by_lua_block.

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

my $t = Test::Nginx->new()
	->has(qw/http http_ssl rewrite/)
	->has_daemon('openssl')
	->has('socket_ssl')
	->has('openssl:1.0.2')->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    lua_shared_dict ssl_sess 1m;

    ssl_session_store_by_lua_block {
        ngx.shared.ssl_sess:incr("store_count", 1, 0)
        ngx.log(ngx.NOTICE, "ssl_session_store_by_lua_block: ran")
    }

    ssl_session_fetch_by_lua_block {
        ngx.shared.ssl_sess:incr("fetch_count", 1, 0)
        ngx.log(ngx.NOTICE, "ssl_session_fetch_by_lua_block: ran")
    }

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_certificate      %%TESTDIR%%/server.crt;
        ssl_certificate_key  %%TESTDIR%%/server.key;
        ssl_protocols        TLSv1.2;
        ssl_session_tickets  off;
        ssl_session_cache    shared:SSL:1m;

        location /t1 {
            content_by_lua_block { ngx.say("ok") }
        }

        location /t2 {
            content_by_lua_block {
                local d = ngx.shared.ssl_sess
                ngx.say("store=" .. (d:get("store_count") or 0))
                ngx.say("fetch=" .. (d:get("fetch_count") or 0))
            }
        }
    }
}

EOF

my $d = $t->testdir();

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key  = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

system('openssl req -x509 -new '
	. "-config $d/openssl.conf -subj /CN=localhost/ "
	. "-out $d/server.crt -keyout $d/server.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate: $!";

$t->run();

###############################################################################

sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}

# first request: triggers ssl_session_store_by_lua_block
http_get('/t1',
	PeerAddr => '127.0.0.1:' . port(8080),
	SSL => 1,
	SSL_verify_mode => 0,
);

like($t->read_file('error.log'), qr/ssl_session_store_by_lua_block: ran/,
	'ssl_session_store_by_lua_block ran');

# second request: may trigger ssl_session_fetch_by_lua_block on resumption
http_get('/t1',
	PeerAddr => '127.0.0.1:' . port(8080),
	SSL => 1,
	SSL_verify_mode => 0,
);

like($t->read_file('error.log'), qr/ssl_session_fetch_by_lua_block: ran/,
	'ssl_session_fetch_by_lua_block ran');

# store counter must be >= 1
my $r = body(http_get('/t2',
	PeerAddr => '127.0.0.1:' . port(8080),
	SSL => 1,
	SSL_verify_mode => 0,
));
like($r, qr/store=[1-9]/, 'store hook invocation count >= 1');

###############################################################################
