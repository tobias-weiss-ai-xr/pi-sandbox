#!/usr/bin/env bash
# probe.sh — isolation escape-attempt harness for pi sandboxing comparison.
#
# Runs a fixed set of probes that reveal what an environment exposes:
# identity, sensitive files, secret env vars, out-of-workspace writes,
# network egress, host resource access, and process visibility.
#
# SAFETY: this script NEVER prints secret contents. It reports only
# existence/size for files and NAME-ONLY presence for env vars. Safe to run
# anywhere, including on the host.
#
# Designed to run under Git Bash (MINGW) on Windows AND inside Linux
# containers. Each probe is independent and captures its own errors.

set +e
PROBE_NAME="${PROBE_NAME:-unnamed}"
WORKDIR="${PROBE_WORKDIR:-$(pwd)}"

line() { printf '=%.0s' {1..70}; printf '\n'; }
section() { printf '\n'; line; printf '## %s\n' "$1"; line; }
kv() { printf '  %-28s %s\n' "$1:" "$2"; }

section "PROBE: $PROBE_NAME"
kv "run host" "$(hostname 2>/dev/null || echo n/a)"
kv "whoami" "$(whoami 2>/dev/null || id -un 2>/dev/null || echo n/a)"
kv "id" "$(id 2>/dev/null || echo n/a)"
kv "pwd" "$(pwd)"
kv "uname" "$(uname -a 2>/dev/null || echo n/a)"
kv "ostype" "$OSTYPE"
kv "workdir" "$WORKDIR"

# --- A. Sensitive file existence (contents NEVER printed) -------------------
section "A. sensitive files (existence + size only)"
check_path() {
	local p="$1"
	if [ -e "$p" ]; then
		local sz
		sz=$(wc -c < "$p" 2>/dev/null | tr -d ' ')
		printf '  %-30s EXISTS size=%s\n' "$p" "${sz:-?}"
	else
		printf '  %-30s missing\n' "$p"
	fi
}
# Home-relative sensitive locations
for p in "$HOME/.ssh" "$HOME/.ssh/id_rsa" "$HOME/.aws" "$HOME/.aws/credentials" \
         "$HOME/.gnupg" "$HOME/.pi/agent" "$HOME/.pi/agent/settings.json" \
         "$HOME/.docker" "$HOME/.kube" "$HOME/.netrc" "$HOME/.gitconfig"; do
	check_path "$p"
done
# Container/host-typical sensitive locations
for p in "/etc/passwd" "/etc/shadow" "/var/run/docker.sock" "/proc/1/cmdline" \
         "/root/.ssh" "/run/secrets"; do
	check_path "$p"
done

# --- B. Secret-looking env vars (NAMES ONLY, never values) ------------------
section "B. secret-shaped env vars (names only)"
secret_names=0
for var in $(env 2>/dev/null | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
	case "$var" in
		*KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*PASSWD*|*CREDENTIAL*|*API*|*OAUTH*|\
		ANTHROPIC_API_KEY|OPENAI_API_KEY|AWS_*|GH_*|GITHUB_*|NPM_*|SBX_*)
			printf '  %s is set\n' "$var"
			secret_names=$((secret_names + 1))
			;;
	esac
done
kv "secret-shaped vars found" "$secret_names"

# --- C. Out-of-workspace write attempt --------------------------------------
section "C. write outside workspace"
target="/tmp/pi-probe-write-$$"
if printf 'probe' > "$target" 2>/dev/null; then
	printf '  %-30s SUCCESS (wrote %s)\n' "/tmp write" "$target"
	rm -f "$target" 2>/dev/null
else
	printf '  %-30s blocked\n' "/tmp write"
fi
# Try writing to the parent of the workdir (host escape attempt)
parent="$(dirname "$WORKDIR")"
target2="$parent/.pi-probe-escape-$$"
if printf 'probe' > "$target2" 2>/dev/null; then
	printf '  %-30s SUCCESS (wrote %s)\n' "parent-dir write" "$target2"
	rm -f "$target2" 2>/dev/null
else
	printf '  %-30s blocked\n' "parent-dir write"
fi

# --- D. Network egress ------------------------------------------------------
section "D. network egress"
probe_net() {
	local label="$1" url="$2"
	if command -v curl >/dev/null 2>&1; then
		code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$url" 2>/dev/null)
		printf '  %-22s %s -> HTTP %s (curl)\n' "$label" "$url" "${code:-fail}"
	elif command -v wget >/dev/null 2>&1; then
		if wget -q --spider --timeout=6 "$url" 2>/dev/null; then
			printf '  %-22s %s -> reachable (wget)\n' "$label" "$url"
		else
			printf '  %-22s %s -> unreachable (wget)\n' "$label" "$url"
		fi
	elif command -v node >/dev/null 2>&1; then
		# node 18+ has global fetch; used in slim containers without curl/wget
		local res
		res=$(node -e 'fetch(process.argv[1],{method:"GET"}).then(r=>process.stdout.write(String(r.status))).catch(e=>process.stdout.write("ERR:"+e.code))' "$url" 2>/dev/null)
		printf '  %-22s %s -> %s (node-fetch)\n' "$label" "$url" "${res:-fail}"
	else
		printf '  %-22s %s -> no curl/wget/node\n' "$label" "$url"
	fi
}
probe_net "example.com" "https://example.com"
probe_net "anthropic" "https://api.anthropic.com"
probe_net "metadata AWS" "http://169.254.169.254/latest/meta-data/"

# --- E. Host resource access (containers) -----------------------------------
section "E. host resource access"
check_path "/var/run/docker.sock"
check_path "/proc/1/cmdline"
if [ -r /proc/1/cmdline ]; then
	printf '  /proc/1/cmdline readable: %s\n' \
		"$(tr '\0' ' ' < /proc/1/cmdline 2>/dev/null | cut -c1-60)"
fi
# Can we see the host docker daemon?
if command -v docker >/dev/null 2>&1; then
	printf '  docker CLI present on PATH\n'
else
	printf '  docker CLI absent\n'
fi

# --- F. Process visibility --------------------------------------------------
section "F. process visibility"
if command -v ps >/dev/null 2>&1; then
	printf '  visible processes: %s\n' "$(ps -e 2>/dev/null | wc -l | tr -d ' ')"
	printf '  sample: %s\n' "$(ps -e 2>/dev/null | head -4 | tail -3 | tr '\n' '|')"
else
	printf '  ps unavailable\n'
fi

# --- G. Host filesystem mount visibility (containers) -----------------------
section "G. mount / filesystem view"
if command -v mount >/dev/null 2>&1; then
	mount 2>/dev/null | head -8 | while IFS= read -r m; do printf '  %s\n' "$m"; done
else
	printf '  mount unavailable\n'
fi
kv "disk free (workdir)" "$(df -h "$WORKDIR" 2>/dev/null | tail -1 | tr -s ' ')"

line
printf '## END PROBE: %s\n' "$PROBE_NAME"
line
