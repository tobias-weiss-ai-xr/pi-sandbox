# Example — develop a git repo inside the sandbox

Bootstrap a **new research topic** from
[`skeleton-research`](https://github.com/tobias-weiss-ai-xr/skeleton-research)
— entirely inside the pi sandbox. The agent edits the repo, runs the project's
own pipeline and test suite, and commits; the change persists to the host, while
your **push credentials never enter the container**.

This is the everyday shape of the [research result](../../REPORT.md): hand the
agent a repo and a model, but keep the two things you never give it — your
credentials and an open path to exfiltrate the key.

## Run it

```bash
# scripted stand-in for the agent — reproducible, no model key needed
bash examples/research-repo/run.sh --demo quantum-error-correction

# hand the same repo to the real agent
export SAIA_API_KEY=...
bash examples/research-repo/run.sh --interactive quantum-error-correction   # pi TUI
bash examples/research-repo/run.sh --task "add a decoder category and regenerate" quantum-error-correction
```

`--demo` is the reproducible path: it runs exactly the shell commands pi's tool
loop would run, so you can see the mechanics and the evidence without a model.
The `--task` / `--interactive` modes point the real agent at the same repo.

Captured evidence: [`results/12-sandbox-research-repo.txt`](../../results/12-sandbox-research-repo.txt).

## What happens

```
clone skeleton-research → scratch/<topic>-research      (host, once)
  edit config/taxonomy.yaml  (name / short / description)
  make bootstrap    # give the repo its identity: README, docs, CITATION
  make validate     # schema-check config + papers.yaml
  make generate     # README, statistics, reports, bibtex
  make check        # fail if generated outputs are stale (the CI gate)
  make test         # 157 pytest cases
  git commit        # ✅ commits land in the host repo
  git push          # ❌ no SSH key, fetch-only remote → stays a human step
```

## Why the sandbox (and what it costs)

**The payoff.** The agent gets a real toolchain and a writable repo, but the
container has no `~/.ssh`, no `~/.gitconfig`, and the only git remote is a
fetch-only `template`. So the worst case is bad commits you review — not a
pushed exfiltration. (Contrast with the recommended open-network setup in the
[threat model](../../THREAT_MODEL.md), where the injected key *is* reachable.)

**Cost 1 — the image needs the project's toolchain.** The base `pi-sandbox`
image is node-based; a research repo needs Python. Hence the derived image:

```dockerfile
FROM pi-sandbox:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-yaml python3-requests python3-feedparser \
      python3-pytest python3-hypothesis make && rm -rf /var/lib/apt/lists/*
```

**Cost 2 — test tooling writes into the repo.** With a read-only rootfs,
`hypothesis` (used by the suite) tried to drop `.hypothesis/` into the workspace
and it got swept into `git add -A`. Fixed by pointing its store at the tmpfs:

```bash
-e HYPOTHESIS_STORAGE_DIRECTORY=/tmp/hypothesis -e PYTHONDONTWRITEBYTECODE=1 -e XDG_CACHE_HOME=/tmp/.cache
```

**Cost 3 — git identity.** The container has no `~/.gitconfig`, so commits would
fail. Instead of writing config into the mounted repo (which would pollute the
host), identity and `safe.directory` are injected as env vars:

```bash
-e GIT_CONFIG_COUNT=4 \
-e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
-e GIT_CONFIG_KEY_1=user.name      -e GIT_CONFIG_VALUE_1='pi-sandbox agent' \
-e GIT_CONFIG_KEY_2=user.email     -e GIT_CONFIG_VALUE_2='pi-sandbox@example.invalid' \
-e GIT_CONFIG_KEY_3=commit.gpgsign -e GIT_CONFIG_VALUE_3=false
```

## Adapting to your own repo

Point `REPO` at any checkout by running the container by hand (or copy `run.sh`):
mount it at `/workspace`, add `--user pi:pi`, drop caps, keep the rootfs
read-only with a tmpfs `/tmp`, and reuse the three env groups above. Bump the
`Dockerfile` with whatever your project's toolchain needs. On native Linux set
`SANDBOX_USER="$(id -u):$(id -g)"` so the non-root user can write the bind mount.

## Files

| file | purpose |
|------|---------|
| `Dockerfile` | `pi-sandbox:latest` + python3/make/pytest → `pi-sandbox:research` |
| `run.sh` | clone/seed the repo, launch the sandbox (`--demo`/`--task`/`--interactive`) |
| `../../results/12-sandbox-research-repo.txt` | captured `--demo` transcript |
