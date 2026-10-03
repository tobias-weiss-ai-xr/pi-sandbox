#!/usr/bin/env bash
# smoke-agentic.sh — END-TO-END agentic smoke test per sandbox configuration.
#
# probe.sh measures the *harness*, never the product. This runs pi itself as an
# agent on a concrete tool-using task under each config and asserts the artifact
# pi writes. Task: count top-level .md in /workspace and write that number to
# /workspace/scratch/smoke-<cfg>.txt via pi's bash tool. Fixture count is
# constant (same mounted workspace), so PASS is reproducible.
#
# Configs:
#   recommended      — net open, root, baked plugin home (saia available)
#   hardened-root    — network none, read-only root, tmpfs /tmp (report's 04)
#   hardened-nonroot — uid 1001 + --cap-drop ALL + no-new-privileges + ro +tmpfs
#
# Needs SAIA_API_KEY (a real remote model). The network-none configs are
# expected to FAIL model fetch and produce NO artifact — that failure is itself
# the finding (hardened network-none cannot drive a remote-model agent).
set +e
cd "$(dirname "$0")/.."
MODEL="${SMOKE_MODEL:-saia/meta-llama-3.1-8b-instruct}"
EXPECTED="$(ls -1 ./*.md 2>/dev/null | wc -l | tr -d ' ')"

run_one() {  # $1=cfg  $2=init-cmd(optional "cmd && ")  rest=docker extra args
  local cfg="$1"; shift
  local init="$1"; shift
  local out="results/10-agentic-smoke-$cfg.txt"
  mkdir -p scratch
  local task="Use the bash tool. Run: mkdir -p /workspace/scratch. Count how many top-level markdown (.md) files are in /workspace and write ONLY that number (plain digits, no words) to /workspace/scratch/smoke-$cfg.txt. Actually run the shell command to count; do not guess."
  echo "--- [$cfg] pi agentic (model=$MODEL) ---"
  (
    docker run --rm "$@" -e SAIA_API_KEY="$SAIA_API_KEY" -v "$PWD:/workspace" \
      --entrypoint bash pi-sandbox -c \
      "${init}pi --model '$MODEL' -p \"$task\"" > "$out" 2>&1
  ) &
  local pid=$! n=0
  while kill -0 "$pid" 2>/dev/null; do
    n=$((n+2)); [ "$n" -gt 150 ] && { kill "$pid" 2>/dev/null; echo "(timed out after ~150s)" >> "$out"; break; }
    sleep 2
  done
  wait "$pid" 2>/dev/null
  local art="scratch/smoke-$cfg.txt" got
  if [ -f "$art" ]; then
    got="$(tr -d '[:space:]' < "$art")"
    if [ "$got" = "$EXPECTED" ]; then
      printf '  RESULT %-16s PASS      (artifact=%s matches fixture=%s)\n' "$cfg" "$got" "$EXPECTED"
    else
      printf '  RESULT %-16s PARTIAL   (artifact=%s != fixture=%s)\n' "$cfg" "$got" "$EXPECTED"
    fi
  else
    printf '  RESULT %-16s NO-ARTIFACT (agent made no file; %s)\n' "$cfg" "$out"
  fi
  rm -f "$art"
}

[ -n "${SAIA_API_KEY:-}" ] || { echo "SAIA_API_KEY required (real remote model)"; exit 2; }

run_one recommended ""   # baked plugin home (saia present), net open, root
run_one hardened-root "" --network none --read-only --tmpfs /tmp
run_one hardened-nonroot "cp -a /opt/pi-agent/. /home/pi/.pi/agent/ && " \
  --user pi:pi --cap-drop ALL --security-opt no-new-privileges \
  --network none --read-only --tmpfs /tmp \
  --tmpfs /home/pi/.pi/agent:uid=1001,gid=1001

echo "Done. Raw logs: results/10-agentic-smoke-*.txt"