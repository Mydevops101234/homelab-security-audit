# Homelab Docker Security Audit & Remediation

A case study documenting a real security audit and remediation I performed
on my personal homelab: a Docker host running DNS filtering, a monitoring
stack, a CI server, a container-management platform, and a game server
integrated with a third-party webhook.

This isn't a synthetic lab exercise — it's the actual process I used to
find, prioritize, and fix real misconfigurations on infrastructure I run
day to day. All IPs, hostnames, and credentials in this repo are sanitized
placeholders; the vulnerability classes, root causes, and fixes are real.

## Skills demonstrated

- **Exposure analysis**: enumerating what's actually reachable and from
  where - including a dual-stack IPv4/IPv6 blind spot where several
  services were reachable from the public internet over IPv6 despite
  being "protected" by IPv4 NAT.
- **Credential hygiene**: finding placeholder/default credentials left in
  production, and moving secrets out of version-controlled config into
  environment-based injection.
- **Least privilege / network segmentation**: re-architecting a service
  dependency to use internal container-to-container networking instead of
  a publicly-published admin port, eliminating an entire attack surface
  rather than just restricting it.
- **Supply chain**: auditing for floating image tags (`latest`, `lts`) and
  pinning to immutable digests.
- **Root cause investigation**: diagnosing a monitoring stack that was
  silently failing (broken dashboard, unresolved datasource references,
  stale metric names after an upstream exporter's breaking change) via
  systematic API-level introspection rather than guesswork.
- **Automation**: a reusable, read-only Bash script that codifies the
  manual audit steps so the check can be re-run on any Docker host.

## Layout

| Path | What it is |
|---|---|
| [`docs/01-methodology.md`](docs/01-methodology.md) | How the audit was performed — the enumeration approach, not just the findings |
| [`docs/02-findings-report.md`](docs/02-findings-report.md) | Findings, ranked by severity, in a standard risk-report format |
| [`docs/03-remediation.md`](docs/03-remediation.md) | What changed, before/after, and how each fix was verified |
| [`docs/architecture.md`](docs/architecture.md) | Network segmentation diagram before and after |
| [`examples/`](examples) | Sanitized, parameterized Docker Compose configs reflecting the post-remediation state |
| [`scripts/docker-security-audit.sh`](scripts/docker-security-audit.sh) | Standalone read-only script that automates the exposure/credential/pinning checks from the audit |

## Try the audit script

```bash
./scripts/docker-security-audit.sh
```

Read-only - it only runs `docker inspect`/`docker ps` against the local
Docker daemon and prints findings. It doesn't modify anything.
