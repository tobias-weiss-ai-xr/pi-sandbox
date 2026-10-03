# pi-sandboxing

[![ci](https://github.com/tobias-weiss-ai-xr/pi-sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/tobias-weiss-ai-xr/pi-sandbox/actions/workflows/ci.yml)

Empirical comparison of the ways to sandbox Pi's model-generated commands. Each
method is probed with a fixed escape-attempt script on three hosts — **Windows 11
+ Git Bash + Docker Desktop (WSL2)**, **native Linux (legion)**, and **macOS
(Colima)** — plus a **product-function test** (does pi actually work as an agent)
and a **real exfiltration test**. Raw outputs are committed under `results/`.

Two headline results (see `REPORT.md` §9): the *recommended* open-network setup is
only safe against *accidental* leaks — a malicious agent can exfiltrate the one
real key you pass — and the *hardened* flags as documented don't run pi at all
(read-only session dir). Read `THREAT_MODEL.md` before quoting a verdict.

The full write-up with findings and recommendations is **`REPORT.md`**. What each
method actually protects against — and the adversaries that defeat it — is in
**`THREAT_MODEL.md`**. Raw outputs are indexed in **`results/README.md`**.

## Quick start

```bash
make help        # list targets
make image       # build pi-sandbox:latest
make verify      # assert the 4 bundled plugins load (9 checks)
make check       # assert the committed results still satisfy their invariants (no Docker)
make sandbox     # interactive non-root sandbox with the current dir mounted
```

## Repo layout

```
harness/probe.sh                     portable escape-attempt probe (identity, secrets, net, writes, procs, caps)
harness/run-docker-probes.sh          reproduces all 3 Docker probe variants (Windows; sets MSYS_NO_PATHCONV=1)
harness/run-docker-probes-macos.sh    same variants on macOS/Linux, HOME-derived mounts, host label from uname
harness/check-sandbox-plugins.sh      verifies the 4 bundled sandbox plugins load
harness/sandbox-plugins.sh            interactive sandbox shell with the 4 plugins pre-installed
harness/run.sh                        practical sandbox: mounts $PWD, non-root, caps dropped, read-only (--no-network|--probe)
harness/smoke-agentic.sh              runs pi AS AN AGENT per config (product-function test)
harness/exfil-probe.sh + exfil/       measures real-key exfiltration vs a synthetic attacker collector
harness/check-invariants.sh           turns the results corpus into grep-able regression assertions
harness/normalize-results.sh          strips host-specific noise for clean cross-host diffs
docker/Dockerfile.pi                  node:24-bookworm-slim + pi + git + ripgrep + 4 plugins → image pi-sandbox:latest
results/01..11-*.txt                  raw probe outputs + timing (host suffix: none=Win, -legion=Linux, -macos); see results/README.md
Makefile                              one-command entry points
THREAT_MODEL.md                      adversaries + what each method stops
REPORT.md                            the comparison report
```

## Reproduce

```bash
make image                         # docker build -t pi-sandbox -f docker/Dockerfile.pi .
bash harness/probe.sh              # baseline (no isolation) → results/01-*.txt
make probes                        # 02 recommended, 03 leaky mounts, 04 hardened (macOS/Linux)
bash harness/run-docker-probes.sh  # same, on Windows/Git Bash
make check                         # assert invariants over results/*.txt
```

## Bundled sandbox plugins

The `pi-sandbox:latest` image ships four packages, verified by
`harness/check-sandbox-plugins.sh`:

| Package | Source | What it adds |
|---|---|---|
| pi-saia-plugin | `git:github.com/tobias-weiss-ai-xr/pi-saia-plugin` | SAIA Academic Cloud provider + all models (needs `-e SAIA_API_KEY` at runtime) |
| ponytail | `npm:opencode-ponytail` | minimal-code rules — `/ponytail lite|full|ultra|off` |
| caveman | `npm:pi-caveman` | terse output, ~75% fewer tokens — `/caveman full|ultra|...` |
| rtk | `npm:@sherif-fanous/pi-rtk` | routes shell commands through the `rtk` binary — `/rtk status` (degrades gracefully if the binary is absent) |

Interactively:

```bash
SAIA_API_KEY=... bash harness/sandbox-plugins.sh
"# in the container:" pi
"# then e.g. /model saia/qwen3.6-35b-a3b   /caveman full   /ponytail lite   /rtk status"
```

Verify in CI / on the CLI:

```bash
bash harness/check-sandbox-plugins.sh   # 9 assertions, all must PASS
```

Gondolin and sandbox-runtime attempts were recorded inline in `results/05-*.txt` and
`results/06-*.txt` (both blocked on this host: missing QEMU / missing vendored srt-win.exe).

## CI

`.github/workflows/ci.yml` runs three jobs: **lint** (`shellcheck` + `bash -n`),
**invariants** (`make check` over the committed corpus — no Docker), and **sandbox**
(build the image → `make verify` → regenerate the Linux probes → re-assert invariants),
uploading the fresh results as an artifact.

## Note on the probe

`harness/probe.sh` is safety-designed: it prints file **existence + size only** and
env-var **names only** — never secret contents.
