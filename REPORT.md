# Pi Sandboxing Methods — Practical Comparison Report

**Project:** `pi-sandboxing` · **Host:** Windows 11, Git Bash (MINGW64)
**Pi:** 0.99.2 (host) · **Docker:** 29.6.1 Desktop (Linux containers, WSL2 backend) · **Node:** 22.14.0

Empirical comparison of the ways to sandbox Pi's model-generated commands, with a fixed
escape-attempt probe (`harness/probe.sh`) run in each environment. Raw outputs live in
`results/` — every claim below is backed by a captured file.

---

## TL;DR

| Rank | Method | Boundary strength | Works on this host today? | Credential story |
|---|---|---|---|---|
| 1 | **Plain Docker** (recommended mounts) | Strong (whole process) | ✅ **tested, works** | Real key enters container via `-e` |
| 1b | **Plain Docker hardened** (`--network none --read-only`) | Strongest tested | ✅ **tested, works** | Same, but no egress to leak it |
| 2 | Docker Sandboxes (`sbx`) | Strong (managed) | ❌ CLI not installed | **Best**: proxy keeps real key on host |
| 3 | OpenShell | Strong (fs/proc/net/cred/inference policies) | ❌ not installed | Good: inference routing keeps keys out |
| 4 | Gondolin micro-VM | Medium-strong (tools only) | ❌ `qemu-img ENOENT` | **Weak**: commands inherit host env |
| 5 | OS-level sandbox extension | Narrow (bash only) | ⚠️ **undocumented Windows backend exists** | None (env visible to commands) |
| 6 | Direct run (baseline) | **None** | ✅ (this is the threat) | All 6 API keys exposed |

**Bottom line:** On this Windows host, **Plain Docker is the only strong boundary that
actually runs today** — and its two real gaps (open network egress, writable container
root) close with two flags, both verified. Gondolin is blocked by missing QEMU; `sbx` and
OpenShell are simply not installed. The biggest surprise: `@anthropic-ai/sandbox-runtime`
ships a **full Windows backend (WFP + ACLs)** that Pi's docs claim doesn't exist — it needs
a one-time UAC install and is unusable out of the box.

---

## 1. The threat, measured first (baseline: no isolation)

`results/01-direct-no-isolation.txt` — running the probe directly on the host shows what
any unsandboxed Pi session can touch:

- **6 secret-shaped env vars set**: `ZHIPUAI_API_KEY`, `LITELLM_API_KEY`, `SAIA_API_KEY`,
  `GOOGLE_API_KEY`, `NEO4J_PASSWORD`, `OPENROUTER_API_KEY`
- **Real SSH private key readable**: `~/.ssh/id_rsa` (1,675 B)
- **Pi's own credential store readable**: `~/.pi/agent/settings.json` (4,795 B), plus
  `~/.gitconfig` (2,514 B), `~/.docker`, `~/.kube`
- **Writes outside the workspace succeed** — both `/tmp` and the parent directory
- **Full network egress**: example.com → 200, api.anthropic.com → 404 (reachable)
- **Host disks visible**: `C:` and `D:` mounted, `docker` CLI on PATH

Pi's own docs agree this is not a boundary: *"Watching the transcript, using project trust,
and reviewing changes do not create a security boundary"* (`docs/security.md`).

---

## 2. Methods at a glance

| | Where Pi runs | What's isolated | Network control | Setup cost here |
|---|---|---|---|---|
| **Plain Docker** | Inside container | Pi + built-in tools + `!` + extensions | `--network none` / flags | Image build (~2 min) |
| **Docker Sandboxes** | Managed sandbox | Same, + credential proxy | Via Docker Sandboxes | Install `sbx` CLI |
| **OpenShell** | Local/remote sandbox | fs, processes, network, credentials, **inference** | Policy-based | Install OpenShell + gateway |
| **Gondolin** | Host (tools in micro-VM) | Built-in tools + `!` commands only | Per-extension | Node ≥23.6 + QEMU |
| **OS-level sandbox ext** | Host (bash wrapped) | **Bash commands only** | Domain allowlist (WFP/eBPF/sandbox-exec) | npm install; UAC on Windows |
| **Direct** | Host user | Nothing | None | None |

---

## 3. Findings per method

### 3.1 Plain Docker — the workhorse ✅

