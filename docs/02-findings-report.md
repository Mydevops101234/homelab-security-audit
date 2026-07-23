# Findings Report

**Scope:** Docker host running 7 services (DNS filtering, monitoring
stack, CI server, container management platform, game server, webhook
integration).
**Method:** Manual black-box review via `docker inspect`/`docker ps`
enumeration — see [`01-methodology.md`](01-methodology.md).
**Note:** All IPs, hostnames, and credential values below are sanitized
placeholders. Severity ratings follow a standard Critical/High/Medium/Low
scale based on exploitability and impact.

---

### F1 — Critical: Default/placeholder credential in production

**Service:** DNS filtering admin UI
**Evidence:** The admin password environment variable was set to the
literal example value from the software's own setup documentation
(`WEBPASSWORD=<example-value-from-docs>`), meaning anyone who has ever
read that project's README already knows the "password."
**Impact:** Full administrative access to DNS configuration for the
network — an attacker with UI access could redirect DNS resolution for
every device on the LAN.
**Recommendation:** Rotate to a random, generated credential; source it
from an environment file excluded from version control.

### F2 — Critical: Weak administrative credential

**Service:** Monitoring dashboard (Grafana)
**Evidence:** Admin password was a short dictionary-word-plus-digits
pattern — the kind of value that appears in the first few thousand
entries of any password cracking wordlist.
**Impact:** Combined with F4 below (the service was reachable beyond the
intended trust boundary), this made the dashboard a realistic brute-force
target from outside the LAN.
**Recommendation:** Rotate to a random, generated credential of
sufficient length; note that changing the environment variable alone does
not rotate an *existing* admin account's password — that requires an
explicit reset against the running application.

### F3 — High: Unauthenticated telemetry endpoints exposed beyond intended trust boundary

**Services:** Metrics collector and system-metrics exporter (no built-in
authentication by design)
**Evidence:** Both were published on all interfaces
(`0.0.0.0:<port>`/`[::]:<port>`) rather than restricted to the host or
LAN. Neither service has a login of any kind — reachability *is* the
access control.
**Impact:** Anyone who could reach the port got full host and service
metrics: hostnames, filesystem layout, running process behavior via
resource-usage patterns, internal service topology. This is
reconnaissance-grade information disclosure, and per F5, "reachable" was
not limited to the LAN.
**Recommendation:** Bind to `127.0.0.1` when the only consumer is another
service on the same Docker network (verified true here — see F6 for the
general pattern), since the internal Docker network doesn't require a
published port at all for container-to-container traffic.

### F4 — High: IPv6 dual-stack exposure bypassing IPv4 NAT protection

**Services:** Multiple, including F3's services and the monitoring
dashboard
**Evidence:** The host had a globally-routable IPv6 address in addition
to its private IPv4 address behind NAT. Several containers were bound to
`0.0.0.0` *and* `[::]`, the dual-stack equivalent of "all interfaces."
Home routers almost universally NAT IPv4 — incidentally protecting
`0.0.0.0`-bound services from the internet even with zero firewall
configuration — but typically do not NAT IPv6, since there's nothing to
translate; the address is already globally unique. Protection there
depends entirely on an explicit firewall rule that, in this case, could
not be confirmed present.
**Impact:** Services that the operator believed were "internal because
there's no port forwarding rule" could be directly reachable from the
public internet over IPv6, independent of any router-level NAT/port
forwarding configuration.
**Recommendation:** Explicitly bind services to a specific IPv4 literal
(host-loopback or LAN interface address) rather than `0.0.0.0`/leaving
the bind address implicit — this closes the IPv6 dual-stack gap as a side
effect, since a specific IPv4 address is never dual-stack. Separately,
confirm the host or router firewall actually drops unsolicited inbound
IPv6.

### F5 — High: Unnecessary published port for an internal-only dependency

**Service:** Game server's remote-console (RCON) administrative protocol
**Evidence:** RCON was published to the host (`0.0.0.0`/`[::]`), but
network topology analysis showed the only consumer (a webhook-integration
service) reached it over an **internal Docker network by service name**,
not through the published host port at all. The publish served no
function.
**Impact:** An unauthenticated-transport, plaintext-ish admin protocol
for a game server (capable of executing server commands) was exposed to
the internet for no operational reason — pure unnecessary attack surface.
**Recommendation:** Don't just restrict exposure — eliminate it.
Attach the dependent service to the same internal Docker network as its
dependency and remove the host port publish entirely. This is a stronger
fix than binding to loopback, because it removes the port from the host's
network namespace altogether rather than merely narrowing who can reach
it.

### F6 — Medium: Long-lived shared credential without a rotation procedure

**Services:** Game server (RCON host) and webhook-integration service
(RCON client)
**Evidence:** Both services used an identical static credential. This is
*architecturally correct* — it's a single client/server auth secret, not
accidental reuse of an unrelated password — but it existed as a
long-lived, human-chosen static string with no documented rotation
process.
**Impact:** Low on its own; flagged because a compromise of either
service's credential store compromises both, and there was no way to
rotate one side without manually coordinating the other.
**Recommendation:** Generate a high-entropy random value, document that
the two `.env` files must be updated together, and treat rotation as a
two-service coordinated change.

### F7 — Medium: Floating image tags instead of pinned digests

**Services:** Several across the host
**Evidence:** Images referenced by mutable tags (`latest`, `lts`) rather
than immutable digests.
**Impact:** A routine `docker compose pull && up -d` can silently
introduce a new image version — potentially with new vulnerabilities,
breaking changes, or removed features — with no record of what version
was actually running before or after.
**Recommendation:** Pin every image by digest (`image@sha256:...`).
Upgrades then become an explicit, auditable, single-line diff instead of
an implicit side effect of a routine command.

### F8 — Low / Informational: Secrets embedded in orchestration files

**Services:** Several across the host
**Evidence:** Plaintext credentials were written directly into Compose
files rather than externalized.
**Impact:** Mixes configuration (safe to version-control, share, diff)
with secret material (should never be in any of those states) in the same
file, increasing the chance a secret ends up committed to source control
or shared accidentally.
**Recommendation:** Externalize all secrets to a git-ignored `.env` file
per stack, with a committed `.env.example` template showing the required
variable names but no real values.

### F9 — Informational: Host-level control-plane access via mounted Docker socket

**Services:** CI server, container management platform
**Evidence:** Both mount `/var/run/docker.sock` into the container, which
is functionally equivalent to root access on the host — anyone who can
run a job/container through either service can create a container that
mounts the host filesystem.
**Impact:** This is a known, accepted trade-off for what these tools do
(CI pipelines building images; container management needing to manage
containers) rather than a misconfiguration to "fix." It does mean the
blast radius of a credential compromise on either service is the entire
host, which should inform how tightly access to their UIs is controlled.
**Recommendation:** Not a code fix — a policy note: treat these two
services' admin credentials as equivalent in sensitivity to root/host
credentials, and keep their attack surface (F4-style exposure) as narrow
as everything else on this list.

---

**Severity summary:** 2 Critical, 3 High, 2 Medium, 2 Informational.
See [`03-remediation.md`](03-remediation.md) for what was actually
changed for each finding and how the fix was verified.
