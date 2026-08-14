#!/usr/bin/perl

# Tests for spnego-http-auth-nginx-module, Kerberos/SPNEGO authentication.
# Requires a local MIT Kerberos KDC; guarded by has_daemon checks.
# Perl GSSAPI module required to obtain service tokens from the credential cache.

###############################################################################

use warnings;
use strict;

use Test::More;
use MIME::Base64;
use POSIX qw/ WNOHANG /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http/)
	->has_daemon('krb5kdc')
	->has_daemon('kadmin.local')
	->has_daemon('kdb5_util')
	->has_daemon('kinit')
	->plan(5);

eval { require GSSAPI; GSSAPI->import(); };
plan(skip_all => "GSSAPI Perl module not available: $@") if $@;

my $d = $t->testdir();

###############################################################################
# 1. Write Kerberos configuration files
###############################################################################

$t->write_file('krb5.conf', <<"EOF");
[libdefaults]
    default_realm = NGINX.TEST
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 1h
    forwardable = true

[realms]
    NGINX.TEST = {
        kdc = localhost:60088
    }
EOF

$t->write_file('kdc.conf', <<"EOF");
[kdcdefaults]
    kdc_ports = 60088
    kdc_tcp_ports = 60088

[realms]
    NGINX.TEST = {
        database_name = $d/principal
        key_stash_file = $d/.k5stash
        acl_file = $d/kadm5.acl
        max_life = 1h
        max_renewable_life = 1d
    }

[logging]
    kdc = FILE:$d/kdc.log
EOF

$t->write_file('kadm5.acl', "*/admin\@NGINX.TEST *\n");

###############################################################################
# 2. Point MIT Kerberos tools at our test config
###############################################################################

$ENV{KRB5_CONFIG}      = "$d/krb5.conf";
$ENV{KRB5_KDC_PROFILE} = "$d/kdc.conf";
$ENV{KRB5CCNAME}       = "FILE:$d/krb5cc_test";

###############################################################################
# 3. Create realm database and principals
###############################################################################

system("kdb5_util create -r NGINX.TEST -P masterpassword -s 2>>$d/setup.log") == 0
	or BAIL_OUT('kdb5_util create failed; see ' . $d . '/setup.log');

# Service principal for nginx
system("kadmin.local -r NGINX.TEST -q "
	. "'addprinc -randkey HTTP/localhost\@NGINX.TEST' >>$d/setup.log 2>&1") == 0
	or BAIL_OUT('addprinc HTTP/localhost failed');

system("kadmin.local -r NGINX.TEST -q "
	. "'ktadd -k $d/nginx.keytab HTTP/localhost\@NGINX.TEST' >>$d/setup.log 2>&1") == 0
	or BAIL_OUT('ktadd HTTP/localhost failed');

# Authorised test user (keytab-based, no password needed)
system("kadmin.local -r NGINX.TEST -q "
	. "'addprinc -randkey testuser\@NGINX.TEST' >>$d/setup.log 2>&1") == 0
	or BAIL_OUT('addprinc testuser failed');

system("kadmin.local -r NGINX.TEST -q "
	. "'ktadd -k $d/testuser.keytab testuser\@NGINX.TEST' >>$d/setup.log 2>&1") == 0
	or BAIL_OUT('ktadd testuser failed');

# Unauthorised user (for 403 test)
system("kadmin.local -r NGINX.TEST -q "
	. "'addprinc -randkey denied\@NGINX.TEST' >>$d/setup.log 2>&1") == 0
	or BAIL_OUT('addprinc denied failed');

system("kadmin.local -r NGINX.TEST -q "
	. "'ktadd -k $d/denied.keytab denied\@NGINX.TEST' >>$d/setup.log 2>&1") == 0
	or BAIL_OUT('ktadd denied failed');

###############################################################################
# 4. Start KDC as a background process
###############################################################################

my $kdc_pid = fork();
BAIL_OUT('fork failed') unless defined $kdc_pid;
if ($kdc_pid == 0) {
	exec('krb5kdc', '-n', '-r', 'NGINX.TEST');
	exit 1;
}

# Wait for the KDC to be ready (it binds port 60088 rapidly)
select undef, undef, undef, 0.5;

###############################################################################
# 5. Write nginx.conf and start nginx
###############################################################################

