#!/usr/bin/env bash
# probe_broker.sh — secrets-brokering probe (poor-man's Docker Sandboxes).
# Proves the sbx pattern with plain Docker: the real credential stays on the
# host behind a scoped token; the container holds only a placeholder and pulls
# the key at runtime over one forwarded port.
#
# SAFETY: prints env-var NAMES only and booleans only — the credential value
# is never written to output (equality is checked, not echoed).
set +e

section() { printf '\n'; printf '=%.0s' {1..70}; printf '\n'; printf '## %s\n' "$1"; printf '=%.0s' {1..70}; printf '\n'; }
kv() { printf '  %-28s %s\n' "$1:" "$2"; }

printf '=%.0s' {1..70}; printf '\n'
printf '## PROBE: 07-secrets-broker (poor-man\x27s Docker Sandboxes)\n'
printf '=%.0s' {1..70}; printf '\n'
kv "run host" "$(hostname 2>/dev/null || echo n/a)"
kv "whoami" "$(whoami 2>/dev/null || id -un 2>/dev/null || echo n/a)"

# --- A. What the container env holds (names only) ---------------------------
section "A. credential env (names only, never values)"
if [ -n "${FAKE_API_KEY_PLACEHOLDER:-}" ]; then
	kv "real key present in env?" "no (placeholder only: ${FAKE_API_KEY_PLACEHOLDER##*/})"
else
	kv "real key present in env?" "no (absent entirely)"
fi
kv "secret-shaped vars in env" "$(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | grep -cE 'KEY|TOKEN|SECRET|PASSWORD|API')"

# --- B. Broker round-trip (booleans only) -----------------------------------
section "B. broker round-trip"
URL="${BROKER_URL:-http://172.17.0.1:18080/key}"
TOK="${BROKER_TOKEN:-dev-token}"
if command -v curl >/dev/null 2>&1; then
	fetched=$(curl -sf --max-time 6 -H "X-Scope-Token: $TOK" "$URL" 2>/dev/null)
else
	fetched=$(node -e 'fetch(process.argv[1],{headers:{"X-Scope-Token":process.argv[2]}}).then(r=>r.ok?r.text():"").then(t=>process.stdout.write(t)).catch(()=>{})' "$URL" "$TOK" 2>/dev/null)
fi
if [ -n "$fetched" ]; then
	kv "broker reachable" "yes"
	# equality against the host-side demo value; never echo either
	if [ "$fetched" = "demo-real-key-1a2b3c" ]; then
		kv "credential matches host demo" "yes (value not logged)"
	else
		kv "credential matches host demo" "no"
	fi
else
	kv "broker reachable" "no"
fi

printf '=%.0s' {1..70}; printf '\n'
printf '## END PROBE: 07-secrets-broker\n'
printf '=%.0s' {1..70}; printf '\n'