#!/usr/bin/env bash
# broker.sh — turnkey secrets-broker agentic shell (the "easy AND secure" path).
#
# Why this exists (the MCDM conclusion in MCDM.md): open-network sandboxes leak
# an injected key, but cutting egress kills remote inference. The secrets-broker
# is the third way — the credential NEVER lives in the agent sandbox. It lives in
# a host-scoped broker container and is fetched one call at a time by tools that
# genuinely need it (results/07 pattern, now a single command).
#
#   BROKER_KEY=sk-real... bash harness/broker.sh             # interactive pi shell
#   BROKER_KEY=... bash harness/broker.sh --resolve GITHUB_TOKEN   # feed a provider/tool key
#   BROKER_KEY=... bash harness/broker.sh --single-use       # one-shot, redeem-once credential
#   bash harness/broker.sh --demo                            # scripted round-trip, no real key
#   bash harness/broker.sh --probe                           # the security probe, wired in
#
# On native Linux set SANDBOX_USER="$(id -u):$(id -g)" for bind-mount ownership.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

IMAGE=pi-sandbox
VOL=pi-home
BROKER_CNT="pi-broker-$$"
BROKER_URL="http://broker:18080/key"

MODE=shell
SINGLE_USE=0
declare -a RESOLVE=()

# --- args ---
while [ $# -gt 0 ]; do
  case "$1" in
    --shell) MODE=shell; shift 1 ;;
    --demo)  MODE=demo; shift 1 ;;
    --probe) MODE=probe; shift 1 ;;
    --single-use) SINGLE_USE=1; shift 1 ;;
    --resolve) [ $# -ge 2 ] && [ -n "$2" ] || { echo "--resolve needs a VAR name (the broker-fed env var)" >&2; exit 2; }
               RESOLVE+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' | grep .; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done

# --- credential source: the HOST side, never the sandbox ---------------------
if [ "$MODE" = demo ] || [ "$MODE" = probe ]; then
  KEY="demo-real-key-1a2b3c"
elif [ -n "${BROKER_KEY:-}" ]; then
  KEY="$BROKER_KEY"
else
  echo "BROKER_KEY not set (or use --demo). It stays on the host/broker, never in the sandbox." >&2
  exit 2
fi
# fresh per-session scope token
TOKEN="$( { command -v openssl >/dev/null 2>&1 && openssl rand -hex 16; } 2>/dev/null \
  || node -e 'process.stdout.write(require("node:crypto").randomBytes(16).toString("hex"))' )"

[ "$MODE" = demo ] && echo "==> DEMO broker; no real credential materialized."

# --- watchdog: batch runs (demo/probe) must never wedge forever --------------
# bash 3.2 on macOS can spin forever at 100% CPU in its error path when the
# launching session dies (observed live: 4.7 days, one core). Cap batch-mode
# runtime; the kill lands even if bash itself is wedged (separate process +
# SIGKILL). Interactive shells are exempt. Override with BROKER_MAX_SECS.
if [ "$MODE" != shell ]; then
  ( sleep "${BROKER_MAX_SECS:-300}"; kill -9 "$$" 2>/dev/null; docker rm -f "pi-broker-$$" >/dev/null 2>&1 ) &
  WATCHDOG=$!
fi

# --- build image (if needed) + seed persistent agent home ---------------------
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> Building $IMAGE (if needed)..."
  docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null
fi
if ! docker run --rm -v "$VOL:/data" "$IMAGE" test -f /data/settings.json 2>/dev/null; then
  echo "==> Seeding $VOL from baked /opt/pi-agent (owner pi)..."
  docker run --rm -v "$VOL:/data" --entrypoint bash "$IMAGE" \
    -c "cp -a /opt/pi-agent/. /data/ && chown -R pi /data" >/dev/null
fi

# --- start the host-scoped broker on the shared bridge -----------------------
echo "==> Starting broker container $BROKER_CNT on the Docker bridge (key holder)..."
BROKER_ARGS=(-e BROKER_TOKEN="$TOKEN" -e BROKER_KEY="$KEY" \
  -e BROKER_BIND=0.0.0.0 -e BROKER_PORT=18080)
[ "$SINGLE_USE" = 1 ] && BROKER_ARGS+=(-e BROKER_SINGLE_USE=1)
docker rm -f "$BROKER_CNT" >/dev/null 2>&1 || true   # avoid a stale same-name broker
docker run -d --rm --name "$BROKER_CNT" "${BROKER_ARGS[@]}" \
  -v "$PWD/harness/broker_server.mjs:/broker_server.mjs:ro" \
  --entrypoint node "$IMAGE" /broker_server.mjs >/dev/null
trap 'kill "${WATCHDOG:-}" 2>/dev/null || true; wait "${WATCHDOG:-}" 2>/dev/null || true; docker rm -f "$BROKER_CNT" >/dev/null 2>&1 || true' EXIT
sleep 1

echo "==> token  ${TOKEN:0:8}…  url=$BROKER_URL  mode=$MODE$([ "$SINGLE_USE" = 1 ] && echo ' (single-use)')"
if [ ${#RESOLVE[@]} -gt 0 ]; then
  echo "WARN: --resolve ${RESOLVE[*]} fetches the key at startup and materializes it in the" >&2
  echo "      sandbox env (weaker). Prefer on-demand 'fetch_key' for tool credentials." >&2
  if [ "$SINGLE_USE" = 1 ]; then
    echo "WARN: --single-use + --resolve conflicts: the startup fetch redeems the one-shot" >&2
    echo "      token, so later 'fetch_key' calls will get 410. Drop --resolve for single-use." >&2
  fi
fi

# --- inner command for the sandbox ------------------------------------------
resolve_cmd=""
for R in "${RESOLVE[@]:-}"; do
  resolve_cmd+="export $R=\"\$(fetch_key 2>/dev/null)\"; "
done

case "$MODE" in
  demo)
    CMD="K=\"\$(fetch_key 2>/dev/null)\"; if [ \"\$K\" = \"demo-real-key-1a2b3c\" ]; then echo 'DEMO-BROKER-OK: credential fetched on demand; value not logged'; else echo 'DEMO-BROKER-FAIL'; fi" ;;
  probe)
    CMD="bash /probe_broker.sh" ;;
  *)
    CMD="$resolve_cmd exec pi" ;;
esac

# --- launch the hardened sandbox, wired to the broker ------------------------
# Same hardening as `make sandbox`: non-root pi, caps dropped, no-new-privileges,
# read-only rootfs, tmpfs /tmp — but NO real key in the environment. fetch_key is
# mounted ro and the broker is reachable as `broker` via --link on the bridge.
TTY=""; [ -t 0 ] && TTY="-it"
# MOUNTS carries both bind mounts (-v) and the broker env (-e) into the sandbox
MOUNTS=(-v "$PWD:/workspace" -v "$VOL:/home/pi/.pi/agent"
        -v "$PWD/harness/fetch_key:/usr/local/bin/fetch_key:ro"
        -e BROKER_URL="$BROKER_URL" -e BROKER_TOKEN="$TOKEN")
[ "$MODE" = probe ] && MOUNTS+=(-v "$PWD/harness/probe_broker.sh:/probe_broker.sh:ro")

# shellcheck disable=SC2086
docker run --rm $TTY "${MOUNTS[@]}" --network bridge \
  --link "$BROKER_CNT:broker" \
  --user pi:pi --cap-drop ALL --security-opt no-new-privileges \
  --read-only --tmpfs /tmp \
  --entrypoint bash "$IMAGE" -c "$CMD"