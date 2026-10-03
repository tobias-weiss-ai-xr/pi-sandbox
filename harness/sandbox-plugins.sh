#!/usr/bin/env bash
# sandbox-plugins.sh — drop into an interactive pi-sandbox container that has all
# four sandbox plugins baked in (pi-saia-plugin, ponytail, caveman, rtk).
#
# Pass SAIA_API_KEY to make the saia provider usable:
#   SAIA_API_KEY=your_key bash harness/sandbox-plugins.sh
#
# Docker is required. Uses --rm (ephemeral) — use a named volume for persistence.
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE="pi-sandbox"

echo "==> Building $IMAGE (if needed)..."
docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null

MOUNTS=(-v "$PWD:/workspace")
if [ -n "${SAIA_API_KEY:-}" ]; then
  MOUNTS+=(-e "SAIA_API_KEY=$SAIA_API_KEY")
  echo "    SAIA_API_KEY provided -> saia provider available"
else
  echo "    (no SAIA_API_KEY set; saia models listed only after a key is supplied;"
  echo "     ponytail/caveman/rtk work without it)"
fi

echo "==> Starting pi+plugins in $IMAGE (Ctrl-D to exit). Run: /model saia/...  /caveman full  /ponytail lite  /rtk status"
docker run --rm -it "${MOUNTS[@]}" --entrypoint pi "$IMAGE"