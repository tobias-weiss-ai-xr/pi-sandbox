#!/usr/bin/env bash
# run-docker-probes-macos.sh — reproduce the Docker probe variants on macOS.
#
# The original run-docker-probes.sh encodes two Windows/Git-Bash specifics that
# don't apply here: `pwd -W` (Windows-style path for volume mounts) and
# MSYS_NO_PATHCONV=1 (Git Bash path mangling). On macOS we use plain `pwd` and
# derive the leaky mounts from $HOME dynamically (the Windows version hard-coded
# "C:/Users/Tobias").
#
# Usage: bash harness/run-docker-probes-macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."
W="$PWD"
IMAGE="pi-sandbox"
PROBE="$W/harness/probe.sh"

echo "Building $IMAGE (if needed)..."
docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null

run_probe() {  # $1=name $2..=docker args
  local name="$1"; shift
  echo "--- $name ---"
  docker run --rm \
    -e "PROBE_NAME=$name" -e PROBE_WORKDIR="/workspace" \
    -v "$PROBE:/probe.sh:ro" "$@" --entrypoint bash "$IMAGE" /probe.sh \
    | tee "results/$name.txt"
}

# 02: recommended setup — workspace bind mount + named volume for agent home,
# only the needed credential passed in.
run_probe 02-macos-docker-recommended \
  -e ANTHROPIC_API_KEY=dummy-key-not-real \
  -v "$W:/workspace" \
  -v pi-agent-home:/root/.pi/agent

# 03: leaky — mounts host ~/.pi/agent, ~/.ssh, $HOME read-only + extra env.
# Demonstrates what a careless mount setup exposes (docs' #1 warning). macOS
# host user is `weissto` with HOME=/Users/weissto; the ssh key is id_ed25519.
run_probe 03-macos-docker-leaky-mounts \
  -e ANTHROPIC_API_KEY=dummy-key-not-real \
  -e OPENAI_API_KEY=dummy-leak \
  -e AWS_SECRET_ACCESS_KEY=dummy-leak \
  -v "$W:/workspace" \
  -v "$HOME:/hosthome:ro" \
  -v "$HOME/.pi/agent:/root/.pi/agent:ro" \
  -v "$HOME/.ssh:/root/.ssh:ro"

# 04: hardened — no network, read-only root, tmpfs /tmp.
run_probe 04-macos-docker-hardened \
  -e ANTHROPIC_API_KEY=dummy \
  --network none --read-only --tmpfs /tmp \
  -v "$W:/workspace" \
  -v pi-agent-home:/root/.pi/agent

echo "Done. See results/02-macos-*.txt, results/03-macos-*.txt, results/04-macos-*.txt"