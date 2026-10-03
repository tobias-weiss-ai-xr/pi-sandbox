#!/usr/bin/env bash
# seccomp-probe.sh — isolate the effect of a custom seccomp profile + tmpfs
# noexec apart from everything else that the hardened config changes.
#
# Run the SAME script twice, two ways:
#   control : --security-opt seccomp=unconfined --tmpfs /tmp
#             (root, normal caps, network open)  -> Seccomp 0, egress open, exec ok
#   strict  : --security-opt seccomp=<egress-deny.json> --tmpfs /tmp:noexec,nosuid,size=256m
#             (root, normal caps, network open)  -> Seccomp 2, egress blocked by
#              seccomp even though the network is open, /tmp not executable
#
# The point: egress can be cut by a syscall filter, not only by --network none;
# and tmpfs noexec kills /tmp-file execution for persistence. Both while node/pi
# still run — a hardened profile need not be a toaster.
#
# SAFETY: prints only identities/status, never secret contents.

set +e
PROBE_NAME="${PROBE_NAME:-seccomp}"
line(){ printf '=%.0s' {1..70}; printf '\n'; }
section(){ printf '\n'; line; printf '## %s\n' "$1"; line; }
kv(){ printf '  %-28s %s\n' "$1:" "$2"; }

section "PROBE: $PROBE_NAME"
kv "whoami" "$(whoami 2>/dev/null || id -un 2>/dev/null)"
kv "id" "$(id 2>/dev/null)"
kv "uname" "$(uname -sr 2>/dev/null)"

# Seccomp filter mode: 0 = none, 2 = filter present
sec=$(awk '/^Seccomp:/{print $2}' /proc/self/status 2>/dev/null)
sec=$(printf '%s' "$sec" | tr -d ' ')
kv "Seccomp mode (0=none, 2=filter)" "${sec:-n/a}"

# A2. caps (should be Docker defaults here — cap-drop is NOT used, so any
# difference from control is attributable to the profile/tmpfs alone)
cap=$(awk '/^CapEff:/{print $2}' /proc/self/status 2>/dev/null | tr -d ' ')
kv "effective caps (CapEff)" "${cap:-n/a}"

section "C. writes + exec in /tmp"
w=/tmp/pi-seccomp-write-$$
if printf 'probe' > "$w" 2>/dev/null; then
  printf '  %-24s SUCCESS\n' "/tmp write"
  rm -f "$w" 2>/dev/null
else
  printf '  %-24s blocked\n' "/tmp write"
fi
x=/tmp/pi-seccomp-exec-$$
if printf '#!/bin/sh\necho ran-from-tmp\n' > "$x" 2>/dev/null && chmod +x "$x" 2>/dev/null; then
  if out=$("$x" 2>&1); then
    printf '  %-24s %s\n' "exec from /tmp" "ok ($out)"
  else
    printf '  %-24s blocked (%s)\n' "exec from /tmp" "$(printf '%s' "$out")"
  fi
  rm -f "$x" 2>/dev/null
else
  printf '  %-24s blocked (could not create/chmod)\n' "exec from /tmp"
fi

section "D. network egress (node fetch; network is OPEN in both runs)"
egress_for(){ # $1=label $2=url
  local res
  res=$(node -e 'fetch(process.argv[1]).then(r=>process.stdout.write("HTTP "+r.status)).catch(e=>process.stdout.write("ERR"+(e.cause&&e.cause.code?" "+e.cause.code:" "+(e.code||""))))' "$2" 2>/dev/null)
  printf '  %-22s %s -> %s\n' "$1" "$2" "${res:-fail}"
}
egress_for "example.com" "https://example.com"
egress_for "anthropic" "https://api.anthropic.com"

section "F. does the toolchain still run under the profile?"
if node -e 'process.stdout.write("node " + process.version)' >/dev/null 2>&1; then
  kv "node" "$(node -e 'process.stdout.write(process.version)' 2>/dev/null) ok"
else
  kv "node" "blocked/failed"
fi
if pi --version >/dev/null 2>&1; then
  kv "pi version" "$(pi --version 2>/dev/null | tr -d '\r' )"
else
  kv "pi version" "blocked/failed"
fi

line
printf '## END PROBE: %s\n' "$PROBE_NAME"
line