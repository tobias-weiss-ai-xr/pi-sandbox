# pi-sandboxing — Further improvements (research-backed roadmap)

Inspiration scan (2026-10):

- [awesome-ai-coding-sandboxes](https://github.com/fhiltscher/awesome-ai-coding-sandboxes) —
  security-posture-first landscape matrix (38 runtimes). Key data: **egress control is the
  minority** (only ~8 deny-by-default); **secrets brokering is now a real cluster** (sbx-style
  proxy is mainstream: Cleanroom, smolvm, Mitos, microsandbox, OpenSandbox, …); the
  "strong-posture tier" = microVM **and** restricted egress **and** brokered secrets.
- Upstream pi docs 0.99.2 (`docs/containerization.md`) now officially present **Docker
  Sandboxes** and **OpenShell** as the preferred managed methods — the two our report marked
  "not installed" are now the vendor-endorsed paths, including the proxy credential pattern
  (`sbx secret set-custom`, placeholder substitution per host).
- NVIDIA **OpenShell** (~15k⭐, NemoClaw ecosystem) — fs/proc/net/credential/**inference**
  policies; only method that can route inference so real model keys never enter the shell.
- **microsandbox** (~8.5k⭐, Apache, libkrun µVM + broker) — "Gondolin done right".
- **Greywall** (~300⭐) — container-free, deny-by-default kernel-enforced fs/net/syscall
  isolation for AI agents (macOS+Linux) — closes the OS-level-extension gap from §4.
- wasmer (~21k⭐) — WASM sandboxes as a *tool-execution* tier (narrow, fast).

## Verified feasibility on legion (this session)

- `/dev/kvm` present, VT-x (24 vmx flags) → **microVM tier is runnable** (Firecracker/Kata/libkrun).
- `bwrap` already installed → process-tier probes are zero-install.
- `sbx` / `runsc` / firejail / OpenShell not installed; all installable (Arch repo / npm / Docker).

## Ranked experiments

| # | Experiment | Tier | Value | Cost | Why |
|---|---|---|---|---|---|
| 1 | `05-gvisor`: same suite under `docker run --runtime=runsc` | container+ | kernel-ish boundary | low (daemon) | gVisor = user-space kernel; closes shared-kernel container weaknesses for free in Docker |
| 2 | `06-bwrap`: probe under bubblewrap (`--ro-bind /`, net off) | process | zero-startup, no Docker | **low (0 install)** | measures the "no-container" tier against the identical probe; the §4 bash-jail question quantified |
| 3 | `07-secrets-broker`: poor-man's sbx | brokering | **high** | low | small proxy inside container pulls real key from host over one forwarded port (the homelab socat pattern); proves brokering works with plain Docker, no new CLI |
| 4 | Install + probe **Docker Sandboxes `sbx`** on legion | managed container | high | medium | vendor-endorsed; real credential story (host-proxied); report's "not installed" is now outdated |
| 5 | Install + probe **NVIDIA OpenShell** (Docker) | managed sandbox | high | medium | inference routing = the only way raw model keys can stay fully outside; ~15k⭐ maturity |
| 6 | **microsandbox** (libkrun µVM + broker) | microVM | high | medium-high | self-hosted, Apache, brokered secrets — the strong-posture tier, on a host that has KVM |
| 7 | **Greywall** vs bwrap side-by-side | kernel/process | medium | medium | container-free deny-by-default; tests whether Docker is even needed on legion |
| 8 | **Kata/Firecracker via containerd** (Cleanroom/Mitos posture) | microVM | high | high | deny-default egress + brokered secrets; heavier ops | 

## Horizontal improvements (independent of which experiment)

- **Credential story repo-wide**: real keys stay in a host-side store (sops/vault); containers get
  scoped tokens or a forwarded host proxy port. Fix the §4 plugin-credential hole: plugin tokens
  (`~/.pi/agent/settings.json`) need a per-sandbox named volume seeded once, or migration to
  env-var credentials readable via the proxy.
- **Version pinning**: Dockerfile currently floats pi (container got 1.0.0 vs host 0.99.2).
  Pin `@earendil-works/pi-coding-agent@<version>` and print pi versions from inside the probe.
- **Image size**: 1.36 GB from node:24-bookworm-slim; consider multi-stage (builder → runtime
  with only pi + git + ripgrep) and a scratch/minimal distroless base.

## Tooling improvements for this repo

1. **Cross-platform runner**: `run-docker-probes.sh` currently hard-requires Git Bash
   (`MSYS_NO_PATHCONV`, `pwd -W`). Make it detect MINGW vs native Linux and run unmodified on
   legion (this session had to hand-invoke equivalent commands).
2. **CI invariant-check**: GitHub Actions matrix (ubuntu-latest + self-hosted legion runner)
   runs the full suite and *asserts* the findings — `04-hardened`: no HTTP 200, parent write
   blocked; `02-recommended`: exactly 1 secret-shaped var, no `id_rsa`; `03-leaky`: leaks
   present. Converts the probe outputs from documentation to regression tests. The outputs are
   already grep-able for each invariant.
3. **Result normalizer**: strip host-specific noise (container IDs, timings) so legion vs
   windows results diff cleanly.