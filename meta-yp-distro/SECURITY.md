# Security Policy

## Supported status

This layer is under active development (YP-M1 developer platform). Only the
latest commit on the `feat-m1-dev-platform` branch is supported; older
development commits and frozen tags (`m0.1.3` and earlier) are not patched.

## Reporting a vulnerability

Please report security issues privately to the maintainer:

  zeek.zhao <zeek.zhao@foxmail.com>

Do not open a public issue for an unpatched vulnerability. Include the affected
commit, reproduction steps, and impact. The maintainer will acknowledge within
a reasonable timeframe and coordinate a fix before public disclosure.

## Scope

- Distribution configuration and image/packagegroup recipes in this layer.
- Out-of-scope: upstream CVEs in oe-core / meta-openembedded (report upstream),
  BSP-specific issues, and vulnerabilities in pre-frozen M0 tags.

## Build-time credentials

No credentials are stored in this layer. CI tokens are injected only via
GitHub Actions secrets and are never committed to the repository.
