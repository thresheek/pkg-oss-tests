# AGENTS.md

Guidance for agents converting third-party nginx module test suites into this repo.

## What this repo is

Test suites for third-party nginx modules as packaged in
[nginx/pkg-oss](https://github.com/nginx/pkg-oss).

* **Source**: the module's own upstream suite, written for OpenResty's
  `Test::Nginx::Socket` (Perl DSL, `.t` files with `__DATA__` and `=== TEST n:` blocks).
* **Target**: the [nginx/nginx-tests](https://github.com/nginx/nginx-tests) framework
  (`lib/Test/Nginx.pm` + plain `Test::More` assertions).

Layout:

```
<module>/
├── LICENSE          # upstream license text + "Copyright (C) <year>, <name>, F5, Inc."
└── t/
    └── *.t          # one converted file per upstream t/*.t, same filename
```

After adding a module, add a row to the table in `README.md` with the upstream
version the tests were converted from (must match the version packaged in pkg-oss).

## Hard rules

**1. No dependencies beyond what nginx-tests itself can use.**
The tests must run against a stock nginx build plus *only* the module under test.
That means **no OpenResty modules**: no `echo`, no `set_iconv` / iconv support,
no `lua`, no `srcache`, no `headers-more`, no `array-var`, no `encrypted-session`
helpers in another module's tests, etc. Standard nginx modules (`http`, `rewrite`,
`proxy`, `ssi`, `map`, `return`, ...) are fine — declare them via `->has(...)`.

Perl-side the rule is: **anything nginx-tests itself already uses is allowed.**
That is core Perl (`POSIX`, `Socket`, `IO::Select`, `IO::Socket::INET`, `IO::Poll`,
`MIME::Base64`, `Digest::MD5`, `Encode`, `Time::Local`, `IO::Compress::Gzip`,
`Sys::Hostname`, `File::Temp`, `Config`, ...), `Test::More`, and the framework's own
helpers (`Test::Nginx`, `Test::Nginx::Stream`, `Test::Nginx::HTTP2`, ...).

Non-core CPAN modules that nginx-tests uses are allowed too, but only the same way
it uses them — loaded lazily and guarded so the file skips instead of failing when
they are absent:

```perl
eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
```

That set is effectively `IO::Socket::SSL`, `CryptX` (`Crypt::*`; also available as
`->has('cryptx')`), `JSON::PP`/`JSON::XS`, and `Protocol::WebSocket::*`. Do not
reach for anything outside it, and never make a whole module's suite depend on a
CPAN module when a core one will do.

**2. Convert only deterministic tests.** Not everything upstream needs to survive.
Drop a block if it is:

* timing/scheduling sensitive, or depends on `repeat_each()` to shake out randomness;
* already marked `--- SKIP` upstream;
* a `--- must_die` / `[emerg]` config-failure test (nginx-tests has no `must_die`,
  and a bad directive would abort startup for the whole merged config);
* dependent on a module we cannot use (rule 1);
* dependent on the deprecated aliases / build options not present in the packaged build.

Randomised output *can* be tested when the property is deterministic — assert the
shape (`qr/^[a-zA-Z0-9]{32}$/`) or the range, sampling a modest number of times.

**3. Preserve traceability.** Keep upstream filenames verbatim. Keep upstream
location numbering (`/t1`, `/t2`, ...) including the *gaps* left by dropped blocks,
so the mapping back to `=== TEST n` stays obvious. Test descriptions are the
upstream block titles, lowercased and typo-fixed.

## File skeleton

Copy this exactly (`set-misc/t/base64.t` is the canonical reference):

```perl
#!/usr/bin/perl

# Tests for ngx_http_set_misc_module, base64 encoding and decoding.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(2)
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

        location /encode {
            set_encode_base64 $out "abcde";
            return 200 $out;
        }

        location /decode {
            set_decode_base64 $out "YWJjZGU=";
            return 200 $out;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/encode'), qr/YWJjZGU=\z/, 'base64 encode');
like(http_get('/decode'), qr/abcde\z/, 'base64 decode');

###############################################################################
```

Style invariants:

* Separator lines are exactly 79 `#`. File ends with a separator line.
* Perl code is **tab**-indented (the `->write_file_expand` continuation starts with a tab);
  `nginx.conf` inside the heredoc is **4 spaces** per level, `listen`/`server_name` aligned.
* Heredoc is `<<'EOF'` (single-quoted) so `$vars` in the config are not interpolated.
* Use `%%TEST_GLOBALS%%` and `%%TEST_GLOBALS_HTTP%%`. Always `daemon off;` and `events { }`.
* Hardcode `listen 127.0.0.1:8080;` — `write_file_expand` rewrites `127.0.0.1:8xxx` to a real port.
* `plan(N)` counts only your own assertions; `Test::Nginx::plan` adds 2 automatically
  (the no-alerts and no-sanitizer-errors checks).
* Add `worker_processes 1;` only when the test depends on per-worker state
  (e.g. `set_rotate` in `set-misc/t/rotate.t:29`).
* Extra `use` lines (e.g. `use POSIX qw(strftime);`) go between `use strict;` and `use Test::More;`.

## Conversion cheat-sheet

| OpenResty `Test::Nginx::Socket` | nginx-tests `Test::Nginx` |
|---|---|
| `# vi:filetype=` header | `#!/usr/bin/perl` + `# Tests for ngx_http_X_module, <directives>.` |
| `use Test::Nginx::Socket;` | `use Test::More;` + `FindBin` chdir + `use lib 'lib'; use Test::Nginx;` |
| `plan tests => repeat_each() * 2 * blocks();` | `->plan(N)`, N = number of surviving assertions |
| `run_tests();` + `__DATA__` | `$t->run();` + plain `Test::More` assertions |
| one `--- config` per block, all `location /bar` | **one merged `nginx.conf`**; each block becomes `location /tN` or a semantic name (`/encode`, `/sha1`, `/blank`) |
| `echo $out;` | `return 200 $out;` — the single most important substitution |
| `echo $a; echo $b;` | `return 200 "$a $b";` (pick a separator and assert on it) |
| `echo_location /incr;` xN | N sequential `http_get('/incr')` collected into a list |
| `echo_location_async /foo?id=x;` xN | N separate `http_get` + individual assertions |
| `--- request\n GET /bar` | `http_get('/bar')` |
| `--- response_body\nabcde` | `like(http_get(...), qr/abcde\z/, '...')` — `return` emits **no** trailing newline, unlike `echo` |
| `--- response_body_like: 3[5-7]` | `like(body(http_get(...)), qr/^3[5-7]$/, '...')` |
| `--- error_code: 500` (+ 500 body) | `like(http_get(...), qr/ 500 /, '...')` (status-line match) |
| empty body (upstream expects `"\n"`) | `like(http_get('/blank'), qr!Content-Length: 0!, '...')` |
| `repeat_each(N)` | drop, or an explicit loop when the test is about state/sampling |
| `no_long_string()`, `no_shuffle()`, `no_diff()`, `log_level()` | drop |
| `--- must_die`, `--- SKIP` | drop the block (keep its number gap) |
| Perl vars interpolated into blocks (`$main::foo`) | compute at runtime in the assertion section |

Merged-config gotchas:

* Directives upstream placed once at `server`/`--- config` level must be **repeated in
  every location** of the merged config (see `set-misc/t/base32_no_padding.t`, which
  repeats `set_base32_padding off;` in all 27 locations).
* `upstream` / `upstream_list` blocks are hoisted into the single `http` / `server`.
* Watch for blocks that become byte-identical after merging (their upstream distinction
  was location-vs-server placement). Keep them, they are still a valid regression check.

Regex conventions:

* Anchor whole-response matches with `\z`.
* Use `qr!...!` when the expected string contains `/`.
* Wrap literal payloads in `\Q...\E`, especially anything containing backslashes.
  For strings with `\0`, `\t`, `\b`, `\Z`, `\$`, build the expectation as a
  single-quoted Perl literal first, then match with `qr!\Q$var\E\z!` (see
  `set-misc/t/quote-sql.t`).

## Helper snippets

These are local helpers, copy-pasted into the files that need them (do not
factor them into a shared module — nginx-tests files are self-contained).

Body extraction (used instead of `Test::Nginx::http_content`):

```perl
sub body {
	my ($r) = @_;
	$r =~ /\x0d\x0a\x0d\x0a(.*)\z/s;
	return defined $1 ? $1 : '';
}
```

Sequential requests for per-location/per-worker state (replaces `echo_location` chains):

```perl
sub seq {
	my ($uri, $n) = @_;
	my @out;
	push @out, body(http_get($uri)) for (1 .. $n);
	return \@out;
}

is_deeply(seq('/t5', 6),
	['a = 1', 'a = 2', 'a = 3', 'a = 1', 'a = 2', 'a = 3'],
	'no current value is given');
```

Sampling a randomised value (replaces `repeat_each(100)`):

```perl
sub in_range {
	my ($uri, $re, $n) = @_;
	for (1 .. $n) {
		return 0 unless body(http_get($uri)) =~ $re;
	}
	return 1;
}

ok(in_range('/rand1', qr/^[5-7]$/, 50), 'sanity');
```

Clock-tolerant time assertions (the clock may tick between building the
expectation and serving the request):

```perl
sub candidates {
	my ($gmt) = @_;
	my $now = time();
	my %set;
	for my $d (-1 .. 2) {
		my @tm = $gmt ? gmtime($now + $d) : localtime($now + $d);
		$set{ strftime($fmt, @tm) } = 1;
	}
	return \%set;
}

my $loc = candidates(0);
ok($loc->{ body(http_get('/local')) }, 'local time format');
```

## Error-log assertions (optional)

Upstream `--- error_log` / `--- no_error_log [error]` expectations are **dropped by
default** — the set-misc conversion asserts on body and status only, which keeps the
tests fast and free of log-format coupling.

Convert one only when it is the *only* observable behaviour of a feature. In that
case use `$t->read_file('error.log')`:

```perl
like($t->read_file('error.log'), qr/set_rotate: bad current value: "abc"/,
	'bad current value logged');
```

Caveats before you do this:

* `%%TEST_GLOBALS%%` already sets `error_log ... debug;`, so debug-level messages are
  available only if the binary was built with `--with-debug` — do not rely on them.
* The log is cumulative for the whole file; a message from an earlier request will
  still match later. Assert on messages unique enough to be unambiguous, or check
  ordering explicitly.
* `Test::Nginx::DESTROY` already fails the run on any `[alert]` line, and there are
  two implicit tests for that — do not duplicate.
* `no_error_log [error]` has no direct equivalent and is not worth emulating; skip it.

## Running the tests

The `.t` files locate the framework via `use lib 'lib'` relative to their own
directory (`BEGIN { use FindBin; chdir($FindBin::Bin); }`). Provide
`nginx-tests`' `lib/Test/Nginx.pm` at `<module>/t/lib/Test/Nginx.pm` (copy or
symlink), or run the files from inside an nginx-tests checkout.

