#!/usr/bin/perl

# Tests for nginx-fips-check-module, FIPS mode logging.

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

my $t = Test::Nginx->new()->has(qw/http/)->plan(1)
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

EOF

$t->run();

###############################################################################

like($t->read_file('error.log'),
	qr/OpenSSL FIPS Mode is not enabled/,
	'fips mode not enabled logged at startup');

###############################################################################
