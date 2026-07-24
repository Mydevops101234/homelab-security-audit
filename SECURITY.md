# Security Policy

This repo is a documentation/case-study project (a security audit
writeup plus one standalone script), not a versioned application with
ongoing releases, so the usual "Supported Versions" table doesn't apply.
Here's what does:

## Scope

- **`scripts/docker-security-audit.sh`** — the only executable code here.
  It's read-only (only calls `docker ps`/`docker inspect`, never writes
  or modifies anything), but a bug in its detection logic is still worth
  reporting — a false "not exposed" or "not a placeholder" result would
  undermine the point of the tool. This is the main thing worth filing an
  issue over.
- **`examples/*/docker-compose.yml`** — reference configs illustrating the
  fixes described in `docs/`. They intentionally use placeholder image
  digests (`REPLACE_WITH_CURRENT_DIGEST`) and aren't meant to be deployed
  as-is.
- **`docs/`, `README.md`** — writeup, not code. All IPs, hostnames, and
  credentials in them are sanitized placeholders, not live infrastructure
  details.

## Reporting a Vulnerability

For a false negative or logic bug in `docker-security-audit.sh`, please
open a GitHub issue — public is fine, since it's a bug in detection logic,
not a live secret.

For anything you'd rather report privately, reach out via my GitHub
profile. I'll acknowledge reports within a few days and credit the report
in the fix commit unless you'd prefer to stay anonymous.