```sh
git clone https://github.com/nginx/nginx-tests /tmp/nginx-tests
ln -s /tmp/nginx-tests/lib set-misc/t/lib

TEST_NGINX_BINARY=/usr/sbin/nginx \
TEST_NGINX_GLOBALS='load_module modules/ngx_http_set_misc_module.so;' \
	prove -v set-misc/t/
```

Useful environment variables:

| Variable | Purpose |
|---|---|
| `TEST_NGINX_BINARY` | nginx binary (default `../nginx/objs/nginx`) |
| `TEST_NGINX_GLOBALS` | spliced into `%%TEST_GLOBALS%%`; use for `load_module` of dynamic modules |
| `TEST_NGINX_GLOBALS_HTTP` | spliced into `%%TEST_GLOBALS_HTTP%%` |
| `TEST_NGINX_VERBOSE` | log request/response traffic |
| `TEST_NGINX_CATLOG` | dump `error.log` on exit |
| `TEST_NGINX_LEAVE` | keep the temp test directory |

`has()` also matches `load_module` lines from `TEST_NGINX_GLOBALS`, so
`->has('ngx_http_set_misc_module')` can be used to skip when the dynamic module is
not loaded. Alternatively `$t->try_run('no set-misc module')` skips the file when
nginx fails to start with the config. Neither is used today (the harness is expected
to load the module), but both are legitimate if a suite needs it.

