#!/usr/bin/env bash
# run.sh — use the sandbox to develop a git repo: bootstrap a new research topic
# from the `skeleton-research` template, entirely inside the pi sandbox.
#
# This is the everyday shape of the research result:
#   * the repo is bind-mounted read/write at /workspace → edits & commits persist
#   * the agent runs the project's own toolchain (python, make, pytest) in the box
#   * git identity + `safe.directory` are injected via env — the host's
#     ~/.gitconfig and ~/.ssh are NEVER mounted, so the agent can commit but
#     cannot push. Push stays a human step on the host.
#
# Usage:
#   bash examples/research-repo/run.sh --demo            [SHORT]   # scripted stand-in (no model)
#   bash examples/research-repo/run.sh --interactive     [SHORT]   # real pi TUI in the repo
#   bash examples/research-repo/run.sh --task "..."      [SHORT]   # one-shot pi -p
#
# SHORT is the topic slug (default: quantum-error-correction). The repo lands in
# scratch/<SHORT>-research (gitignored), cloned from skeleton-research on first run.
# On native Linux set SANDBOX_USER="$(id -u):$(id -g)" so the non-root user can
# write the bind mount; on macOS/Colima the default pi:pi already works.
set -euo pipefail
cd "$(dirname "$0")/../.."                     # repo root

BASE_IMAGE="pi-sandbox:latest"
IMAGE="pi-sandbox:research"                    # base + python3/make/pytest (see Dockerfile)
TEMPLATE="https://github.com/tobias-weiss-ai-xr/skeleton-research.git"
USER_SPEC="${SANDBOX_USER:-pi:pi}"
SEED_UID="${USER_SPEC%%:*}"

MODE="--demo"
SHORT="quantum-error-correction"
TASK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --demo|--interactive) MODE="$1"; shift ;;
    --task) MODE="--task"; TASK="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) SHORT="$1"; shift ;;
  esac
done
REPO="scratch/${SHORT}-research"
TOPIC_NAME="$(echo "$SHORT" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')"
TOPIC_DESC="Evidence base for ${SHORT//-/ }: curated literature, taxonomy, and auto-generated review."

echo "==> Building images (if needed)..."
docker image inspect "$BASE_IMAGE" >/dev/null 2>&1 || docker build -q -t "$BASE_IMAGE" -f docker/Dockerfile.pi .
docker build -q -t "$IMAGE" -f examples/research-repo/Dockerfile . >/dev/null

# --- seed the repo from the skeleton (first run only) ------------------------
if [ ! -d "$REPO/.git" ]; then
  echo "==> Cloning skeleton-research → $REPO"
  git clone -q --depth 1 "$TEMPLATE" "$REPO"
  git -C "$REPO" remote rename origin template
  # belt & braces: no push URL, and (crucially) no SSH key inside the sandbox
  git -C "$REPO" remote set-url --push template "disabled://no-push-credentials-in-sandbox"
fi
REPO="$(cd "$REPO" && pwd)"

# --- writable agent home (first run only) ------------------------------------
if ! docker run --rm -v pi-home:/data --entrypoint bash "$IMAGE" \
        -c 'test -f /data/settings.json' 2>/dev/null; then
  echo "==> Seeding pi-home from baked /opt/pi-agent..."
  docker run --rm -v pi-home:/data --entrypoint bash "$IMAGE" \
    -c "cp -a /opt/pi-agent/. /data/ && chown -R $SEED_UID /data"
fi

