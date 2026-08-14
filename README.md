# pkg-oss-tests

Test suites for third-party nginx modules as packaged in [nginx/pkg-oss](https://github.com/nginx/pkg-oss).

Tests are LLM-converted from the upstream module test suites and adapted to run against the packaged builds.

These tests are not intended as an authoritative measure of full module correctness. They serve as regression tests only to check that additions to the nginx codebase do not explicitly break select third-party module functionality.

## Structure

One directory per module, containing a `t/` subdirectory of test scripts using the [nginx-tests](https://github.com/nginx/nginx-tests) library.

```
<module>/
└── t/
    └── *.t
```

## Modules

Tests are converted from the test suite shipped with the listed module version.

| Module | Version |
|--------|---------|
| [set-misc](set-misc/) | 0.34 |
| [encrypted-session](encrypted-session/) | 0.10 |
| [headers-more](headers-more/) | 0bf283ff |
| [subs-filter](subs-filter/) | c6f825fa |
| [brotli](brotli/) | 1.0.0rc |
| [fips-check](fips-check/) | 0.1 |
| [geoip2](geoip2/) | 3.4 |
| [lua](lua/) | 0.10.31 |
