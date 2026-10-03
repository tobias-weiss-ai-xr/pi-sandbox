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
pass=0 fail=0

ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
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

echo
printf '== invariants: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]