`results/02-docker-recommended.txt`, `03-docker-leaky-mounts.txt`, `04-docker-hardened.txt`

Built the documented image (`docker/Dockerfile.pi`: node:24-bookworm-slim + pi + git +
ripgrep; **1.36 GB**). Ran the probe three ways:

**Recommended setup** (workspace bind mount + *named* volume for `/root/.pi/agent`, only
`ANTHROPIC_API_KEY` passed in):

- Host secrets **gone**: all 6 host API keys invisible; only the one dummy var passed in.
  Host `~/.ssh`, `~/.aws`, `~/.gitconfig`, `~/.docker`, `~/.kube` — all `missing`.
- `/var/run/docker.sock` **not mounted**; `docker` CLI absent inside.
- `/proc/1/cmdline` is the container's own `bash /probe.sh` — PID namespace isolated.
- **Gap 1 — network egress is wide open**: example.com → 200, api.anthropic.com → 404
  (only the AWS metadata IP 169.254.169.254 is unreachable). A compromised container can
  exfiltrate anything you mounted or passed.
- **Gap 2 — container root is writable**: `dirname(/workspace)` write "succeeded" (to
  `//` inside the container — harmless to the host, but a writable attack surface).

**Leaky variant** (`03`) — mounting host home, `~/.pi/agent`, `~/.ssh` read-only + 3 env
vars: the **real** `id_rsa` (1,675 B) and **real** `settings.json` (4,795 B) appear inside.
Mounts, not Docker, decide credential exposure. This is the docs' #1 warning
("Do not mount the host's `~/.pi/agent`").

**Hardened variant** (`04`) — `--network none --read-only --tmpfs /tmp`:

- Network: **all three probes blocked** (`ERR:undefined`).
- Parent-dir write: **blocked** (`Read-only file system`); `/tmp` still works (tmpfs).

Both gaps close with two flags. Cost: container start ≈ **0.53 s** one-time
(`results/08-timing.txt`; direct ≈ 0.03 s — and in real use you start one long-lived
container, so this is not per-tool-call).

**Gotcha found:** Git Bash mangles `-v /probe.sh:ro` into `C:/Program Files/Git/probe.sh:ro`.
Everything Docker in this repo runs under `MSYS_NO_PATHCONV=1` (encoded in
`harness/run-docker-probes.sh`).

**Pros:** strongest boundary that actually works here; host secrets invisible by default;
hardening is two flags; no admin rights; reproducible image; cross-platform.
**Cons:** 1.36 GB image; real API key still enters the container (`-e`); version drift
(container got pi **1.0.0** vs host **0.99.2** — pin the image); extensions must work in
the container; MSYS path friction on Windows; interactive TUI through `docker run -it`.

### 3.2 Docker Sandboxes (`sbx`) — best credential story, not installed ❌

`results/07-docker-sandboxes-sbx.txt`

`sbx` is not on PATH, `docker sandbox` is **removed** ("migrate to Docker Sandboxes"),
`@docker/sbx` is 404 on npm. The docs' pitch is real and distinct: the proxy keeps the true
provider key **on the host** and substitutes an OAuth-shaped placeholder inside the sandbox
(`sbx secret set-custom --host api.anthropic.com --env ANTHROPIC_OAUTH_TOKEN
--placeholder 'sk-ant-oat01-...'`), replacing it only for requests to that host.
Run: `sbx run --kit "docker.io/sbx/pi-kit:latest" pi`; non-interactive:
`sbx exec <name> -- pi -p "..."`.

**Pros:** strictly better credential handling than plain Docker (real key never enters the
sandbox); managed lifecycle; official pi kit. **Cons:** another CLI to install and trust;
underneath it's the same container-class boundary, not a stronger one; untested here.

### 3.3 OpenShell — richest policy model, not installed ❌

Per `docs/containerization.md` (no install present to test): local/remote sandboxes with
**filesystem, process, network, credential, and inference** policies — the only method whose
policy scope covers model-inference routing itself, so raw model keys can stay outside the
sandbox entirely. Requires a gateway (`openshell gateway add/select`), and remote sandboxes
have **no bind mounts** — files move via `openshell sandbox upload/download` or git clone.

