# pi-sandboxing

Empirical comparison of the ways to sandbox Pi's model-generated commands, run on
**Windows 11 + Git Bash + Docker Desktop (WSL2)**. Each method is probed with a fixed
escape-attempt script; raw outputs are committed under `results/`.

The full write-up with findings and recommendations is **`REPORT.md`**.

## Repo layout

```
harness/probe.sh                     portable escape-attempt probe (identity, secrets, net, writes, procs)
harness/run-docker-probes.sh          reproduces all 3 Docker probe variants (Windows; sets MSYS_NO_PATHCONV=1)
harness/run-docker-probes-macos.sh    same variants on macOS, HOME-derived mounts
harness/check-sandbox-plugins.sh      verifies the 4 bundled sandbox plugins load
harness/sandbox-plugins.sh            interactive sandbox shell with the 4 plugins pre-installed
docker/Dockerfile.pi                  node:24-bookworm-slim + pi + git + ripgrep + 4 plugins → image pi-sandbox:latest
results/01..08-*.txt                  raw probe outputs + timing (host suffix: none=Win, -legion=Linux, -macos)
REPORT.md                            the comparison report
```

## Reproduce

```bash
docker build -t pi-sandbox -f docker/Dockerfile.pi .
bash harness/probe.sh              # baseline (no isolation) → results/01-*.txt
bash harness/run-docker-probes.sh  # 02 recommended, 03 leaky mounts, 04 hardened (Windows)
bash harness/run-docker-probes-macos.sh  # 02/03/04 on macOS (results/0X-macos-*.txt)
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

## Note on the probe

`harness/probe.sh` is safety-designed: it prints file **existence + size only** and
env-var **names only** — never secret contents.
