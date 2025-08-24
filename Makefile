# Makefile for jira-omnifocus development

.PHONY: help install test lint security coverage clean release setup dev

# Default target
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Development setup
setup: ## Initial development environment setup
	@echo "Setting up development environment..."
	gem install bundler
	bundle install
	@echo "✅ Development environment ready!"

install: ## Install dependencies
	bundle install

# Testing
test: ## Run the test suite
	bundle exec rspec

test-verbose: ## Run tests with verbose output
	bundle exec rspec --format documentation

test-coverage: ## Run tests with coverage report
	COVERAGE=true bundle exec rspec

test-integration: ## Run integration tests only
	bundle exec rspec spec/integration/

test-unit: ## Run unit tests only  
	bundle exec rspec spec/unit/

# Code quality
lint: ## Run RuboCop linter
	bundle exec rubocop

lint-fix: ## Run RuboCop with auto-corrections
	bundle exec rubocop --autocorrect

lint-fix-all: ## Run RuboCop with all auto-corrections
	bundle exec rubocop --autocorrect-all

# Security
security: ## Run security audit
	bundle exec bundler-audit --update

security-check: ## Check for vulnerabilities without updating
	bundle exec bundler-audit

# Documentation
docs: ## Generate documentation
	bundle exec yard doc

docs-server: ## Start documentation server
	bundle exec yard server --reload

# Development
dev: ## Run the script in development mode
	DEBUG=true bundle exec bin/jiraomnifocus.rb

dry-run: ## Test script without making changes (if supported)
	DRY_RUN=true bundle exec bin/jiraomnifocus.rb

validate: ## Validate script syntax
	bundle exec ruby -c bin/jiraomnifocus.rb

# Release preparation
check-release: ## Run all checks before release
	@echo "Running pre-release checks..."
	$(MAKE) test
	$(MAKE) lint
	$(MAKE) security
	$(MAKE) validate
	@echo "✅ All pre-release checks passed!"

version: ## Show current version
	@bundle exec ruby -e "require './lib/jira_omnifocus/version'; puts JiraOmnifocus::VERSION"

# Maintenance
clean: ## Clean up temporary files
	rm -rf coverage/
	rm -rf tmp/
	rm -rf .yardoc/
	rm -rf doc/

update-deps: ## Update dependencies
	bundle update

outdated: ## Check for outdated dependencies
	bundle outdated

# CI simulation
ci-test: ## Simulate CI test environment
	@echo "Simulating CI environment..."
	COVERAGE=false $(MAKE) test
	$(MAKE) lint
	$(MAKE) security
	@echo "✅ CI simulation completed!"

# Quick development cycle
quick: ## Quick development check (fast)
	$(MAKE) lint-fix
	$(MAKE) test-unit
	$(MAKE) validate

# Full development cycle  
full: ## Full development check (comprehensive)
	$(MAKE) lint-fix
	$(MAKE) test-coverage
	$(MAKE) security
	$(MAKE) docs

# Git hooks simulation
pre-commit: ## Simulate pre-commit hook
	$(MAKE) lint
	$(MAKE) test-unit

pre-push: ## Simulate pre-push hook  
	$(MAKE) check-release