# Threat model

The probe results are only meaningful against a stated adversary. This file
defines what we assume, what each sandbox method actually stops, and what is
explicitly out of scope. Read it before quoting a "safe"/"unsafe" verdict.

## Assets

1. **Host credentials** — SSH keys, cloud/API credentials, `~/.pi/agent`, agent
   sockets (`SSH_AUTH_SOCK`, gpg-agent), macOS Keychain.
2. **The one scoped key** you deliberately inject so the agent can call a model.
3. **Integrity of the host filesystem** outside the shared workspace.
4. **Model budget / blast radius** — how far a misbehaving agent can act.

## Adversaries

| id | adversary | how it arrives |
|----|-----------|----------------|
| **A1** | accidental leak | a buggy tool/extension writes or sends a secret; an over-broad mount |
| **A2** | malicious/compromised agent | the model is tricked (e.g. prompt-injection in code/README it reads) into exfiltrating or destroying |
| **A3** | malicious extension | a third-party pi package (`ponytail`/`caveman`/`rtk`/…) runs code with the sandbox's grants |
| **A4** | untrusted project | a cloned repo whose `AGENTS.md`/hooks instruct the agent — a *vector* that arms A2 |

A1 is a hygiene problem. A2–A4 are adversarial: the agent **tries** to cross the
boundary. Most "it's sandboxed" claims quietly assume A1 and then fail A2.

## What each method stops

Legend: ✅ stopped · ⚠️ partial/mitigated · ❌ not stopped.

| method | A1 accidental | A2 malicious agent | A3 malicious ext | host secrets (A1–A4) |
|--------|:---:|:---:|:---:|:---:|
| no isolation (direct on host) | ❌ | ❌ | ❌ | ❌ full `$HOME` readable |
| **Docker recommended** (`02`, mount workspace + 1 key, net open) | ⚠️ | ❌ **key is exfiltratable over the open network** (`results/11-exfil-recommended.txt`) | ❌ shares the container's grants | ✅ listed host secrets hidden |
| **Docker hardened** (`04`, `--network none --read-only --tmpfs /tmp`) | ✅ | ✅ egress blocked (`results/11-exfil-hardened.txt`) | ⚠️ can still read what's mounted | ✅ |
| **non-root hardened** (`09`, + uid 1001, caps dropped) | ✅ | ✅ + `CapEff` none, `/etc/shadow` unreadable | ⚠️ | ✅ |
| **gVisor** (`05-legion-*`) | ✅ | ✅ same class; tighter at syscall level (denies `/` writes even on a writable rootfs) | ⚠️ | ✅ |
| **secrets-broker** (`07`) | ⚠️ | ⚠️ real key never *enters* the container — placeholder only; but a pulled key can still be exfiltrated if egress is open | ⚠️ | ✅ |
| Docker Sandboxes / `sbx` | ⚠️ | ⚠️ proxy substitutes a placeholder per host | ⚠️ | ✅ best credential story |

## The two findings that reframe the table

- **"Recommended" is safe only against A1.** It hides host secrets, but a
  deliberately malicious agent (or a malicious extension, which runs *inside* the
  boundary with the same grants) can POST the one real key you passed to any
  endpoint. Measured: `results/11-exfil-recommended.txt` → `EXFIL_DELIVERED`.
- **"Hardened" does not run the product as-documented.** Under the report's exact
  `04` flags, pi crashes on startup — read-only rootfs makes `~/.pi/agent/sessions`
  unwritable (`results/10-agentic-smoke-hardened-root.txt`). A *usable* hardened
  config needs a writable agent home (tmpfs/volume); `--network none` then also
  blocks remote-model inference, so it only suits local/on-net models.

## Out of scope

- **Kernel/hypervisor exploits.** Docker shares the host kernel; a container
  escape via a kernel bug defeats every row above except gVisor/microVM. If your
  adversary is a kernel exploit, you need gVisor (`05`) or a microVM — tracked in
  `FUTURE.md`.
- **Token spend.** A sandbox does not stop an agent burning budget (it only stops
  egress and file reach).
- **Insider/other tenants.** Single-user assumption.
- **Supply chain of the sandbox image itself.** `docker/Dockerfile.pi` pulls pi +
  4 plugins at build; those are trusted by default (pin digests to harden).
- **Secrets that live only in the mounted workspace** (a committed `.env`) — the
  workspace is in-scope by design; the agent can read it.

## Practical posture

- Need remote models + real work → **recommended, but assume A2 is possible**; pass
  a scoped/throwaway key, never your primary. Best is the secrets-broker (`07`).
- Need to run untrusted code/prompts → **non-root hardened** or gVisor, with a
  writable home and a local model.
- Anything with your *real* long-lived credentials → a method whose placeholder
  story is real (`sbx`), or don't put that credential where the agent can reach it.