## Checklist for adding a module

1. Fetch the upstream tarball at exactly the version packaged in pkg-oss.
2. Create `<module>/t/`, one converted `.t` per upstream `t/*.t`, filenames preserved.
3. Triage every `=== TEST n` block against the "Hard rules"; drop what cannot be
   converted deterministically or without extra modules.
4. Merge each file's blocks into one `nginx.conf`; repeat server-level directives per location.
5. Make sure `plan(N)` equals the number of assertions you wrote.
6. Run the file; verify it passes and that no test silently asserts nothing
   (`return 200` with an empty variable trivially matches many regexes — anchor with `\z`).
7. Add `<module>/LICENSE` (upstream text + F5 copyright line).
8. Add the module row to `README.md`.

## Current state

| Module | Version | Status |
|---|---|---|
| set-misc | 0.34 | done — 18 files, all upstream files converted |
| encrypted-session | 0.10 | done — 1 file (`sanity.t`) |
| headers-more | 0bf283ff | done — 7 files (3 upstream files dropped) |
| subs-filter | c6f825fa | done — 6 files, all upstream files converted |
| brotli | 1.0.0rc | done — 2 files (`brotli.t`, `brotli_h2.t`) |
| fips-check | 0.1 | done — 1 file (`fips_check.t`) |
| geoip2 | 3.4 | done — 3 files (`geoip2.t`, `geoip2_proxy_recursive.t`, `geoip2_stream.t`) |
| njs | — | skipped — test suite maintained in the njs upstream repo and reused directly in pkg-oss CI; no conversion needed here |
| acme | — | skipped — test suite maintained in the acme upstream repo and reused directly in pkg-oss CI; no conversion needed here |
| ndk | — | skipped — no standalone observable behaviour; covered implicitly by set-misc and other module tests that depend on it |
| rtmp | — | skipped — requires RTMP protocol client; no tractable nginx-tests equivalent |
| otel | — | skipped — module maintained by the F5 team who track nginx compatibility directly; no conversion needed here |
| auth-spnego | — | skipped — requires a live Kerberos KDC and keytab; not feasible in isolation |
| passenger | — | skipped — requires Phusion Passenger and a Ruby/Python/Node application runtime |

