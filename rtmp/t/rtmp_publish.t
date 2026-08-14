#!/usr/bin/perl

# Tests for ngx_rtmp_module, live stream publish via Perl RTMP client.
# No external tools required — the RTMP control plane is implemented directly
# using IO::Socket::INET.  nginx-rtmp marks a stream as published (visible
# in /stat) as soon as the "publish" AMF command is received, before any
# video or audio data arrives.

###############################################################################

use warnings;
use strict;

use Test::More;
use IO::Socket::INET;
use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/)->plan(2)
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

# Non-blocking read helper: drain all available bytes and look for $pattern.
# Uses non-blocking sysread so the call returns immediately once the server
# goes idle, avoiding the hang caused by a blocking read on a keep-open socket.
sub rtmp_read {
	my ($sock, $pattern, $timeout) = @_;
	my $sel = IO::Select->new($sock);
	my $buf = '';
	$sock->blocking(0);
	while ($sel->can_read($timeout // 3)) {
		my $n = sysread($sock, my $tmp, 4096);
		last unless defined $n && $n > 0;
		$buf .= $tmp;
		last if $buf =~ $pattern;
	}
	$sock->blocking(1);
	return $buf;
}

# Complete the old-style RTMP handshake (zero version bytes skip HMAC-SHA256).
sub rtmp_handshake {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => 1935,
		Proto    => 'tcp',
		Timeout  => 5,
	) or return undef;

	$sock->print("\x03" . ("\x00" x 1536)) or return undef;

	my $buf = '';
	while (length($buf) < 3073) {
		my $n = $sock->read(my $tmp, 3073 - length($buf));
		last unless $n;
		$buf .= $tmp;
	}
	return undef unless length($buf) == 3073;

	$sock->print(substr($buf, 1, 1536)) or return undef;
	return $sock;
}

# ---- Drive the RTMP publish flow ----

my $sock = rtmp_handshake();
BAIL_OUT('RTMP handshake failed') unless $sock;

# 1. AMF connect {app:"live"}  (csid=3, stream=0, type=0x14, payload=35 bytes)
$sock->print(
	"\x03\x00\x00\x00\x00\x00\x23\x14\x00\x00\x00\x00"
	. "\x02\x00\x07connect"
	. "\x00\x3f\xf0\x00\x00\x00\x00\x00\x00"
	. "\x03\x00\x03app\x02\x00\x04live\x00\x00\x09"
);
rtmp_read($sock, qr/_result/, 3);

# 2. AMF createStream (transaction=2, null command object; payload=25 bytes)
$sock->print(
	"\x03\x00\x00\x00\x00\x00\x19\x14\x00\x00\x00\x00"
	. "\x02\x00\x0ccreateStream"
	. "\x00\x40\x00\x00\x00\x00\x00\x00\x00"
	. "\x05"
);
rtmp_read($sock, qr/_result/, 3);

# 3. AMF publish "test" "live" (transaction=0, null, stream_id=1; payload=34 bytes)
#    nginx-rtmp registers the stream as soon as this command is received,
#    before any media data arrives, so /stat will show it immediately.
$sock->print(
	"\x03\x00\x00\x00\x00\x00\x22\x14\x01\x00\x00\x00"
	. "\x02\x00\x07publish"
	. "\x00\x00\x00\x00\x00\x00\x00\x00\x00"
	. "\x05"
	. "\x02\x00\x04test"
	. "\x02\x00\x04live"
);

# Poll /stat until the stream appears (up to 5 s)
my $found = 0;
for (1..25) {
	if (http_get('/stat') =~ m{<name>test</name>}) {
		$found = 1;
		last;
	}
	select undef, undef, undef, 0.2;
}

ok($found, 'published stream visible in /stat');
like(http_get('/stat'), qr{<nclients>1</nclients>},
	'nclients reflects active publisher');

$sock->close();

###############################################################################
