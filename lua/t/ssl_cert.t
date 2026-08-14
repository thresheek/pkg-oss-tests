#!/usr/bin/perl

# Tests for ngx_http_lua_module, ssl_certificate_by_lua_block.

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
	->has('socket_ssl_sni')
	->has('openssl:1.0.2')->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    lua_shared_dict ssl_cert 1m;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_certificate     %%TESTDIR%%/server.crt;
        ssl_certificate_key %%TESTDIR%%/server.key;

        ssl_certificate_by_lua_block {
            local ssl = require "ngx.ssl"
            local name = ssl.server_name() or "unknown"
            ngx.shared.ssl_cert:set("sni", name)
            ngx.log(ngx.NOTICE, "ssl_certificate_by_lua_block: sni=", name)
        }

        location /t1 {
            content_by_lua_block { ngx.say("ok") }
        }

        location /t2 {
            content_by_lua_block {
                ngx.say(ngx.shared.ssl_cert:get("sni") or "absent")
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

# make an HTTPS request to trigger ssl_certificate_by_lua_block
my $r = http_get('/t1',
	PeerAddr => '127.0.0.1:' . port(8080),
	SSL => 1,
	SSL_hostname => 'localhost',
	SSL_verify_mode => 0,
);

like($r, qr/ok/, 'ssl_certificate_by_lua_block: HTTPS request succeeds');
like($t->read_file('error.log'), qr/ssl_certificate_by_lua_block: sni=/,
	'ssl_certificate_by_lua_block ran');

# shdict written during TLS handshake is readable by HTTP handler
is(body(http_get('/t2',
	PeerAddr => '127.0.0.1:' . port(8080),
	SSL => 1,
	SSL_hostname => 'localhost',
	SSL_verify_mode => 0,
)), "localhost\n", 'ssl.server_name() captured via shdict');

###############################################################################
