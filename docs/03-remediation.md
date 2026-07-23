# Remediation

Each finding from [`02-findings-report.md`](02-findings-report.md) was
fixed and independently verified against live state — not just assumed
correct because the config file changed.

## F1 / F2 — Credential rotation

Generated random, high-entropy replacement credentials and moved them out
of the Compose files into git-ignored `.env` files (see F8). For the
monitoring dashboard, the fix required an extra step beyond editing the
environment variable: the application only reads that variable to seed a
*brand-new* admin account, so an already-provisioned account needed an
explicit password reset against the running service. Verified by
resetting the password and confirming an authenticated API health check
succeeded with the new credential — not just that the container restarted
without errors.

## F3 / F4 — Rebinding to the correct trust boundary

| Service | Before | After |
|---|---|---|
| Metrics collector | `0.0.0.0` / `[::]` | `127.0.0.1` (only consumed internally — see F5's pattern) |
| System-metrics exporter | `0.0.0.0` / `[::]` | `127.0.0.1` |
| Monitoring dashboard | `0.0.0.0` / `[::]` | Specific LAN IPv4 literal |
| CI server, container management UI | `0.0.0.0` / `[::]` | Specific LAN IPv4 literal |

Binding to a specific IPv4 address rather than the wildcard closes the
IPv6 dual-stack gap as a side effect — a literal IPv4 address is never
dual-stack, so there's no `[::]` equivalent to accidentally publish
alongside it.

**Verified** by re-inspecting each container's live port bindings after
recreation (`docker inspect`, not just re-reading the Compose file) and
confirming the bound address matched intent.

## F5 — Removing a port instead of restricting it

Network topology review showed the RCON-consuming service and the game
server were already on a shared, isolated Docker network, reachable from
each other by container hostname. The host port publish for RCON was
providing zero function for the actual dependency — it was pure exposure.

Fix: dropped the host port publish entirely. The dependent service
continues to reach RCON at `<container-hostname>:<port>` over the
internal Docker network — no host-level network path exists for it at
all anymore.

**Verified** two ways: confirmed the port no longer appears in
`docker ps`/`docker inspect` port bindings at all, and confirmed the
dependent service's authenticated integration (webhook → RCON command)
still functioned end-to-end after the change.

## F6 — Coordinated credential rotation

Generated one new high-entropy value and updated both services' `.env`
files together, with an explicit comment in each documenting that the
two must be changed as a pair and why (client/server auth, not
incidental reuse).

## F7 — Digest pinning

Replaced every floating tag reference with the exact digest currently
deployed (`docker inspect --format '{{join .RepoDigests ", "}}' <image>`
against the already-running container, rather than guessing a version
number), so the pin reflects what was actually tested — not an assumed
"latest stable."

## F8 — Externalizing secrets

For every stack: added a `.env` (git-ignored, real values) and
`.env.example` (committed, placeholder values) pair, and switched Compose
files to reference `${VAR}` instead of literal secrets. Added a
`.gitignore` per stack so `.env` can never be committed by accident.

## F9 — Documented, not code-fixed

No configuration change — this was a scope/awareness finding. Documented
in the findings report so it factors into future access-control decisions
for those two services.

## Bonus: root-cause debugging during remediation

While restricting the monitoring dashboard's exposure, its container
dashboard was found to be silently broken — showing "No data" across
every panel. This wasn't part of the original security scope, but a
monitoring stack that silently fails to monitor is its own risk (you
can't detect what you can't see), so it was investigated and fixed:

1. **Datasource pointed at a stale hardcoded container IP** instead of
   the stable internal DNS service name — a classic failure mode after
   any container recreate reassigns internal IPs. Fixed by repointing to
   the service name, verified via the datasource's own `/health` endpoint
   returning a successful query result, not just "saved without error."
2. **A container-metrics collector was never deployed**, so an entire
   class of dashboard panels had no data source at all. Added it,
   configured Prometheus to scrape it, and verified real per-container
   metric series were flowing before considering it done.
3. **~19 dashboard queries referenced metric names from an old exporter
   version** (a naming scheme the upstream project changed years ago).
   Rather than patch each panel by hand, wrote a script to programmatically
   rewrite every affected query expression via the dashboard's JSON API,
   then re-verified via the dashboard's own query engine (not just raw
   metrics-database queries) that each fixed expression returned data
   end-to-end.
4. A second pass surfaced that most panels referenced an **unresolved
   template placeholder** for their datasource (`${DS_PROMETHEUS}`) that
   had never been substituted for a real datasource ID — a leftover from
   an incomplete dashboard import. Found by diffing which panels worked
   against which datasource reference they used, and fixed the same way:
   programmatic rewrite + API-level verification, not a guess-and-check
   loop through the UI.

This is included because "the fix looks right in the config" and "the fix
actually works" are different claims, and the second one requires
verification — the same discipline as the port-binding and credential
fixes above.
