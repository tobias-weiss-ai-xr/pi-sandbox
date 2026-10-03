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

.PHONY: help image verify check probes smoke exfil sandbox example lint clean

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

image: ## build the sandbox image
	docker build -t pi-sandbox -f docker/Dockerfile.pi .

verify: ## assert the bundled plugins load (needs the image)
	bash $(HARNESS)/check-sandbox-plugins.sh

check: ## assert committed results still satisfy their invariants (no Docker)
	bash $(HARNESS)/check-invariants.sh

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

lint: ## shellcheck (if installed) + bash -n on all scripts
	@for f in $(HARNESS)/*.sh examples/*/*.sh; do \
	  if command -v shellcheck >/dev/null 2>&1; then shellcheck -S error -e SC2086 "$$f" || exit 1; \
	  else bash -n "$$f" || exit 1; fi; \
	done
	@echo "lint: OK"

clean: ## remove scratch outputs and the persistent agent-home volume
	rm -rf scratch/exfil scratch/smoke-*.txt
	docker volume rm pi-home >/dev/null 2>&1 || true
	@echo "clean: done"