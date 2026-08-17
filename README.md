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

## Modules

| Module | Version | Tests |
|--------|---------|-------|
| [set-misc](set-misc/) | 0.34 | converted |
| [encrypted-session](encrypted-session/) | 0.10 | converted |
| [headers-more](headers-more/) | 0bf283ff | converted |
| [subs-filter](subs-filter/) | c6f825fa | converted |
| [brotli](brotli/) | 1.0.0rc | converted |
| [fips-check](fips-check/) | 0.1 | from scratch |
| [geoip2](geoip2/) | 3.4 | from scratch |
| [lua](lua/) | 0.10.31 | from scratch |
| [rtmp](rtmp/) | 1.2.2 | from scratch |
| [auth-spnego](auth-spnego/) | 1.1.3 | from scratch |
