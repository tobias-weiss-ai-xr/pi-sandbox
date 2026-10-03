# pi-sandbox

[![ci](https://github.com/tobias-weiss-ai-xr/pi-sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/tobias-weiss-ai-xr/pi-sandbox/actions/workflows/ci.yml)

Empirical comparison of the ways to sandbox **Pi**'s model-generated commands —
measured with a fixed escape-attempt probe on three hosts, plus a product-function
test and a real exfiltration test. Raw outputs are committed under `results/`.
Analysis in [`REPORT.md`](REPORT.md); adversaries in [`THREAT_MODEL.md`](THREAT_MODEL.md).

## Quick start

```bash
make help        # list all targets
make image       # build pi-sandbox:latest
make verify      # assert the 4 bundled plugins load (9 checks)
make test        # unit-test probe.sh behavior in a controlled container (19 checks)
make check       # assert committed results still satisfy their invariants (55 checks; no Docker)
make sandbox     # interactive non-root sandbox with the current dir mounted
make example     # develop a skeleton-research repo inside the sandbox (demo, no model)
```

Requirements: Docker (`docker build`/`docker run`). On macOS the tested backend is
**Colima**; on Windows, Docker Desktop with WSL2. `make check` needs nothing but a shell.

## Findings at a glance

> **Two results that reframe the usual advice**
> 1. The *recommended* open-network setup is safe only against *accidental* leaks — a
>    deliberately malicious agent (or extension) can exfiltrate the one real key you pass.
> 2. The *hardened* flags as documented **don't run pi at all** — `--read-only` makes the
>    session directory unwritable, so pi crashes on startup.

| method | host secrets | egress | runs pi? | exfil of the injected key |
|--------|:---:|:---:|:---:|:---:|
| direct on host (no isolation) | ❌ exposed | open | ✅ | n/a |
| `02` Docker recommended | ✅ hidden | open | ✅ | ❌ **leaks** |
| `03` Docker leaky mounts | ❌ exposed | open | ✅ | (mounts decide exposure) |
| `04` Docker hardened | ✅ hidden | ❌ none | ❌ **crashes** | ✅ blocked |
| `09` non-root hardened | ✅ hidden | ❌ none | ⚠️ local model only | ✅ blocked |
| `05` gVisor | ✅ hidden | ❌ none | — | ✅ blocked |
| `07` secrets-broker | ✅ placeholder only | open | ✅ | real key never enters |

Full matrix (incl. adversarial cases) and evidence links: [`THREAT_MODEL.md`](THREAT_MODEL.md).

## Layout

| path | what it is |
|------|------------|
| `harness/probe.sh` | portable escape-attempt probe — identity, secrets, network, writes, processes, capabilities |
| `harness/run-docker-probes.sh` | reproduces the 3 Docker probe variants (Windows/Git Bash; sets `MSYS_NO_PATHCONV=1`) |
| `harness/run-docker-probes-macos.sh` | same on macOS/Linux; `$HOME`-derived mounts, host label from `uname` |
| `harness/run.sh` | practical sandbox: mounts `$PWD`, non-root, caps dropped, read-only (`--no-network`, `--probe`) |
| `harness/smoke-agentic.sh` | runs pi **as an agent** per config (product-function test) |
| `harness/exfil-probe.sh` + `exfil/` | measures real-key exfiltration against a synthetic attacker collector |
| `harness/check-sandbox-plugins.sh` | verifies the 4 bundled plugins load (9 checks) |
| `harness/sandbox-plugins.sh` | interactive sandbox shell with the 4 plugins pre-installed |
| `harness/check-invariants.sh` | grep-based regression assertions over `results/` |
| `harness/normalize-results.sh` | strips host-specific noise for clean cross-host diffs |
| `examples/research-repo/` | worked example: develop a git repo (a new `skeleton-research` topic) inside the sandbox |
| `docker/Dockerfile.pi` | `node:24-bookworm-slim` + pi + git + ripgrep + 4 plugins → `pi-sandbox:latest` |
| `results/` | raw probe outputs + timing — see [`results/README.md`](results/README.md) |
| `Makefile` · `THREAT_MODEL.md` · `REPORT.md` | entry points · adversaries · the write-up |

## Reproduce

```bash
make image                         # docker build -t pi-sandbox -f docker/Dockerfile.pi .
bash harness/probe.sh              # baseline, no isolation       → results/01-*.txt
make probes                        # 02 recommended, 03 leaky, 04 hardened (macOS/Linux)
bash harness/run-docker-probes.sh  # the same three, on Windows/Git Bash
make check                         # assert invariants over results/*.txt
```

The Docker variants are:

| id | configuration |
|----|---------------|
| `02` recommended | workspace bind mount + named volume for the agent home, one key passed with `-e` |
| `03` leaky mounts | the above, plus host `~/.ssh`, `~/.pi/agent` and `$HOME` mounted read-only |
| `04` hardened | `--network none --read-only --tmpfs /tmp` (see the crash caveat above) |
| `09` non-root hardened | `--user 1001:1001 --cap-drop ALL --security-opt no-new-privileges`, writable tmpfs agent home |

## Example — develop a git repo in the sandbox

The research result has an everyday shape: give the agent a repo, keep your
credentials out. `examples/research-repo/` bootstraps a new topic from
[`skeleton-research`](https://github.com/tobias-weiss-ai-xr/skeleton-research)
inside the sandbox — the agent edits config, runs the project's pipeline and full
test suite, and commits; the change persists to the host, while push
stays a human step (no SSH key, fetch-only remote).

```bash
make example                                     # scripted, no model needed
bash examples/research-repo/run.sh --interactive # hand it to the real agent
```

See [`examples/research-repo/README.md`](examples/research-repo/README.md) and
[`results/12-sandbox-research-repo.txt`](results/12-sandbox-research-repo.txt).

## Bundled sandbox plugins

The `pi-sandbox:latest` image ships four packages, verified by `make verify`:

| package | source | what it adds |
|---------|--------|--------------|
| **pi-saia-plugin** | `git:github.com/tobias-weiss-ai-xr/pi-saia-plugin` | SAIA Academic Cloud provider + all models (needs `-e SAIA_API_KEY` at runtime) |
| **ponytail** | `npm:opencode-ponytail` | minimal-code rules — `/ponytail lite\|full\|ultra\|off` |
| **caveman** | `npm:pi-caveman` | terse output, ~75% fewer tokens — `/caveman full\|ultra\|…` |
| **rtk** | `npm:@sherif-fanous/pi-rtk` | routes shell commands through the `rtk` binary — `/rtk status` (degrades gracefully if the binary is absent) |

Interactive — launch a shell with all four plugins and a live model:

```bash
SAIA_API_KEY=... bash harness/sandbox-plugins.sh
# inside the container:
pi
# slash commands to try:
#   /model saia/qwen3.6-35b-a3b    /caveman full    /ponytail lite    /rtk status
```

Non-interactive smoke test:

```bash
docker run --rm -e SAIA_API_KEY \
  --entrypoint pi pi-sandbox \
  --model saia/meta-llama-3.1-8b-instruct -p "Reply with exactly: sandbox ok"
```

## Other runtimes

| file | what |
|------|------|
| `results/05-gondolin-attempt.txt` · `results/06-sandbox-runtime-attempt.txt` | blocked on Windows (no QEMU / no vendored `srt-win.exe`) |
| `results/05-legion-gvisor*.txt` | gVisor via `runsc` OCI on legion (tighter at the syscall level) |
| `results/07-legion-secrets-broker.txt` | secrets-broker pattern — placeholder + scoped token |
| `results/07-docker-sandboxes-sbx.txt` | Docker Sandboxes / `sbx` not installed on the test host |

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs three jobs:

- **lint** — `shellcheck -S error` + `bash -n` (uses local shellcheck in CI; falls back to the
  `koalaman/shellcheck` Docker image, then `bash -n`, locally);
- **invariants** — `make check` asserts the committed corpus (no Docker);
- **sandbox** — builds the image → `make verify` → unit-tests the probe (`make test`) →
  regenerates the Linux probes → re-asserts invariants → runs the research example
  (`make example`) → uploads the fresh results as an artifact.

## Safety of the probe

`harness/probe.sh` is safety-designed: it prints file **existence and size only**, and
env-var **names only** — never secret contents. Safe to run anywhere, including on the host.
