# pi-sandboxing

Empirical comparison of the ways to sandbox Pi's model-generated commands, run on
**Windows 11 + Git Bash + Docker Desktop (WSL2)**. Each method is probed with a fixed
escape-attempt script; raw outputs are committed under `results/`.

The full write-up with findings and recommendations is **`REPORT.md`**.

## Repo layout

```
harness/probe.sh            portable escape-attempt probe (identity, secrets, net, writes, procs)
harness/run-docker-probes.sh  reproduces all 3 Docker probe variants (sets MSYS_NO_PATHCONV=1)
docker/Dockerfile.pi        node:24-bookworm-slim + pi + git + ripgrep → image pi-sandbox:latest
results/01..08-*.txt        raw probe outputs + timing
REPORT.md                   the comparison report
```

## Reproduce

```bash
docker build -t pi-sandbox -f docker/Dockerfile.pi .
bash harness/probe.sh              # baseline (no isolation) → results/01-*.txt
bash harness/run-docker-probes.sh  # 02 recommended, 03 leaky mounts, 04 hardened
```

Gondolin and sandbox-runtime attempts were recorded inline in `results/05-*.txt` and
`results/06-*.txt` (both blocked on this host: missing QEMU / missing vendored srt-win.exe).

## Note on the probe

`harness/probe.sh` is safety-designed: it prints file **existence + size only** and
env-var **names only** — never secret contents.