Blocks deliberately dropped from set-misc:

* `base32.t` TEST 29, 30 — `--- must_die` checks on a wrong-length `set_base32_alphabet`.
* `base32_no_padding.t` TEST 28 — deprecated `set_misc_base32_padding` alias.
* `quote-sql.t` TEST 8 — requires `set_iconv` (libiconv-enabled OpenResty build).
* `rand.t` TEST 9 — marked `--- SKIP` upstream (location numbering jumps `/rand8` → `/rand10`).
* All `--- error_log` / `--- no_error_log` assertions, per the policy above.

Blocks deliberately dropped from encrypted-session:

* `sanity.t` TEST 8 — requires `content_by_lua` + `ngx.sleep` (OpenResty only).
* All `--- error_log` assertions (expires values), per the policy above.
* `echo`, `echo_exec`, `set_encode_base32`, `set_decode_base32`, `set_unescape_uri`
  replaced throughout by inline encrypt→decrypt round-trips; tests 6 and 7 use a
  literal garbage value instead of the upstream's specific tampered base32 ciphertexts.

Blocks deliberately dropped from headers-more:

* `eval.t` — whole file, requires `ngx_http_eval_module` (OpenResty).
* `input-ua.t` — whole file, all meaningful assertions are SystemTap (`--- stap`)
  probes checking nginx internal browser-detection struct fields; body-only residuals
  are too superficial to be worth keeping.