# --- git identity + ownership safety, injected via env (host repo untouched) --
GIT_ENV=(
  -e GIT_CONFIG_COUNT=4
  -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'
  -e GIT_CONFIG_KEY_1=user.name      -e GIT_CONFIG_VALUE_1="${GIT_AUTHOR_NAME:-pi-sandbox agent}"
  -e GIT_CONFIG_KEY_2=user.email     -e GIT_CONFIG_VALUE_2="${GIT_AUTHOR_EMAIL:-pi-sandbox@example.invalid}"
  -e GIT_CONFIG_KEY_3=commit.gpgsign -e GIT_CONFIG_VALUE_3=false
)
# keep test tooling from writing artifacts into the repo (read-only rootfs → use /tmp)
RUNTIME_ENV=(
  -e HYPOTHESIS_STORAGE_DIRECTORY=/tmp/hypothesis
  -e PYTHONDONTWRITEBYTECODE=1
  -e XDG_CACHE_HOME=/tmp/.cache
  -e TOPIC_NAME="$TOPIC_NAME" -e TOPIC_SHORT="$SHORT" -e TOPIC_DESC="$TOPIC_DESC"
)
SAIA_ENV=(); [ -n "${SAIA_API_KEY:-}" ] && SAIA_ENV=(-e "SAIA_API_KEY=$SAIA_API_KEY")
ITTY=""; [ -t 0 ] && ITTY="-it"

RUN=(docker run --rm $ITTY
  -v "$REPO:/workspace" -v pi-home:/home/pi/.pi/agent -w /workspace
  "${GIT_ENV[@]}" "${RUNTIME_ENV[@]}" "${SAIA_ENV[@]}"
  --user "$USER_SPEC" --cap-drop ALL --security-opt no-new-privileges
  --read-only --tmpfs /tmp)

case "$MODE" in
  --demo)
    # A scripted stand-in for the agent: exactly the commands pi's bash/tool loop
    # would run, so the mechanics are reproducible without a model key.
    echo "==> [demo] bootstrapping '$SHORT' from the skeleton, inside the sandbox"
    "${RUN[@]}" --entrypoint bash "$IMAGE" -c '
      set -e; cd /workspace
      mkdir -p "$HYPOTHESIS_STORAGE_DIRECTORY"
      echo "sandbox user: $(id -un) (uid $(id -u)) | $(python3 --version) | $(make --version | head -1)"
      # 1. give the repo its identity (the only file a human must adapt)
      sed -i "/^topic:/,/^taxonomy:/{
        s|^  name: .*|  name: \"$TOPIC_NAME\"|
        s|^  short: .*|  short: \"$TOPIC_SHORT\"|
        s|^  description: .*|  description: \"$TOPIC_DESC\"|
      }" config/taxonomy.yaml
      echo "-- topic set:"; grep -A3 "^topic:" config/taxonomy.yaml | head -4
      # 2. run the project pipeline, exactly as CI would
      echo "-- make bootstrap"; make bootstrap | tail -3
      echo "-- make validate";  make validate  | tail -1
      echo "-- make generate";  make generate  | tail -2
      echo "-- make check";     make check     | tail -2
      echo "-- make test";      make test      | tail -1
      # 3. commit from inside the sandbox
      git add -A
      git commit -q -m "Bootstrap $TOPIC_SHORT from skeleton-research" || echo "(nothing to commit)"
      echo "-- git log:"; git log --oneline -n 2
    '
    echo
    echo "==> Proof it persisted — same repo, read on the HOST:"
    git -C "$REPO" log --oneline -n 2
    git -C "$REPO" show --stat --oneline HEAD | tail -n +2 | head -12
    echo "==> The sandbox committed but cannot push: no SSH key, and the only"
    echo "    remote is the fetch-only 'template'."
    ;;
  --task)
    echo "==> [task] pi -p \"$TASK\"  (repo: $REPO)"
    "${RUN[@]}" --entrypoint pi "$IMAGE" -p "$TASK"
    echo "==> Host view after the agent ran:"; git -C "$REPO" status --short; git -C "$REPO" log --oneline -n 3
    ;;
  --interactive)
    echo "==> [interactive] pi in $REPO (ctrl-d to exit)"
    "${RUN[@]}" --entrypoint pi "$IMAGE"
    ;;
esac