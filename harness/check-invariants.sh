#!/usr/bin/env bash
# check-invariants.sh — assert the committed probe results still hold.
#
# Turns the results corpus into regression assertions: each method has
# grep-able invariants that must survive any future edit/rerun. Works on the
# committed files (no Docker needed), so it runs in CI even without a build.
#
# Exit non-zero if any invariant fails.
set -uo pipefail
cd "$(dirname "$0")/.."
pass=0 fail=0 warns=0

ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
# warn() — informational marker; does NOT fail the run
warn(){ printf '  \033[33mWARN\033[0m  %s\n' "$1"; warns=$((warns+1)); }
# require <file> <ERE> <description>
require() { if grep -Eq -e "$2" "$1"; then ok "$3"; else no "$3"; fi; }
# forbid  <file> <ERE> <description>
forbid()  { if grep -Eq -e "$2" "$1"; then no "$3"; else ok "$3"; fi; }

shopt -s nullglob 2>/dev/null || true

echo "## 02 — recommended: exactly one injected var, host secrets hidden, egress open"
for f in results/02-*.txt; do
  require "$f" 'secret-shaped vars found: +1' "$f: exactly 1 injected secret var"
  require "$f" 'id_rsa +missing'              "$f: host id_rsa not exposed"
  require "$f" '-> +200'                      "$f: egress is open (documented gap §3.1)"
done

echo "## 03 — leaky mounts: host secrets DO appear (the counter-example)"
for f in results/03-*.txt; do
  require "$f" 'secret-shaped vars found: +3' "$f: 3 extra env vars injected"
  require "$f" 'settings.json +EXISTS'        "$f: real settings.json leaks in"
  require "$f" '-> +200'                      "$f: egress is open"
done

echo "## 04 — hardened: no egress, out-of-workspace write blocked"
for f in results/04-*.txt; do
  forbid  "$f" '-> +200'                      "$f: no successful egress"
  require "$f" 'parent-dir write +blocked'    "$f: parent-dir write blocked"
done

echo "## 09 — non-root hardened: uid!=0, caps dropped, no secrets, writes blocked"
for f in results/09-*.txt; do
  require "$f" 'runs as root\?: +no'          "$f: not root"
  require "$f" 'CapEff\).*\(none\)'           "$f: effective caps dropped"
  require "$f" 'secret-shaped vars found: +0' "$f: zero secret-shaped vars"
  require "$f" 'parent-dir write +blocked'    "$f: parent-dir write blocked"
done

echo "## 10 — agentic smoke: hardened-root crashes (review correction), recommended runs"
for f in results/10-agentic-smoke-hardened-root.txt; do
  require "$f" 'ENOENT.*sessions'             "$f: pi crashes (read-only session dir) — known"
done
for f in results/10-agentic-smoke-recommended.txt; do
  require "$f" 'bash command'                 "$f: agent executed a shell tool"
done

echo "## 11 — exfiltration: recommended LEAKS, hardened BLOCKS"
require results/11-exfil-recommended.txt 'EXFIL_DELIVERED'        "11: recommended leaks the key"
require results/11-exfil-hardened.txt    'EXFIL_FAILED:ENETUNREACH' "11: hardened blocks egress"

echo "## 12 — sandbox develops a git repo (skeleton-research → new topic)"
for f in results/12-*.txt; do
  require "$f" 'sandbox user: pi \(uid 1001\)' "$f: ran non-root in the sandbox"
  require "$f" '[0-9]+ passed in'              "$f: project test suite passed in-box"
  require "$f" 'read on the HOST'              "$f: the in-box commit persisted to the host"
  require "$f" 'cannot push'                   "$f: no push credentials in the sandbox"
done

# --- groups added to close the coverage gap (01/05/07/08) -------------------
echo "## 01 — direct on host (no isolation): host is writable + secrets exposed"
for f in results/01-*.txt; do
  require "$f" 'parent-dir write +SUCCESS'        "$f: host writable (parent-dir write succeeds)"
  require "$f" 'example.com +.*HTTP 200'          "$f: egress reaches the internet"
  require "$f" 'secret-shaped vars found: +[1-9]' "$f: host exposes real secret vars"
done

