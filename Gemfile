# frozen_string_literal: true

ruby '>= 3.2.0'

source 'https://rubygems.org'

# Core dependencies with version constraints
gem 'highline', '~> 3.0'        # 2.0.2 → 3.0+ (Unicode support)
gem 'json', '~> 2.7'            # 2.3.0 → 2.7+ (performance, security)
gem 'optimist', '~> 3.1'        # 3.0.0 → 3.1+ (bug fixes)

# macOS-specific dependencies
gem 'rb-scpt', '~> 1.0.3' # AppleScript bridge (no updates)
gem 'ruby-keychain', '~> 0.3.2', require: 'keychain' # Keychain integration
gem 'terminal-notifier', '~> 2.0.0' # 2.0.0 → 2.0.0 (macOS compatibility)

# Development and quality tools
group :development, :test do
  gem 'bundler-audit', '~> 0.9'
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.60'
  gem 'rubocop-performance', '~> 1.20'
  gem 'rubocop-rspec', '~> 3.0'
  gem 'yard', '~> 0.9'
  
  # Testing framework enhancements
  gem 'webmock', '~> 3.18'        # HTTP request mocking
  gem 'vcr', '~> 6.2'             # HTTP interaction recording
  gem 'simplecov', '~> 0.22'      # Code coverage reporting
  gem 'simplecov-console', '~> 0.9' # Console coverage output
  gem 'factory_bot', '~> 6.4'     # Test data factories
  gem 'faker', '~> 3.2'           # Fake data generation
  gem 'timecop', '~> 0.9'         # Time mocking for tests
end
