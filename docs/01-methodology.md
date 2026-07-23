# Methodology

The audit was black-box against my own host — I started from `docker ps`
with no prior notes on what was configured, to simulate coming in cold on
unfamiliar infrastructure (a realistic scenario for any IA/security role).

## 1. Inventory

```bash
docker ps
```

Established the full attack surface: 7 running services covering DNS
filtering, a 3-container monitoring stack, a CI server, a container
management platform, and a game server paired with a webhook receiver.

## 2. Per-container configuration review

For every running container:

```bash
docker inspect --format \
  '{{.Name}}: Image={{.Config.Image}} RestartPolicy={{.HostConfig.RestartPolicy.Name}} NetworkMode={{.HostConfig.NetworkMode}} Privileged={{.HostConfig.Privileged}}' \
  <container>
```

This surfaces three things automated scanners often miss because they
require correlating multiple fields: whether a container runs privileged,
what network it's actually attached to (as opposed to what a compose file
*claims*), and whether it was deployed via Compose at all (checked via
`com.docker.compose.project.config_files` labels — several containers here
turned out to be undocumented `docker run` deployments with no config file
anywhere on disk).

## 3. Credential exposure scan

```bash
docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' <container> \
  | grep -Ei 'pass|secret|token|key|user'
```

Container environment variables are visible to anyone with `docker`
access, which is expected — the point of this step isn't that env vars
exist, it's checking *what's in them*. This surfaced two placeholder
values that were never rotated after initial setup (one was literally the
example value copied from a project's own documentation) and a shared
credential between two services that needed to be evaluated for whether
the sharing was intentional (client/server auth) or accidental reuse.

## 4. Network exposure analysis

`docker ps` shows published ports, but the binding address matters more
than the port number:

- `127.0.0.1:PORT->PORT` — host-local only.
- `<LAN-IP>:PORT->PORT` — reachable from the local network only.
- `0.0.0.0:PORT->PORT` **and/or** `[::]:PORT->PORT` — reachable from
  *any* interface, including a public IPv6 address if the host has one.

That last point is the one this audit specifically checked for and found:

```bash
ip -4 addr show
ip route | grep default
```

Home routers almost universally NAT IPv4, which incidentally protects
`0.0.0.0`-bound services from the public internet even when the operator
never configured a firewall rule. IPv6 is different — many ISPs hand out
a globally-routable IPv6 prefix directly to the router, and routers don't
NAT IPv6 the way they do IPv4 (there's nothing to translate; the address
is already globally unique). Protection depends entirely on the router or
host actually running a stateful IPv6 firewall. A container bound to
`[::]` on a host with global IPv6 connectivity can be directly reachable
from the internet even though the "same" `0.0.0.0` binding is invisible
from outside on IPv4. This is a common blind spot because most local
testing and casual verification happens over IPv4.

## 5. Supply chain / reproducibility check

```bash
docker inspect --format '{{join .RepoDigests ", "}}' <image>
```

Checked whether images were referenced by floating tag (`latest`, `lts`)
vs. pinned digest. Floating tags mean a routine `docker compose pull` can
silently introduce a new — possibly breaking or vulnerable — image
version with no record of what changed or when.

## 6. Verification, not just remediation

After each fix, the change was verified against live state rather than
assumed correct from the config:

- Re-ran `docker ps` / `docker inspect` to confirm the actual bound
  address changed, not just the compose file.
- Queried application-level health/status APIs (e.g. a monitoring
  datasource's `/health` endpoint) to confirm the fix actually restored
  function, not just changed configuration.
- Where a fix removed a published port entirely, confirmed the
  service-to-service path that used to depend on it still worked over the
  internal network path instead.

See [`02-findings-report.md`](02-findings-report.md) for what this
process found and [`03-remediation.md`](03-remediation.md) for how each
finding was fixed and verified.