echo "## 05 — gVisor (legion): a step tighter than plain Docker"
for f in results/05-legion-gvisor.txt; do
  require "$f" 'uname: .*gvisor'                  "05-open: ran under gVisor (runsc)"
  require "$f" 'parent-dir write +blocked'        "05-open: denies writes even on writable rootfs (novel)"
  require "$f" 'example.com .*200'                "05-open: open run keeps egress"
done
for f in results/05-legion-gvisor-hardened.txt; do
  require "$f" 'uname: .*gvisor'                  "05-hdn: ran under gVisor (runsc)"
  require "$f" 'parent-dir write +blocked'        "05-hdn: writes blocked"
  require "$f" 'example.com .*ERR'                "05-hdn: no egress"
done

echo "## 07 — secrets-broker: the real key never enters the box"
for f in results/07-*broker.txt; do
  require "$f" 'real key present in env\?: +no'   "$f: placeholder only, real key stays on the host"
  require "$f" 'secret-shaped vars in env: +[1-9]' "$f: only broker token + placeholder (no raw key)"
done

echo "## 08 — timing: container-start figure recorded"
for f in results/08-*.txt; do
  require "$f" 'container start' "$f: timing recorded"
done

# --- warnings (informational; never fail the run) --------------------------
echo "## 13 — seccomp profile + tmpfs noexec (control vs strict, same caps+network)"
for f in results/13-*-seccomp-unconfined.txt; do
  require "$f" 'Seccomp mode .*: +0'          "13-control: no seccomp filter (Seccomp 0)"
  require "$f" '/tmp +ok \(ran-from-tmp\)'   "13-control: /tmp is executable"
  require "$f" 'example.com .*-> HTTP 200'    "13-control: egress open"
done
for f in results/13-*-seccomp-strict.txt; do
  require "$f" 'Seccomp mode .*: +2'          "13-strict: seccomp filter active (Seccomp 2)"
  require "$f" '/tmp +blocked'                "13-strict: tmpfs noexec blocks /tmp execution"
  require "$f" 'example.com .*->.*(ERR)'      "13-strict: egress cut by seccomp despite open network"
  require "$f" 'node:.*ok'                    "13-strict: node still runs under the profile"
  require "$f" 'pi version: +[0-9.]'         "13-strict: pi still runs under the profile"
done

echo "## warnings — stakes lowered to surfaces, not gates"
# Timing-drift sentinel: if a re-measured container start is implausibly large
# the recorded figure no longer reflects reality (was ~0.5–3 s).
for f in results/08-*.txt; do
  max="$(grep -oE '[0-9]+\.[0-9]+ ?s' "$f" | tr -d ' s' | sort -nr | head -1)"
  if [ -n "$max" ] && awk -v v="$max" 'BEGIN{ exit !(v>300) }'; then
    warn "$f: container-start figure ${max}s looks like drift (expected ~0.5–3s)"
  fi
done

# Coverage-gap: any result file with no invariants here is a blind spot.
# Add new files deliberately by writing checks for them (or drop them from
# results/). This list is the current corpus; keep it in sync.
expected_files="
01-direct-no-isolation.txt
01-legion-direct.txt
01-macos-direct.txt
02-docker-recommended.txt
02-legion-docker-recommended.txt
02-macos-docker-recommended.txt
03-docker-leaky-mounts.txt
03-legion-docker-leaky-mounts.txt
03-macos-docker-leaky-mounts.txt
04-docker-hardened.txt
04-legion-docker-hardened.txt
04-macos-docker-hardened.txt
05-gondolin-attempt.txt
05-legion-gvisor-hardened.txt
05-legion-gvisor.txt
06-sandbox-runtime-attempt.txt
07-docker-sandboxes-sbx.txt
07-legion-secrets-broker.txt
08-macos-timing.txt
08-timing.txt
09-nonroot-hardened.txt
10-agentic-smoke-hardened-nonroot.txt
10-agentic-smoke-hardened-root.txt
10-agentic-smoke-recommended.txt
11-exfil-hardened.txt
11-exfil-recommended.txt
12-sandbox-research-repo.txt
13-macos-seccomp-strict.txt
13-macos-seccomp-unconfined.txt
"
for f in results/*.txt; do
  b="${f##*/}"
  if ! printf '%s\n' "$expected_files" | grep -Fxq "$b"; then
    warn "$f: result file has no invariants — add checks for it or document it"
  fi
done


echo
printf '== invariants: %d passed, %d failed, %d warnings ==\n' "$pass" "$fail" "$warns"
[ "$fail" -eq 0 ]