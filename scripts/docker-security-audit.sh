#!/usr/bin/env bash
# Read-only Docker host security audit.
#
# Checks every running container for:
#   - network exposure (bound to all interfaces vs. host/LAN-scoped)
#   - credential-looking env vars that appear to be defaults/placeholders
#   - images not pinned by digest
#   - privileged mode / docker.sock mounts
#
# Only calls `docker ps` / `docker inspect`. Makes no changes.

set -euo pipefail

RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH" >&2; exit 1; }

CONTAINERS=$(docker ps -q)
if [ -z "$CONTAINERS" ]; then
  echo "No running containers."
  exit 0
fi

echo "${BOLD}== Docker Security Audit ==${RESET}"
echo "Host: $(hostname) | $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo

warn_count=0

for id in $CONTAINERS; do
  name=$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')
  image=$(docker inspect --format '{{.Config.Image}}' "$id")
  privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "$id")

  echo "${BOLD}---- ${name} ----${RESET}"
  echo "  image: ${image}"

  # --- image pinning ---
  if [[ "$image" != *"@sha256:"* ]]; then
    echo "  ${YELLOW}[WARN]${RESET} image not pinned by digest (uses a mutable tag) — a routine pull can silently change what's running"
    warn_count=$((warn_count + 1))
  fi

  # --- privileged mode ---
  if [ "$privileged" = "true" ]; then
    echo "  ${YELLOW}[WARN]${RESET} running privileged — confirm this is required (e.g. cAdvisor-style host metrics) and not incidental"
    warn_count=$((warn_count + 1))
  fi

  # --- docker.sock mount ---
  if docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}' "$id" 2>/dev/null | grep -q '/var/run/docker.sock'; then
    echo "  ${YELLOW}[WARN]${RESET} mounts /var/run/docker.sock — functionally host-root-equivalent access"
    warn_count=$((warn_count + 1))
  fi

  # --- port exposure ---
  # Fields are tab-separated and HostIp/HostPort are kept apart, since
  # IPv6 addresses contain colons themselves and break naive colon-split
  # parsing of a combined "ip:port" string.
  port_lines=$(docker inspect --format \
    '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{$p}}	{{.HostIp}}	{{.HostPort}}
{{end}}{{end}}' "$id" 2>/dev/null || true)

  if [ -n "$port_lines" ]; then
    while IFS=$'\t' read -r containerport hostip hostport; do
      [ -z "$containerport" ] && continue
      if [ "$hostip" = "0.0.0.0" ] || [ "$hostip" = "::" ]; then
        echo "  ${RED}[EXPOSED]${RESET} ${containerport} -> ${hostip}:${hostport} (all interfaces — reachable beyond LAN on hosts with public IPv6 connectivity, regardless of IPv4 NAT/port-forwarding)"
        warn_count=$((warn_count + 1))
      else
        echo "  [scoped]  ${containerport} -> ${hostip}:${hostport}"
      fi
    done <<< "$port_lines"
  fi

  # --- credential env var scan ---
  env_lines=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" 2>/dev/null \
    | grep -Ei 'pass|secret|token|key' || true)

  if [ -n "$env_lines" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      k="${line%%=*}"
      v="${line#*=}"
      lower_v=$(echo "$v" | tr '[:upper:]' '[:lower:]')
      flag=""
      case "$lower_v" in
        *changeme*|*yourpassword*|*default*|"password"|"admin"|"admin123"|"") flag="looks like a placeholder/default value" ;;
      esac
      if [ ${#v} -lt 12 ] && [ -z "$flag" ]; then
        flag="short (${#v} chars) — check entropy"
      fi
      if [ -n "$flag" ]; then
        echo "  ${RED}[CRED]${RESET} ${k} — ${flag}"
        warn_count=$((warn_count + 1))
      else
        echo "  [cred]    ${k} is set (length ${#v}, doesn't match common placeholder patterns)"
      fi
    done <<< "$env_lines"
  fi

  echo
done

echo "${BOLD}== Summary ==${RESET}"
if [ "$warn_count" -eq 0 ]; then
  echo "${GREEN}No findings.${RESET}"
else
  echo "${YELLOW}${warn_count} item(s) flagged above.${RESET} Review each against your actual intended trust boundary —"
  echo "not every [EXPOSED]/[CRED]/[WARN] is necessarily wrong, but each should be a deliberate decision, not a default."
fi
