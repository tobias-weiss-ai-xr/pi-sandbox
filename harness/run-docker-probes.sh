#!/usr/bin/env bash
# run-docker-probes.sh — reproduce all Docker probe variants.
# Encodes the MSYS_NO_PATHCONV=1 workaround required on Git Bash (Windows),
# which was a real friction point: without it, "-v /probe.sh:ro" gets
# mangled to "C:/Program Files/Git/probe.sh:ro".
#
# Usage: bash harness/run-docker-probes.sh
set -euo pipefail
cd "$(dirname "$0")/.."
W="$(pwd -W)"           # Windows-style path for Docker volume mounts
IMAGE="pi-sandbox"
PROBE="$W/harness/probe.sh"

echo "Building $IMAGE (if needed)..."
docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null

run_probe() {  # $1=name $2..=docker args
  local name="$1"; shift
  echo "--- $name ---"
  MSYS_NO_PATHCONV=1 docker run --rm \
    -e "PROBE_NAME=$name" -e PROBE_WORKDIR="/workspace" \
    -v "$PROBE:/probe.sh:ro" "$@" --entrypoint bash "$IMAGE" /probe.sh \
    | tee "results/$name.txt"
}

# 02: recommended setup — workspace bind mount + named volume for agent home,
# only the needed credential passed in.
run_probe 02-docker-recommended \
  -e ANTHROPIC_API_KEY=dummy-key-not-real \
  -v "$W:/workspace" \
  -v pi-agent-home:/root/.pi/agent

# 03: leaky — mounts host ~/.pi/agent, ~/.ssh, $HOME read-only + extra env.
# Demonstrates what a careless mount setup exposes.
run_probe 03-docker-leaky-mounts \
  -e ANTHROPIC_API_KEY=dummy-key-not-real \
  -e OPENAI_API_KEY=dummy-leak \
  -e AWS_SECRET_ACCESS_KEY=dummy-leak \
  -v "$W:/workspace" \
  -v "C:/Users/Tobias:/hosthome:ro" \
  -v "C:/Users/Tobias/.pi/agent:/root/.pi/agent:ro" \
  -v "C:/Users/Tobias/.ssh:/root/.ssh:ro"

# 04: hardened — no network, read-only root, tmpfs /tmp.
run_probe 04-docker-hardened \
  -e ANTHROPIC_API_KEY=dummy \
  --network none --read-only --tmpfs /tmp \
  -v "$W:/workspace" \
  -v pi-agent-home:/root/.pi/agent

echo "Done. See results/02-*.txt, results/03-*.txt, results/04-*.txt"
