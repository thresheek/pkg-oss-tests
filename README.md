# pkg-oss-tests

Test suites for third-party nginx modules as packaged in [nginx/pkg-oss](https://github.com/nginx/pkg-oss).

Tests are either converted from upstream module test suites or written from scratch, and adapted to run against the packaged builds.

These tests are not intended as an authoritative measure of full module correctness. They serve as regression tests only to check that additions to the nginx codebase do not explicitly break select third-party module functionality.

## Structure

One directory per module, containing a `t/` subdirectory of test scripts using the [nginx-tests](https://github.com/nginx/nginx-tests) library.

```
<module>/
└── t/
    └── *.t
```

## Supported pkg-oss branches

| pkg-oss branch | nginx core | Notes |
|----------------|------------|-------|
| `target-plus-r37.0` | 1.29.8 (NGINX Plus 37.0.0) | oldest supported |
| `stable-1.30` | 1.30.x (open-source stable) | same module versions as `target-plus-r37.0` |
| `master` / `target-plus-r37.1` | 1.31.x (NGINX Plus 37.1.0) | current |

## Modules

The version column shows the upstream version the tests were written/converted
from (current baseline).  The "also tested with" column lists the older version
packaged in `target-plus-r37.0` and `stable-1.30` (identical module set) that
the suite is also compatible with.

| Module | Version (baseline) | Also tested with | Tests |
|--------|--------------------|------------------|-------|
| [set-misc](set-misc/) | 0.34 | 0.33 | converted |
| [encrypted-session](encrypted-session/) | 0.10 | 0.09 | converted |
| [headers-more](headers-more/) | 0bf283ff | 0.39 (`2b1debde`) | converted |
| [subs-filter](subs-filter/) | c6f825fa | c6f825fa (unchanged) | converted |
| [brotli](brotli/) | 1.0.0rc | 1.0.0rc (unchanged) | converted |
| [fips-check](fips-check/) | 0.1 | 0.1 (unchanged) | from scratch |
| [geoip2](geoip2/) | 3.4 | 3.4 (unchanged) | from scratch |
| [lua](lua/) | 0.10.31 | 0.10.29 (`precontent.t` skipped) | from scratch |
| [rtmp](rtmp/) | 1.2.2 | 1.2.2 (unchanged) | from scratch |
| [auth-spnego](auth-spnego/) | 1.1.3 | 1.1.3 (unchanged) | from scratch |
