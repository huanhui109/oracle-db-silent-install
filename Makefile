SHELL := /bin/bash
VERSION := $(shell cat VERSION)
SKILL_NAME := oracle-db-silent-install

.PHONY: help test lint plan examples install-skill package clean

help: ## Show available targets
	@printf '%s\n' 'oracle-db-silent-install — available targets'
	@printf '%s\n' ''
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  %-16s %s\n", $$1, $$2}'
	@printf '%s\n' ''
	@printf 'version %s\n' '$(VERSION)'

test: ## Run the offline test suite
	@bash tests/run_tests.sh $(if $(FILTER),$(FILTER),)

lint: ## bash -n on every script, plus shellcheck when installed
	@for f in scripts/*.sh tests/*.sh; do bash -n "$$f" || exit 1; done
	@printf 'bash -n: all scripts parse\n'
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -S warning -x scripts/*.sh tests/*.sh && printf 'shellcheck: clean\n'; \
	else printf 'shellcheck: not installed (skipped)\n'; fi

plan: ## Print the 19c plan sheet
	@bash scripts/show_plan.sh 19c

examples: ## Regenerate the 19c example artifacts from parameters.env
	@cd examples/19c-minimal-centos79 && set -a && . ./parameters.env && set +a && \
	  bash ../../scripts/gen_env_file.sh bash_profile.block "$$VERSION" >/dev/null && \
	  bash ../../scripts/gen_root_prep.sh "$$VERSION" > root_prep.sh && \
	  bash ../../scripts/gen_dbca_rsp.sh dbca.rsp "$$VERSION" > dbca.rsp.receipt && \
	  TNS_OUT=tnsnames.ora bash ../../scripts/gen_listener_ora.sh listener.ora > listener.ora.receipt && \
	  bash ../../scripts/show_plan.sh "$$VERSION" > "plan-$$VERSION.txt"
	@printf 'examples regenerated\n'

install-skill: ## Install as a skill: make install-skill DEST=~/.claude/skills
	@d="$(DEST)"; \
	if [ -z "$$d" ] || [ "$$d" = "/" ] || [ "$$d" = "$$HOME" ]; then \
	  printf 'DEST must be a skills directory (e.g. ~/.claude/skills), got "%s"\n' "$$d" >&2; \
	  exit 2; \
	fi; \
	mkdir -p "$$d"; \
	rm -rf "$$d/$(SKILL_NAME)"; \
	cp -R . "$$d/$(SKILL_NAME)"; \
	rm -rf "$$d/$(SKILL_NAME)/.git" "$$d/$(SKILL_NAME)/dist"; \
	find "$$d/$(SKILL_NAME)/scripts" -name '*.sh' -exec chmod +x {} +; \
	printf 'installed to %s/%s\n' "$$d" '$(SKILL_NAME)'

package: ## Build a distributable zip in dist/
	@mkdir -p dist
	@rm -f "dist/$(SKILL_NAME)-$(VERSION).zip"
	@zip -qr "dist/$(SKILL_NAME)-$(VERSION).zip" . \
	  -x '.git/*' 'dist/*' '*.DS_Store' '*/.DS_Store'
	@printf 'built dist/%s-%s.zip\n' '$(SKILL_NAME)' '$(VERSION)'

clean: ## Remove build output and test residue
	@rm -rf dist
	@find . -name '*.bak.*' -not -path './.git/*' -delete
	@printf 'cleaned\n'
