#!/usr/bin/env bash
# check-sandbox-plugins.sh — verify pi-saia-plugin, ponytail, rtk, caveman are
# installed and load cleanly inside the pi-sandbox image.
#
# Runs a fresh, ephemeral pi-sandbox container (no persistent agent home volume,
# so it exercises the baked-in /root/.pi/agent). Prints PASS/FAIL per plugin.
#
# Usage: bash harness/check-sandbox-plugins.sh
set -uo pipefail
cd "$(dirname "$0")/.."
IMAGE="pi-sandbox"

echo "==> Building $IMAGE (if needed)..."
docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null
echo

# The whole check runs inside ONE ephemeral container.
docker run --rm --entrypoint bash "$IMAGE" -c '
set -uo pipefail
PASS=0; FAIL=0
ok(){   printf "  \033[32mPASS\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad(){  printf "  \033[31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== 1. pi list shows all four packages =="
LIST=$(pi list 2>&1)
for p in pi-saia-plugin opencode-ponytail pi-caveman "@sherif-fanous/pi-rtk"; do
  echo "$LIST" | grep -q "$p" && ok "package registered: $p" || bad "package registered: $p"
done
echo "$LIST" | grep -q "pi-saia-plugin"   && grep -q "^  npm:opencode-ponytail" <<<"$LIST" 2>/dev/null || true

echo
echo "== 2. startup has no extension load errors =="
SAIA_API_KEY=dummy PI_OFFLINE=1 pi --list-models >/tmp/models.out 2>/tmp/startup.err
if rg -qi "failed to load extension|error:" /tmp/startup.err; then
  bad "extension load errors present:"; cat /tmp/startup.err | sed "s/^/      /" | head -20
else
  ok "no extension load errors"
fi

echo
echo "== 3. pi-saia-plugin: SAIA provider + models register =="
N=$(grep -c "^saia " /tmp/models.out 2>/dev/null || echo 0)
if [ "${N:-0}" -ge 10 ]; then
  ok "SAIA models registered ($N distinct saia model/alias rows)"
else
  bad "SAIA models registered (got $N)"; grep -i saia /tmp/models.out | head -3 | sed "s/^/      /"
fi

echo
echo "== 4. ponytail / caveman / rtk extensions load individually =="
CHECK(){
  local name="$1"; local ext="$2"
  if [ -f "$ext" ]; then
    out=$(PI_OFFLINE=1 pi -ne -e "$ext" --list-models 2>&1)
    if rg -qi "failed to load extension" <<<"$out"; then
      bad "extension loads: $name"; echo "$out" | rg -i "failed" | head -2 | sed "s/^/      /"
    else
      ok "extension loads: $name"
    fi
    # newer opencode-ponytail ships an extension *directory*; handle that too
  elif [ -d "$ext" ]; then
    out=$(PI_OFFLINE=1 pi -ne -e "$ext" --list-models 2>&1)
    if rg -qi "failed to load extension" <<<"$out"; then
      bad "extension loads (dir): $name"; echo "$out" | rg -i "failed" | head -2 | sed "s/^/      /"
    else
      ok "extension loads (dir): $name"
    fi
  else
    bad "extension file missing: $name ($ext)"
  fi
}
npmroot=/root/.pi/agent/npm/node_modules
CHECK "opencode-ponytail" "$npmroot/opencode-ponytail" # -e accepts package dirs
CHECK "pi-caveman" "$npmroot/pi-caveman"
CHECK "@sherif-fanous/pi-rtk" "$npmroot/@sherif-fanous/pi-rtk"

echo
echo "== done: $PASS passed, $FAIL failed =="
exit $FAIL
'