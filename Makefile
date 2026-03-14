.PHONY: lint format test help

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk -F ':|##' '{printf "%-10s %s\n", $$1, $$3}'

lint: ## check formatting with stylua
	stylua --check lua/

format: ## auto-fix formatting with stylua
	stylua lua/

test: ## run the test suite
	nvim --version
	nvim -l tests/minit.lua