* `subrequest.t` — whole file, all tests use `echo_location` (echo module).
* `unused.t` — whole file, all assertions are debug-level `--- error_log` checks
  (require `--with-debug` build); body-only residuals don't test module behaviour.
* `sanity.t` TEST 36, 37 — `--- must_die` config-failure tests.
* `input.t` TEST 3, 4 — `echo_read_request_body` / `echo_request_body` (echo module).
* `input.t` TEST 23, 29-33 — use `$echo_client_request_headers` (echo module).
* `input.t` TEST 43 — `content_by_lua`.
* `input-conn.t` TEST 1 — clearing `Connection: keep-alive` cannot prevent
  nginx 1.31+ from keeping the connection alive: the keep-alive decision is
  committed before the rewrite phase, so `http()` in the test times out.
* `input.t` TEST 24 — `more_set_input_headers 'Accept-Encoding: gzip'` cannot
  trigger gzip for static-file serving: the gzip module reads its struct field
  before the rewrite phase.
* `input.t` TEST 44, 45, 46 — clearing If-Unmodified-Since / If-Match /
  If-None-Match has no effect: nginx 1.25+ checks these conditional headers from
  parsed struct fields in the not-modified header filter, after the rewrite phase
  but reading the pre-parsed values that headers-more cannot update.
* All `--- stap` / `--- stap_out` assertions (SystemTap) in `input-conn.t`,
  `input-cookie.t`, and `input.t` — body assertions are kept.
* All `--- error_log` / `--- no_error_log` assertions, per the policy above.

Blocks deliberately dropped from brotli:

The upstream test suite is a bash script (`script/.travis-test.sh`), not OpenResty
`Test::Nginx::Socket`. Tests were written from scratch based on what the script checks.
18 upstream tests total; 6 dropped, 12 converted across 2 files.

* Test 1 (H1 long file with rate limit) — timing/rate-sensitive; large static file
  spans multiple nginx buffers, making precomputed brotli bytes non-deterministic.
* Test 16 (H2 long file with rate limit) — same reasons.
* Tests 14–15 and H2 test 18 (`bar`, `b`, `b` tokens on `small.html`) — converted
  faithfully: the upstream uses a `text/html` file which is always a brotli type
  (nginx always includes `text/html` via `ngx_http_html_default_types` regardless
  of `brotli_types` setting); assert plain body passes through unchanged.

Implementation notes for brotli:

* The upstream uses a bash/curl test harness, not OpenResty Socket DSL. No upstream
  `.t` filenames to preserve; files are named after the upstream conf files.
* Precomputed brotli bytes use `quality=1` (matching upstream `brotli_comp_level 1`)
  and `lgwin=10` (the nginx filter's dynamic window selection for content < 1024 bytes:
  `wbits = BROTLI_MIN_WINDOW_BITS; while wbits < conf->lg_win && len > (1<<wbits): wbits++`).
  Generated with Python brotli 1.2.0: `brotli.compress(content, quality=1, lgwin=10)`.
* `return 200 "string"` produces a single nginx buffer with `last_buf=1`, so
  `BrotliEncoderCompressStream` is called once with `BROTLI_OPERATION_FINISH` —
  identical to one-shot compression. Precomputed bytes are therefore deterministic.
* `brotli_min_length 1` is set so short test strings (< 20 bytes default) are compressed.
* `brotli_types text/plain` is added; `text/html` is always included by the module
  regardless of the `brotli_types` setting (`ngx_http_html_default_types` base).
* Test 2 (compressed 404): assertion is header-only (`Content-Encoding: br`) because
  the nginx error page body is version-dependent and cannot be precomputed.

Blocks deliberately dropped from geoip2:

* (none) — no upstream test suite exists; tests written from scratch.

