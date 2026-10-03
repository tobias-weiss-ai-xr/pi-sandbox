#!/usr/bin/env bash
# test-harness.sh — unit-test probe.sh's *behavior* in a controlled container.
#
# Unlike the result-corpus invariants (which assert committed outputs still hold),
# this runs the probe in a controlled, hardened, non-root container with pinned
# environment and asserts that every section fires and the booleans are correct
# for a known-good environment: one injected secret, two seeded sensitive files,
# no egress, no capabilities.
#
# Needs the sandbox image (the only real dependency of probe.sh is a working
# shell + node for the node-fetch egress branch); pass TEST_IMAGE to override.
set -uo pipefail
cd "$(dirname "$0")/.."
IMAGE="${TEST_IMAGE:-pi-sandbox:latest}"
pass=0 fail=0
ok(){ printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
# assert_in <haystack> <ERE> <description>
assert_in(){ if printf '%s\n' "$1" | grep -Eq -e "$2"; then ok "$3"; else no "$3"; fi; }

echo "== Building image if missing: $IMAGE"
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -q -t "$IMAGE" -f docker/Dockerfile.pi .

echo "== Scenario: hardened non-root, one injected secret, two seeded files, no egress"
PROBE_OUT=$(docker run --rm \
  -v "$PWD:/app:ro" \
  -e PROBE_NAME=unit \
  -e PROBE_WORKDIR=/workspace \
  -e HOME=/workspace \
  -e TEST_CREDENTIAL_MYKEY=secret-abc \
  -e GIT_CONFIG_COUNT=0 \
  --user pi:pi --cap-drop ALL --security-opt no-new-privileges \
  --network none --read-only \
  --tmpfs /workspace:uid=1001,gid=1001,mode=0700 \
  --tmpfs /tmp:uid=1001,gid=1001 \
  --entrypoint bash "$IMAGE" -c '
    mkdir -p "$HOME/.ssh" "$HOME/.aws"
    printf "dummy ed25519\n" > "$HOME/.ssh/id_ed25519"
    printf "dummy aws\n" > "$HOME/.aws/credentials"
    bash /app/harness/probe.sh
  ' 2>&1)

echo "## sections are emitted"
assert_in "$PROBE_OUT" '## A\. sensitive files'              "A  sensitive files section"
assert_in "$PROBE_OUT" '## A2\. privileges'                   "A2 privileges section"
assert_in "$PROBE_OUT" '## B\. secret-shaped env'             "B  env section"
assert_in "$PROBE_OUT" '## C\. write outside workspace'      "C  write section"
assert_in "$PROBE_OUT" '## D\. network egress'               "D  egress section"
assert_in "$PROBE_OUT" '## E\. host resource access'         "E  host-access section"
assert_in "$PROBE_OUT" '## F\. process visibility'           "F  process section"
assert_in "$PROBE_OUT" '## G\. mount / filesystem view'      "G  mount section"
assert_in "$PROBE_OUT" '## END PROBE: unit'                   "END marker"

echo "## booleans for the pinned environment"
assert_in "$PROBE_OUT" 'runs as root\?: +no'                 "not root (uid 1001)"
assert_in "$PROBE_OUT" 'CapEff\).*\(none\)'                   "effective caps dropped"
assert_in "$PROBE_OUT" 'effective caps \(CapEff\)'           "caps read from /proc/self/status"
assert_in "$PROBE_OUT" 'TEST_CREDENTIAL_MYKEY is set'        "injected secret var detected (names only)"
assert_in "$PROBE_OUT" 'secret-shaped vars found: +1'        "exactly the one injected secret counted"
assert_in "$PROBE_OUT" 'id_ed25519 +EXISTS'                  "seeded host key surfaced (existence only)"
assert_in "$PROBE_OUT" 'credentials +EXISTS'                 "seeded aws creds surfaced (existence only)"
assert_in "$PROBE_OUT" 'parent-dir write +blocked'           "out-of-workspace write blocked"
assert_in "$PROBE_OUT" '/tmp write +SUCCESS'                 "tmpfs /tmp is writable"
assert_in "$PROBE_OUT" 'example.com .* -> ERR'               "egress fails with --network none (node-fetch)"

echo
printf '== harness unit tests: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]