$t->write_file_expand('nginx.conf', <<"NGINX_CONF");

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # 'return' is a rewrite-phase directive and fires before auth_gss
        # (access phase), so it must NOT be used in auth_gss locations.
        # Use try_files (content phase) instead; expose \$remote_user via
        # add_header so the test can assert on it.
        root $d;

        # Protected: any authenticated principal
        location /protected {
            auth_gss                      on;
            auth_gss_keytab               $d/nginx.keytab;
            auth_gss_service_name         HTTP/localhost;
            auth_gss_realm                NGINX.TEST;
            auth_gss_allow_basic_fallback off;
            auth_gss_format_full          on;
            add_header X-Remote-User      \$remote_user always;
            try_files /ok.html            =404;
        }

        # Restricted: only testuser may enter
        location /restricted {
            auth_gss                         on;
            auth_gss_keytab                  $d/nginx.keytab;
            auth_gss_service_name            HTTP/localhost;
            auth_gss_realm                   NGINX.TEST;
            auth_gss_allow_basic_fallback    off;
            auth_gss_format_full             on;
            auth_gss_authorized_principal    testuser\@NGINX.TEST;
            add_header X-Remote-User         \$remote_user always;
            try_files /ok.html               =404;
        }
    }
}

NGINX_CONF

$t->write_file('ok.html', 'ok');

$t->run();

###############################################################################
# 6. Obtain KRB5 credentials and build SPNEGO token for each user
###############################################################################

sub get_token {
	my ($keytab, $principal) = @_;

	# Get a fresh TGT from the test KDC
	local $ENV{KRB5CCNAME} = "FILE:$d/krb5cc_$$";
	system("kinit -kt $keytab $principal 2>>$d/kinit.log") == 0
		or return undef;

	# Import the service name
	my $target;
	GSSAPI::Name->import($target, "HTTP\@localhost",
		GSSAPI::OID::gss_nt_hostbased_service())
		or return undef;

	# Call gss_init_sec_context to obtain the client token
	my ($ctx, $in_tok, $out_tok) = (GSSAPI::Context->new(), "", "");
	my $status = $ctx->init(
		undef,                                    # use default credential
		$target,
		GSSAPI::OID::gss_mech_krb5(),
		2 | 8,                                    # GSS_C_MUTUAL_FLAG | GSS_C_SEQUENCE_FLAG
		0,                                        # no time limit
		undef,                                    # no channel bindings
		$in_tok,
		undef,                                    # actual mech (output, ignored)
		$out_tok,
		undef,                                    # ret_flags  (output, ignored)
		undef,                                    # time_rec   (output, ignored)
	);

	# GSS_S_COMPLETE = 0, GSS_S_CONTINUE_NEEDED = 1
	return undef unless $status->major == 0 || $status->major == 1;

	return "Negotiate " . encode_base64($out_tok, '');
}

my $auth_testuser = get_token("$d/testuser.keytab", "testuser\@NGINX.TEST");
BAIL_OUT('failed to obtain GSSAPI token for testuser') unless $auth_testuser;

my $auth_denied = get_token("$d/denied.keytab", "denied\@NGINX.TEST");
BAIL_OUT('failed to obtain GSSAPI token for denied') unless $auth_denied;

###############################################################################

# t1: no credentials → 401 Unauthorized
my $r = http_get('/protected');
like($r, qr/ 401 /, 'unauthenticated: 401');

# t2: 401 must include Negotiate challenge
like($r, qr/WWW-Authenticate: Negotiate/, 'unauthenticated: Negotiate challenge');

# t3: valid token → 200
$r = http("GET /protected HTTP/1.0\r\nHost: localhost\r\n"
	. "Authorization: $auth_testuser\r\n\r\n");
like($r, qr/ 200 /, 'valid token: 200');

# t4: X-Remote-User header contains the authenticated principal
like($r, qr/X-Remote-User: testuser\@NGINX\.TEST/, 'remote_user set to authenticated principal');

# t5: valid token but principal not in auth_gss_authorized_principal → 403
$r = http("GET /restricted HTTP/1.0\r\nHost: localhost\r\n"
	. "Authorization: $auth_denied\r\n\r\n");
like($r, qr/ 403 /, 'unauthorized principal: 403');

###############################################################################

END {
	# Stop the KDC
	if ($kdc_pid) {
		kill 'TERM', $kdc_pid;
		waitpid($kdc_pid, 0);
	}
	# Destroy any lingering credentials
	system("kdestroy -c $d/krb5cc_test 2>/dev/null");
}

###############################################################################