**Pros:** most complete policy surface; credential + inference routing; remote option.
**Cons:** install + gateway management; file-transfer overhead on remote; untested here.

### 3.4 Gondolin micro-VM — blocked by QEMU ❌

`results/05-gondolin-attempt.txt`

The package installed and **loaded on Node 22** despite the documented ≥23.6 requirement,
and even extracted its guest image to `~/.cache/gondolin/v0.5.0` — then died:
`spawnSync qemu-img ENOENT`. **QEMU is the hard blocker on this host.**

Architecturally: Pi stays on host with full UX; the extension overrides
`read/write/edit/bash/grep/find/ls` + `!` commands to execute inside a QEMU micro-VM with
the workspace mounted at `/workspace` (write-through). Two caveats from the docs worth
highlighting: (1) **commands inherit the host process environment**, so env-var API keys are
visible inside the VM — *"Do not use this pattern as a credential boundary"*; (2) other
extension tools keep running on the host, so it's a narrower boundary than it looks.

**Pros:** real VM boundary for tool execution; Pi/UX/extensions stay on host; transparent
`/workspace` write-through. **Cons:** QEMU + Node 23.6 prerequisites; not a credential
boundary as shipped; only built-in tools are routed; ~500 lines of extension code to trust.

### 3.5 OS-level sandbox extension — undocumented Windows backend ⚠️

`results/06-sandbox-runtime-attempt.txt`

The example extension (`examples/extensions/sandbox`) wraps bash with
`@anthropic-ai/sandbox-runtime` — declarative `allowedDomains`, `denyRead/allowWrite/denyWrite`
— via `sandbox-exec` (macOS) / bubblewrap (Linux). Pi's docs say macOS/Linux only.

**Discovery:** `sandbox-runtime@0.0.78` **loads on win32** and exports a full Windows
backend: `srt-win.exe`, `getWindowsWfpStatusAsync` (Windows Filtering Platform for network
egress), `grantWindowsAcl/revokeWindowsAcl` (filesystem), a dedicated `srt-sandbox` user
keyed by SID, `installWindowsSandbox`, `WindowsConfigSchema`. The docs' "macOS/Linux only"
claim is stale for the underlying runtime — the *extension* is what disables Windows.

It fails out of the box: `initialize()` → *"no srt-win path configured"* — the vendored
binary is **not shipped** in the npm package (`vendor/` is absent). Activation requires a
one-time **UAC** install: `npx sandbox-runtime windows-install` (creates the `srt-sandbox`
user + WFP filter). Not run here — that's an invasive system change I won't do unattended.

**Pros:** lightest weight (no container/VM, ~ms overhead); fine-grained declarative policy;
network domain allowlisting that plain Docker lacks natively. **Cons:** bash-only — the
read/write/edit tools and other extensions bypass it entirely; no credential isolation;
on Windows: undocumented, needs UAC + system user + WFP filter, broken without config.

### 3.6 Direct run — the baseline to avoid

See §1. Everything exposed. Fine only for throwaway work in disposable VMs/containers.

---

## 4. Recommendations

- **Default on this host:** Plain Docker with the documented mounts. Only boundary that's
  strong *and* verified working. Add `--network none` whenever the task doesn't need net.
- **Task needs network:** accept egress but keep secrets out — pass one scoped key, never
  mount `~/.pi/agent`; or install `sbx` for the proxy pattern.
- **Want host UX + stronger-than-nothing:** Gondolin, *after* installing QEMU and Node ≥23.6
  — and strip sensitive env vars first, since it inherits the host environment.
- **Curious / Windows-native future:** `sandbox-runtime windows-install` is a promising,
  undocumented path — test in a VM snapshot first (UAC, new system user, WFP filter).
- **Never** rely on project trust or transcript-watching as a boundary (Pi's docs say so).

---

## 5. Reproduce

```bash
docker build -t pi-sandbox -f docker/Dockerfile.pi .
bash harness/probe.sh                          # baseline → results/01-*.txt
bash harness/run-docker-probes.sh              # 02 recommended, 03 leaky, 04 hardened
# Gondolin / sandbox-runtime attempts:
#   see results/05-*.txt and results/06-*.txt (commands inline)
```

The probe is safety-designed: it prints file **existence + size only**, env-var **names
only** — never secret contents. Raw evidence: `results/01…08-*.txt`.
