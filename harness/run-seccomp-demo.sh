#!/usr/bin/env bash
# run-seccomp-demo.sh — measure a custom seccomp profile + tmpfs noexec by
# running the same probe twice (control vs strict), isolating seccomp/tmpfs
# from every other hardening flag.
#
#   control : root, normal caps, network OPEN, sec expert seccomp=unconfined,
#             plain /tmp      -> Seccomp 0, egress 200, /tmp is executable
#   strict  : root, normal caps, network OPEN, seccomp=<egress-deny.json>,
#             /tmp noexec     -> Seccomp 2, egress cut by the filter, /tmp exec
#                                 denied — while node/pi still run
#
# Usage: bash harness/run-seccomp-demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."
W="$PWD"
IMAGE="pi-sandbox"
PROBE="$W/harness/seccomp-probe.sh"
PROFILE="$W/harness/seccomp-egress-deny.json"
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      OS="$(uname -s | tr 'A-Z' 'a-z')" ;;
esac

echo "Building $IMAGE (if needed)..."
docker build -q -t "$IMAGE" -f docker/Dockerfile.pi . >/dev/null

run() {  # $1=name   $2..=docker args
  local name="$1"; shift
  echo "--- $name ---"
  docker run --rm \
    -v "$PROBE:/probe.sh:ro" \
    "$@" --entrypoint bash "$IMAGE" /probe.sh \
    | tee "results/$name.txt"
}

run "13-$OS-seccomp-unconfined" \
  --security-opt seccomp=unconfined --tmpfs "/tmp:exec,rw,nodev,nosuid,size=64m" \
  -e PROBE_NAME="seccomp control (unconfined, /tmp executable)"

run "13-$OS-seccomp-strict" \
  --security-opt seccomp="$PROFILE" \
  --tmpfs "/tmp:noexec,nosuid,size=256m" \
  -e PROBE_NAME="seccomp strict (egress-deny profile + noexec /tmp)"

echo "Done. See results/13-$OS-*.txt"