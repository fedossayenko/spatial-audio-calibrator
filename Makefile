# Spatial Audio Calibrator - Development Commands
# Usage: make <target>
# Optimized for Swift 6.2 (March 2026)

# Default target
.DEFAULT_GOAL := help

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
CYAN := \033[0;36m
NC := \033[0m

# ============================================================================
# Building
# ============================================================================

.PHONY: build
build: ## Build the project
	@echo "$(BLUE)Building project with Swift 6...$(NC)"
	swift build

.PHONY: build-release
build-release: ## Build for release with optimizations
	@echo "$(BLUE)Building for release...$(NC)"
	swift build -c release

.PHONY: build-strict
build-strict: ## Build with strict concurrency checking
	@echo "$(BLUE)Building with strict concurrency...$(NC)"
	swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

.PHONY: clean
clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	swift package clean
	rm -rf .build

# ============================================================================
# Testing
# ============================================================================

.PHONY: test
test: ## Run all tests
	@echo "$(BLUE)Running tests...$(NC)"
	swift test --parallel

.PHONY: test-verbose
test-verbose: ## Run tests with verbose output
	@echo "$(BLUE)Running tests (verbose)...$(NC)"
	swift test -v

.PHONY: test-coverage
test-coverage: ## Run tests with code coverage
	@echo "$(BLUE)Running tests with coverage...$(NC)"
	swift test --parallel --enable-code-coverage
	@echo "$(GREEN)Coverage report generated in .build/debug/codecov/$(NC)"

# ============================================================================
# Static Analysis
# ============================================================================

.PHONY: lint
lint: swiftlint ## Run SwiftLint in strict mode
	@echo "$(BLUE)Running SwiftLint (strict)...$(NC)"
	swiftlint lint --strict --config .swiftlint.yml

.PHONY: lint-analyze
lint-analyze: swiftlint ## Run SwiftLint analyzer rules
	@echo "$(BLUE)Running SwiftLint analyzer...$(NC)"
	swiftlint analyze --config .swiftlint.yml

.PHONY: lint-fix
lint-fix: swiftlint ## Run SwiftLint with auto-fix
	@echo "$(BLUE)Running SwiftLint with auto-fix...$(NC)"
	swiftlint --fix --config .swiftlint.yml
	swiftlint lint --config .swiftlint.yml

.PHONY: format
format: swiftformat ## Format code with SwiftFormat
	@echo "$(BLUE)Formatting code...$(NC)"
	swiftformat Sources Tests --config .swiftformat

.PHONY: format-check
format-check: swiftformat ## Check code formatting without making changes
	@echo "$(BLUE)Checking code formatting...$(NC)"
	swiftformat --lint --dryrun Sources Tests --config .swiftformat

.PHONY: periphery
periphery: ## Run Periphery for dead code detection
	@echo "$(BLUE)Building for Periphery analysis...$(NC)"
	swift build
	@echo "$(BLUE)Running Periphery...$(NC)"
	periphery scan --config .periphery.yml --skip-build --index-store-path .build/index/store

.PHONY: analyze
analyze: lint format-check lint-analyze ## Run all static analysis checks
	@echo "$(GREEN)Static analysis complete!$(NC)"

# ============================================================================
# Security
# ============================================================================

.PHONY: security-baseline
security-baseline: ## Create/update secrets baseline
	@echo "$(BLUE)Creating secrets baseline...$(NC)"
	detect-secrets scan > .secrets.baseline
	@echo "$(GREEN)Baseline created at .secrets.baseline$(NC)"

.PHONY: security-check
security-check: ## Check for secrets in code
	@echo "$(BLUE)Checking for secrets...$(NC)"
	detect-secrets-hook --baseline .secrets.baseline $(shell git diff --name-only HEAD 2>/dev/null || echo "Sources Tests") 2>/dev/null || true

# ============================================================================
# Pre-commit
# ============================================================================

.PHONY: install-hooks
install-hooks: ## Install pre-commit hooks
	@echo "$(BLUE)Installing pre-commit hooks...$(NC)"
	pre-commit install
	pre-commit install --hook-type commit-msg
	pre-commit install --hook-type pre-push
	@echo "$(GREEN)Pre-commit hooks installed!$(NC)"

.PHONY: run-hooks
run-hooks: ## Run all pre-commit hooks on all files
	@echo "$(BLUE)Running pre-commit hooks...$(NC)"
	pre-commit run --all-files

.PHONY: update-hooks
update-hooks: ## Update pre-commit hooks to latest versions
	@echo "$(BLUE)Updating pre-commit hooks...$(NC)"
	pre-commit autoupdate

# ============================================================================
# Installation
# ============================================================================

.PHONY: install-tools
install-tools: ## Install all development tools (Homebrew required)
	@echo "$(BLUE)Installing development tools...$(NC)"
	brew install swiftlint
	brew install swiftformat
	brew install peripheryapp/periphery/periphery
	brew install pre-commit
	brew install detect-secrets
	@echo "$(GREEN)All tools installed!$(NC)"

.PHONY: install-plugins
install-plugins: ## Install Xcode plugins for SwiftFormat
	@echo "$(BLUE)Installing Xcode plugins...$(NC)"
	brew install --cask swiftformat-for-xcode
	@echo "$(GREEN)Plugins installed! Restart Xcode to activate.$(NC)"

.PHONY: check-tools
check-tools: ## Check if all tools are installed
	@echo "$(BLUE)Checking installed tools...$(NC)"
	@command -v swift >/dev/null 2>&1 && echo "$(GREEN)✓ Swift: $$(swift --version | head -1)$(NC)" || echo "$(RED)✗ Swift not found$(NC)"
	@command -v swiftlint >/dev/null 2>&1 && echo "$(GREEN)✓ SwiftLint: $$(swiftlint version)$(NC)" || echo "$(RED)✗ SwiftLint not found$(NC)"
	@command -v swiftformat >/dev/null 2>&1 && echo "$(GREEN)✓ SwiftFormat: $$(swiftformat --version)$(NC)" || echo "$(RED)✗ SwiftFormat not found$(NC)"
	@command -v periphery >/dev/null 2>&1 && echo "$(GREEN)✓ Periphery: installed$(NC)" || echo "$(RED)✗ Periphery not found$(NC)"
	@command -v pre-commit >/dev/null 2>&1 && echo "$(GREEN)✓ Pre-commit: $$(pre-commit --version 2>/dev/null | head -1)$(NC)" || echo "$(RED)✗ Pre-commit not found$(NC)"

# ============================================================================
# Git
# ============================================================================

.PHONY: setup
setup: install-tools install-hooks security-baseline ## Complete project setup for new developers
	@echo "$(GREEN)Project setup complete!$(NC)"
	@echo "$(CYAN)Run 'make check-tools' to verify installation$(NC)"

# ============================================================================
# Helpers
# ============================================================================

.PHONY: swiftlint
swiftlint:
	@command -v swiftlint >/dev/null 2>&1 || { \
		echo "$(RED)Error: swiftlint not found$(NC)"; \
		echo "Install with: brew install swiftlint"; \
		exit 1; \
	}

.PHONY: swiftformat
swiftformat:
	@command -v swiftformat >/dev/null 2>&1 || { \
		echo "$(RED)Error: swiftformat not found$(NC)"; \
		echo "Install with: brew install swiftformat"; \
		exit 1; \
	}

.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; target=""} \
		/^[a-zA-Z_-]+:.*##/ { \
			target = $$1; \
			printf "  $(BLUE)%-18s$(NC) %s\n", $$1, $$2; \
		} \
		/^## / { \
			section = substr($$0, 4); \
			if (section != prev_section) { \
				if (target != "") printf "\n"; \
				printf "$(YELLOW)%s$(NC)\n", section; \
				prev_section = section; \
			} \
		}' $(MAKEFILE_LIST)
