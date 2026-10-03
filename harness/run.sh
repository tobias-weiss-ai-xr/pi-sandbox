#!/usr/bin/env bash
# run.sh — the *practical* way to use the pi-sandbox: bind the CURRENT project
# directory into the container and work in it, isolated as a non-root user.
#
# Why this shape (measured on this host):
#  - `-v "$PWD:/workspace"` bind-mounts the project you're in. On macOS+Colima
#    the shared dir is permissive, so non-root `pi` (uid 1001) can read AND
#    write it (verified). On native Linux, bind-mounts preserve the host UID,
#    so set $SANDBOX_USER to your uid:gid (see below).
#  - Run as non-root `pi` with all caps dropped + no-new-privileges + a
#    read-only root filesystem + tmpfs /tmp. eps carries over a CapEff of 0,
#    no host secrets, parent-of-workspace writes blocked (see
#    results/09-nonroot-hardened.txt).
#  - The agent home lives on a PERSISTENT volume `pi-home` (sessions/config
#    survive), seeded from the baked /opt/pi-agent template.
#  - Network stays ON by default (you need it for real inference); drop it with
#    `--no-network` for best isolation.
#
# Examples:
#   bash harness/run.sh                       # interactive, current dir mounted
#   SAIA_API_KEY=... bash harness/run.sh      # also make saia models usable
#   bash harness/run.sh --no-network          # max isolation (no egress)
#   bash harness/run.sh --probe               # run isolation probe in the shell
#   SANDBOX_USER="$(id -u):$(id -g)" bash harness/run.sh   # native-Linux ownership
#
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE="pi-sandbox"
VOL="pi-home"
USER_SPEC="${SANDBOX_USER:-pi:pi}"
NET_MODE=""                 # docker --network flag (default: auto bridge = on)

# --- args ---
PROBE_ONLY=0
for a in "$@"; do
  case "$a" in
    --no-network) NET_MODE="--network none" ;;
    --probe)      PROBE_ONLY=1 ;;
    *) echo "unknown arg: $a" >&2; echo "use --no-network | --probe" >&2; exit 2 ;;
  esac
done

echo "==> Building $IMAGE (if needed)..."
docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null

# --- ensure persistent agent-home volume is seeded from the baked template ---
seed_uid="${USER_SPEC%%:*}"
if ! docker run --rm -v "$VOL:/data" "$IMAGE" test -f /data/settings.json 2>/dev/null; then
  echo "==> Seeding volume $VOL from baked /opt/pi-agent (owner $seed_uid)..."
  docker run --rm -v "$VOL:/data" --entrypoint bash "$IMAGE" \
    -c "cp -a /opt/pi-agent/. /data/ && chown -R $seed_uid /data"
fi

# --- assemble run ---
MOUNTS=(-v "$PWD:/workspace" -v "$VOL:/home/pi/.pi/agent")
[ -n "${SAIA_API_KEY:-}" ] && MOUNTS+=(-e "SAIA_API_KEY=$SAIA_API_KEY")

# interactivity flag only when on a TTY (avoids macOS bash 3.2 empty-array `set -u` trip)
ITTY=""
[ -t 0 ] && ITTY="-it"

# entry: probe or interactive pi (override entrypoint + cmd only for probe)
ENTRY_AS=(); CMD_AS=()
if [ "$PROBE_ONLY" = 1 ]; then
  MOUNTS+=(-v "$PWD/harness/probe.sh:/probe.sh:ro")
  ENTRY_AS=(--entrypoint bash)
  CMD_AS=(-c 'bash /probe.sh')
fi

# run as non-root, caps dropped, read-only root, tmpfs /tmp
# shellcheck disable=SC2086
exec docker run --rm $ITTY "${MOUNTS[@]}" $NET_MODE \
  --user "$USER_SPEC" \
  --cap-drop ALL --security-opt no-new-privileges \
  --read-only --tmpfs /tmp \
  "${ENTRY_AS[@]}" "$IMAGE" "${CMD_AS[@]}"