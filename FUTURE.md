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

## The Talos angle — the OS under the K8s-tier experiment (#8)

Talos is not a sandbox — it's the **host OS that makes table-row #8 (Kata/Firecracker via
containerd) and the k8s-sigs agent-sandbox pattern actually secure**. Framed that way it's a
real candidate for a *dedicated agent-execution node*, and it happens to match the homelab
constraints. Grounding (2026-10 scan):

- **[agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)** (kubernetes-sigs,
  ~4.1k⭐) — a `Sandbox` CRD: stateful, single-container, stable-identity pods with
  persistent storage, built exactly for "AI agent runtimes". It is an *orchestrator* — it
  delegates low-level isolation to **gVisor / Kata Containers via `RuntimeClass`**. That is
  the K8s-native equivalent of our report's pi-in-Docker, with the two gaps closed by
  platform policy instead of per-run flags: default-deny NetworkPolicy (egress) and a secret
  webhook (brokering, the sbx pattern cluster-wide).
- **Talos specifics that matter here:** immutable rootfs + no SSH + no package manager +
  single user + **mTLS API-only** — a node whose only job is running untrusted,
  model-generated code gets maximal container-escape resistance at the OS layer (no shell,
  no package manager, nothing to land on after escape); machine config is declarative YAML
  beside the repo (fits the existing git/ansible workflow); containerd CRI config snippets
  via `machine.files` → `/etc/cri/conf.d` enable RuntimeClasses; gVisor ships as a Sidero
  extension (`siderolabs/extensions`, `container-runtime/gvisor-debug` proves the plumbing).
- **Honest cost:** it's a new platform, not a script. A dedicated node's worth of ops
  (talosctl instead of SSH; Sidero Omni if the fleet grows), and Kata needs KVM + qemu
  (Talos extensions, heavier; gVisor is the easy default). **It does not fix the real
  credential surface** — legion's `~/.pi/agent` + plugin tokens live on the workstation;
  Talos only helps if the sandbox itself is the thing being secured, i.e. you stop running
  risky agent commands on legion and run them on the sandbox node instead.

**Where it fits the homelab:** ai1/ai2 are inference-only (never agents). A Talos node is a
*new* dedicated worker — a host that exists to execute untrusted agent commands for the
whole opencode fleet (legion, chemie, ci, tobi-yoga, pcrz1334, wsl), with legion clients
connecting remotely (the fleet already does remote SSH).

**Posture you'd validate in the pilot:**

| Layer | Default |
|---|---|
| Isolation | `RuntimeClass` = gVisor (default), Kata (risky/GPU tasks) |
| Egress | Cilium default-deny + FQDN allowlist (provider APIs, git remotes only) |
| Secrets | admission webhook: placeholder-substitute real keys (sbx pattern, platform-wide) |
| Lifecycle | agent-sandbox CRD: stateful singleton pi/opencode sessions, persistent storage |
| Node audit | Falco; node itself immutable/mTLS (Talos) |

This combination is exactly the **"strong-posture tier"** from the awesome list
(microVM/gVisor **and** restricted egress **and** brokered secrets) achieved self-hosted —
compare Katakate k7 (Kata+K3s, lighter variant).

**Recommendation (lazy-first):**
1. **Now:** the FUTURE.md quick wins — `05-gvisor` probe on legion (Docker `--runtime=runsc`
   already gives the gVisor layer without K8s, answering "is gVisor measurably better than
   plain Docker for our probe") + `07-secrets-broker`. ~80% of the security learnings, one day.
2. **Weekend pilot:** Talos (single node, KVM on legion or the decommissioned Hetzner box)
   + agent-sandbox + gVisor RuntimeClass + default-deny + placeholder webhook; run the
   probe suite against it as result `08-*` — the first K8s-tier datapoint in this repo.
3. **Only when multi-tenant demand appears:** dedicated Talos worker joined to the homelab
   fleet. Until then, per-host Docker flags remain the right size of solution.



- **Credential story repo-wide**: real keys stay in a host-side store (sops/vault); containers get
  scoped tokens or a forwarded host proxy port. Fix the §4 plugin-credential hole: plugin tokens
  (`~/.pi/agent/settings.json`) need a per-sandbox named volume seeded once, or migration to
  env-var credentials readable via the proxy.
- **Version pinning**: Dockerfile currently floats pi (container got 1.0.0 vs host 0.99.2).
  Pin `@earendil-works/pi-coding-agent@<version>` and print pi versions from inside the probe.
- **Image size**: 1.36 GB from node:24-bookworm-slim; consider multi-stage (builder → runtime
  with only pi + git + ripgrep) and a scratch/minimal distroless base.

## Experiment status

### ✅ Done — `05-gvisor` (runs on legion, no dockerd touch)

`runsc` 2026-09-28 installed; OCI bundle built from the pi-sandbox image (`docker create`
+ `docker export` rootfs); ran directly via `runsc --root … --network host|none --platform kvm run`
(no `daemon.json` edit → **no restart of the 50 production containers** on legion). Configs:
`scratch/gvisor-config-{open,hardened}.json`.

- **open** (`--network host`, writable rootfs): probe fires identically — `uname 4.19.0-gvisor`,
  no host files, egress 200. **Novel result: `parent-dir write blocked` even though the rootfs
  is writable** — gVisor denies writes at `/`, where plain Docker allowed them. gVisor is
  measurably tighter on the exact gap §3.1 flagged.
- **hardened** (`--network none`, readonly rootfs): egress ERR, `/tmp` and parent writes
  blocked — same closed gaps as Docker-hardened, plus the readonly rootfs.
- Reproduce: `docker create`/`export` → rootfs under `bundle/rootfs`, config next to it,
  `runsc run`; needs `/dev/kvm` (verified present on legion) or `--platform ptrace`.

### ✅ Done — `07-secrets-broker` (poor-man's Docker Sandboxes)

`harness/broker_server.py` (one demo credential, token-protected) + `harness/probe_broker.sh`
(prints env NAMES and booleans only; the credential value is equality-checked, never echoed).
Container got only a placeholder (`FAKE_API_KEY_PLACEHOLDER`) + scoped token; pulled the
real key at runtime over one forwarded port; match confirmed; value never logged — the sbx
brokering pattern proven with plain Docker. **Firewall finding:** container→bridge-gateway
(172.17.0.1) was silently dropped by the host INPUT policy (Docker only programs FORWARD),
which is exactly why this homelab's `fwd-*` socat containers exist; one temporary
`iptables -I INPUT -i docker0 -p tcp --dport <p> -j ACCEPT` opened it (rule removed afterwards).

### ⏳ Open — `06-bwrap`, install-and-probe of `sbx`/OpenShell, microVM tier (microsandbox /
Kata), Greywall

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