# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

jira-omnifocus is a macOS-only Ruby application that syncs JIRA tickets with OmniFocus tasks. The project has been modernized with Ruby 3.4+ support, comprehensive test coverage (84 tests), and modern CI/CD practices.

**Platform**: macOS only (OmniFocus and AppleScript dependencies)  
**Ruby Version**: 3.2+ required (3.4 supported)  
**Default Branch**: `main`

## Development Commands

### Quick Start with Makefile
```bash
# Initial setup
make setup

# Run tests
make test                  # Run all tests
make test-unit            # Unit tests only
make test-integration     # Integration tests only
make test-coverage        # With coverage report

# Code quality
make lint                 # Run RuboCop
make lint-fix            # Auto-fix violations
make security            # Security audit

# Development
make dev                  # Run with debug output
make validate            # Validate script syntax
make check-release        # Run all pre-release checks
```

### Manual Commands
```bash
# Install dependencies
bundle install

# Run the script
bundle exec bin/jiraomnifocus.rb
DEBUG=true bundle exec bin/jiraomnifocus.rb

# Run specific tests
bundle exec rspec spec/unit/jira_client_spec.rb
COVERAGE=false bundle exec rspec --format documentation
```

## Architecture

### Refactored Module Structure

**lib/jira_omnifocus/**
- `jira_client.rb` - JIRA API communication with HTTPS enforcement
- `omnifocus_client.rb` - OmniFocus AppleScript integration with optimized lookups
- `configuration.rb` - Config management with validation and Keychain support
- `logger.rb` - Structured logging with multiple levels
- `validation.rb` - Input validation and sanitization
- `version.rb` - Version management

**bin/jiraomnifocus.rb**
- Main entry point (~450 lines)
- Orchestrates sync between JIRA and OmniFocus
- Uses extracted modules for cleaner separation

### Key Architectural Patterns

1. **Security First**: HTTPS enforced, SSL verification warnings, Keychain integration
2. **Performance Optimized**: AppleScript queries for O(1) lookups vs O(n) iteration
3. **Error Handling**: Comprehensive error catching with user notifications
4. **Modular Design**: Extracted concerns into focused modules

### Configuration

Config file: `~/.jofsync.yaml`
- JIRA settings: hostname, credentials, JQL filter
- OmniFocus settings: project, tag, folder, inbox mode
- Security: Keychain support recommended over plaintext passwords

## Test Infrastructure

### Test Coverage
- **Unit Tests**: 75+ tests covering all modules
- **Integration Tests**: Task synchronization workflows
- **Security Tests**: HTTPS enforcement, SSL verification
- **Performance Tests**: Benchmark suite

### Running Tests
```bash
# Full test suite with coverage
bundle exec rspec

# Specific test file
bundle exec rspec spec/unit/security_spec.rb

# Without coverage overhead
COVERAGE=false bundle exec rspec
```

## CI/CD Pipeline

### GitHub Actions Workflows
- **test.yml**: Matrix testing on Ruby 3.2, 3.3, 3.4 (macOS only)
- **rubocop-analysis.yml**: Security and code quality scanning
- **dependencies.yml**: Vulnerability monitoring with bundler-audit
- **changelog.yml**: Automated changelog generation
- **docs.yml**: Documentation generation and coverage

### Pre-Release Checks
```bash
make check-release  # Runs all validation steps
```

## Security Considerations

1. **HTTPS Required**: HTTP connections rejected with clear error
2. **SSL Verification**: Enabled by default, warning logged if disabled
3. **Keychain Storage**: Recommended for credentials
4. **No Secrets in Code**: Configuration separated from codebase
5. **Dependency Scanning**: Automated vulnerability checks in CI

## Performance Optimizations

1. **AppleScript Queries**: Direct OmniFocus queries instead of iteration
2. **Batch Operations**: `batch_get_issues` for multiple JIRA tickets
3. **UTF-8 Encoding**: Global encoding set for consistency
4. **Timeout Constants**: Configurable HTTP timeouts (30s read, 10s open)

## Common Issues and Solutions

### SSL Connection Errors
- Update to Ruby 3.2+ for modern cipher support
- Verify JIRA hostname uses HTTPS
- Check SSL certificate validity

### Keychain Access
```bash
# Add credentials to Keychain
security add-internet-password -a <username> -s <hostname> -w <password>

# Must use launchd (not cron) for Keychain access
```

### OmniFocus Integration
- Requires OmniFocus 3+ installed
- AppleScript access must be enabled in System Preferences
- Tasks identified by name uniqueness