Implementation notes for geoip2:

* No upstream tests exist. Tests cover: country code lookup, default value for
  unknown IPs, nested name lookup, metadata (`build_epoch`), `geoip2_proxy`,
  `geoip2_proxy_recursive`, and stream module.
* The `.mmdb` database is pre-generated with Python `mmdb_writer` 1.2.0
  (ip_version=4, type=GeoIP2-Country) and embedded as base64 in all three test
  files, decoded and written to `%%TESTDIR%%/country.mmdb` before `$t->run()`.
  Contents: `1.2.3.0/24 → AU`, `2.3.4.0/24 → US`, `127.0.0.0/8 → CN`.
* `source=$arg_ip` is used in `geoip2.t` to avoid the 127.0.0.1 loopback
  problem with `$remote_addr` when making HTTP requests from the test client.
* `geoip2_proxy_recursive` is `NGX_HTTP_MAIN_CONF` — it cannot vary per server
  block, so the recursive test lives in its own file (`geoip2_proxy_recursive.t`)
  with a dedicated nginx.conf setting `geoip2_proxy_recursive on`.
* The stream test (`geoip2_stream.t`) connects from 127.0.0.1, which maps to CN
  via `127.0.0.0/8`. A minimal HTTP server on port 8080 satisfies `$t->run()`
  startup detection; the geoip2 stream server listens on port 8081.
* `geoip2_proxy_recursive.t` test 2 verifies the edge case where the entire XFF
  chain is trusted: the module exhausts the chain and falls back to `$remote_addr`
  (127.0.0.1 → CN).

Blocks deliberately dropped from fips-check:

* (none) — no upstream test suite exists; test written from scratch.

Implementation notes for fips-check:

* The module has no upstream tests. The single observable behaviour is a
  `NGX_LOG_NOTICE` message written to `error.log` at startup.
* `%%TEST_GLOBALS%%` sets `error_log ... debug;` which captures NOTICE-level
  messages. The assertion uses `$t->read_file('error.log')`.
* The module's `fips_state` guard ensures the message fires exactly once
  (init_module in the master process; worker processes inherit the non-UNKNOWN
  state and produce no further output).
* In a standard (non-FIPS) build, `FIPS_mode()` returns 0, so the message is
  always `"OpenSSL FIPS Mode is not enabled"`.
* A minimal HTTP server block is required so that `$t->run()` can confirm nginx
  started by connecting to port 8080; no HTTP requests are made.

Blocks deliberately dropped from subs-filter:

* (none) — all 19 upstream tests converted.

Implementation notes for subs-filter:

* Tests that originally proxied to live external servers (yaoweibin.net) are
  replaced by a local backend location returning `return 200 "Find taobao.com here."`
  with `default_type text/html`. The substitution logic is identical; the content
  only needs to contain the target string.
* `--- user_files >>> foo.txt` for short content is replaced by `return 200 "content"`
  with an appropriate `default_type`. Large-body tests (subs.t TEST 3–6) use
  `$t->write_file()` to write a multi-kilobyte string of `a` characters.
* `subs_filter` defaults to filtering `text/html` only. Locations using
  `subs_filter_types text/plain` must also set `default_type text/plain` when
  the response body comes from `return 200` rather than a file served by extension.

Implementation note — `return 200 $var` vs `proxy_pass` for input-header tests:
When a location adds any `proxy_set_header` directive it cancels **all**
inherited server-level `proxy_set_header` directives (nginx inheritance rule).
Locations that need multiple proxy headers must list them all explicitly.

Implementation note — `return 200 $var` vs `proxy_pass` for input-header tests:
`more_set/clear_input_headers` registers a rewrite-phase handler. The rewrite
module's own handler (which evaluates `return 200 $var`) runs first in that same
phase, before headers-more modifies the headers. As a result, `return 200 $var`
always sees the pre-modification value. Tests that need to observe the modified
variable must use `proxy_pass` to a backend location, where `return 200 $var`
runs in the content phase — after the rewrite phase is complete.
