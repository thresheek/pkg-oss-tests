#!/usr/bin/perl

# Tests for ngx_http_rtmp_module, RTMP handshake, AMF connect, and rtmp_stat.

###############################################################################

use warnings;
use strict;

use Test::More;
use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/)->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

rtmp {
    server {
        listen      127.0.0.1:1935;
        access_log  off;

        application live {
            live on;
        }
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /stat {
            rtmp_stat all;
        }
    }
}

EOF

$t->run();

###############################################################################

# Complete the RTMP old-style handshake (zero version bytes bypass HMAC-SHA256)
# and return the open socket plus the 3073-byte server response, or undef.
#
# Old-style server sequence (two write stages):
#   SEND_CHALLENGE: echoes C0+C1 = 1537 bytes as S0+S1
#   SEND_RESPONSE:  echoes C1    = 1536 bytes as S2
#   Total server sends: 3073 bytes; then waits for C2 from client.
#
# Port 1935 is used literally: the framework's 8xxx auto-substitution does
# not apply here, so nginx.conf and the Perl client both use the literal port.
sub rtmp_handshake {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => 1935,
		Proto    => 'tcp',
		Timeout  => 5,
	) or return ();

	# C0 (0x03) + C1 (1536 bytes, all zero: timestamp=0, version=0 → old-style)
	$sock->print("\x03" . ("\x00" x 1536)) or return ();

	# Read S0+S1+S2 = 3073 bytes
	my $buf = '';
	while (length($buf) < 3073) {
		my $n = $sock->read(my $tmp, 3073 - length($buf));
		last unless $n;
		$buf .= $tmp;
	}
	return () unless length($buf) == 3073;

	# C2: echo of S1 (bytes 1..1536 of server response)
	$sock->print(substr($buf, 1, 1536)) or return ();

	return ($sock, $buf);
}

# t1: RTMP handshake — server responds with version byte 0x03
{
	my ($sock, $s) = rtmp_handshake();
	is(defined $s ? ord(substr($s, 0, 1)) : -1, 0x03,
		'RTMP handshake: server version byte 0x03');
	$sock->close() if $sock;
}

# t2: AMF connect — server logs "connect: app='live'" confirming AMF dispatch
#
# We send the connect command and close the socket; by the time we inspect
# error.log the server has already written the INFO log line (it logs before
# sending the _result response).  Reading the binary RTMP response from Perl
# risks blocking on a keep-open connection.
{
	my ($sock) = rtmp_handshake();
	SKIP: {
		skip 'handshake failed', 1 unless $sock;

		# 47-byte RTMP chunk: basic header (fmt=0,csid=3) + type-0 message
		# header + AMF0 "connect" command with object {app: "live"}
		$sock->print(
			"\x03"                          # basic header
			. "\x00\x00\x00"               # timestamp = 0
			. "\x00\x00\x23"               # message length = 35
			. "\x14"                        # type: 20 = AMF0 command
			. "\x00\x00\x00\x00"           # stream ID = 0 (LE)
			. "\x02\x00\x07connect"         # AMF string "connect"
			. "\x00\x3f\xf0\x00\x00\x00\x00\x00\x00"  # number 1.0
			. "\x03"                        # object start
			. "\x00\x03app"                 # key "app"
			. "\x02\x00\x04live"            # string value "live"
			. "\x00\x00\x09"              # object end
		);

		# Brief pause so the worker can process and log before we check
		select undef, undef, undef, 0.5;
		$sock->close();

		like($t->read_file('error.log'),
			qr/connect: app='live'/,
			'AMF connect: server processed connect command');
	}
}

# t3: rtmp_stat — HTTP stat endpoint returns valid XML
like(http_get('/stat'), qr/<rtmp>/, 'rtmp_stat: response contains <rtmp>');

# t4: rtmp_stat — configured application visible in stat XML
like(http_get('/stat'), qr/live/, 'rtmp_stat: application name in stat');

###############################################################################
