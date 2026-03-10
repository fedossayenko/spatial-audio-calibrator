# Spatial Audio Calibrator - Development Commands
# Usage: make <target>

# Default target
.DEFAULT_GOAL := help

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m

# ============================================================================
# Building
# ============================================================================

.PHONY: build
build: ## Build the project
	@echo "$(BLUE)Building project...$(NC)"
	swift build

.PHONY: build-release
build-release: ## Build for release
	@echo "$(BLUE)Building for release...$(NC)"
	swift build -c release

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
	swift test

.PHONY: test-verbose
test-verbose: ## Run tests with verbose output
	@echo "$(BLUE)Running tests (verbose)...$(NC)"
	swift test -v

# ============================================================================
# Static Analysis
# ============================================================================

.PHONY: lint
lint: swiftlint ## Run SwiftLint
	@echo "$(BLUE)Running SwiftLint...$(NC)"
	swiftlint lint --strict

.PHONY: lint-fix
lint-fix: swiftlint ## Run SwiftLint with auto-fix
	@echo "$(BLUE)Running SwiftLint with auto-fix...$(NC)"
	swiftlint --fix
	swiftlint lint

.PHONY: format
format: swiftformat ## Format code with SwiftFormat
	@echo "$(BLUE)Formatting code...$(NC)"
	swiftformat Sources Tests

.PHONY: format-check
format-check: swiftformat ## Check code formatting without making changes
	@echo "$(BLUE)Checking code formatting...$(NC)"
	swiftformat --lint --dryrun Sources Tests

.PHONY: periphery
periphery: ## Run Periphery for dead code detection (requires installation)
	@echo "$(BLUE)Running Periphery...$(NC)"
	periphery scan --config .periphery.yml

.PHONY: analyze
analyze: lint format-check ## Run all static analysis checks
	@echo "$(GREEN)Static analysis complete!$(NC)"

# ============================================================================
# Pre-commit
# ============================================================================

.PHONY: install-hooks
install-hooks: ## Install pre-commit hooks
	@echo "$(BLUE)Installing pre-commit hooks...$(NC)"
	pre-commit install
	pre-commit install --hook-type commit-msg

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
	@echo "$(GREEN)All tools installed!$(NC)"

.PHONY: install-plugins
install-plugins: ## Install Xcode plugins for SwiftFormat
	@echo "$(BLUE)Installing Xcode plugins...$(NC)"
	brew install --cask swiftformat-for-xcode
	@echo "$(GREEN)Plugins installed! Restart Xcode to activate.$(NC)"

# ============================================================================
# Git
# ============================================================================

.PHONY: setup
setup: install-tools install-hooks ## Complete project setup for new developers
	@echo "$(GREEN)Project setup complete!$(NC)"

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
			printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2; \
		} \
		/^## / { \
			section = substr($$0, 4); \
			if (section != prev_section) { \
				if (target != "") printf "\n"; \
				printf "$(YELLOW)%s$(NC)\n", section; \
				prev_section = section; \
			} \
		}' $(MAKEFILE_LIST)
