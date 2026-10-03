# pi-sandbox — one-command entry points.
#
#   make image     build pi-sandbox:latest
#   make verify    assert the 4 bundled plugins load (9 checks)
#   make check     assert the committed results still hold (grep invariants)
#   make probes    regenerate Docker probe results on this POSIX host
#   make smoke     run pi as an agent per config (needs SAIA_API_KEY)
#   make exfil     measure real-key exfiltration per config
#   make sandbox   interactive non-root sandbox with $PWD mounted
#   make lint      shellcheck (if present) + bash -n on all harness scripts
#
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
HARNESS := harness

.PHONY: help image verify check test probes smoke exfil sandbox example probe-seccomp lint lint-meta scan clean


help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

image: ## build the sandbox image
	docker build -t pi-sandbox -f docker/Dockerfile.pi .

verify: ## assert the bundled plugins load (needs the image)
	bash $(HARNESS)/check-sandbox-plugins.sh

check: ## assert committed results still satisfy their invariants (no Docker)
	bash $(HARNESS)/check-invariants.sh

test: ## unit-test probe.sh behavior in a controlled container (needs the image)
	bash $(HARNESS)/test-harness.sh

probes: ## regenerate Docker probe results on this host (macOS/Linux)
	bash $(HARNESS)/run-docker-probes-macos.sh

smoke: ## run pi as an agent per config (requires SAIA_API_KEY + image)
	bash $(HARNESS)/smoke-agentic.sh

exfil: ## measure real-key exfiltration per config (requires the image)
	bash $(HARNESS)/exfil-probe.sh

sandbox: ## interactive non-root sandbox with the current dir mounted
	bash $(HARNESS)/run.sh

example: ## develop a skeleton-research repo inside the sandbox (demo, no model)
	bash examples/research-repo/run.sh --demo

probe-seccomp: ## isolate a seccomp profile + tmpfs noexec (results/13-*)
	bash $(HARNESS)/run-seccomp-demo.sh

lint: ## shellcheck (local → docker → bash -n fallback) on all scripts
	@FILES="$$(find $(HARNESS) examples -name '*.sh' | sort)"; \
	if command -v shellcheck >/dev/null 2>&1; then \
	  echo "lint: using local shellcheck"; shellcheck -S error -e SC2086 $$FILES || exit 1; \
	elif docker info >/dev/null 2>&1; then \
	  echo "lint: local shellcheck absent; using docker image koalaman/shellcheck"; \
	  docker run --rm -v "$$(pwd):/w" -w /w koalaman/shellcheck -S error -e SC2086 $$FILES || exit 1; \
	else \
	  echo "lint: shellcheck unavailable; bash -n only"; \
	  for f in $$FILES; do bash -n "$$f" || exit 1; done; \
	fi
	@if command -v hadolint >/dev/null 2>&1; then \
	  echo "lint: hadolint (local)"; hadolint docker/Dockerfile.pi || exit 1; \
	elif docker info >/dev/null 2>&1; then \
	  echo "lint: hadolint via docker"; \
	  docker run --rm -v "$$(pwd):/w" -w /w hadolint/hadolint hadolint docker/Dockerfile.pi || exit 1; \
	else echo "lint: hadolint skipped (unavailable)"; fi
	@echo "lint: OK"

clean: ## remove scratch outputs and the persistent agent-home volume
	rm -rf scratch/exfil scratch/smoke-*.txt
	docker volume rm pi-home >/dev/null 2>&1 || true
	@echo "clean: done"

lint-meta: ## lint workflows (actionlint) + YAML (yamllint) + Markdown (markdownlint) via docker
	@echo "lint-meta: actionlint"; docker run --rm -v "$$(pwd):/w" -w /w rhysd/actionlint:latest -color || exit 1
	@echo "lint-meta: yamllint"; docker run --rm -v "$$(pwd):/w" -w /w cytopia/yamllint:latest -c .yamllint -f parsable .github || exit 1
	@echo "lint-meta: markdownlint (advisory)"; docker run --rm -v "$$(pwd):/w" -w /w davidanson/markdownlint-cli2:v0.17.2 || true
	@echo "lint-meta: OK"

scan: ## trivy image scan (fail on CRITICAL/HIGH with a fix available)
	@if command -v trivy >/dev/null 2>&1; then \
	  trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --format table pi-sandbox; \
	elif docker info >/dev/null 2>&1; then \
	  echo "scan: trivy via docker (expects the daemon socket); run on a native-Linux host or CI"; \
	  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --format table pi-sandbox; \
	else echo "scan: trivy unavailable"; exit 2; fi
