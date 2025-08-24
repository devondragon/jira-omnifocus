# frozen_string_literal: true

# Coverage reporting
require 'simplecov'
require 'simplecov-console'

# Start coverage reporting
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console
  ])

  add_filter '/spec/'
  add_filter '/vendor/'
  add_group 'Libraries', 'lib'
  
  # Coverage thresholds
  minimum_coverage 90
  minimum_coverage_by_file 80
end

# Load our application
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'jira_omnifocus'

# Testing support gems
require 'webmock/rspec'
require 'vcr'
require 'factory_bot'
require 'faker'
require 'timecop'

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

# Configure VCR for HTTP interaction recording
VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.default_cassette_options = { record: :once }
  config.configure_rspec_metadata!
  
  # Filter sensitive data
  config.filter_sensitive_data('<JIRA_USERNAME>') { ENV['JIRA_USERNAME'] }
  config.filter_sensitive_data('<JIRA_PASSWORD>') { ENV['JIRA_PASSWORD'] }
  config.filter_sensitive_data('<JIRA_HOSTNAME>') { ENV['JIRA_HOSTNAME'] }
end

# RSpec configuration
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure FactoryBot
  config.include FactoryBot::Syntax::Methods

  # Setup and teardown
  config.before(:suite) do
    FactoryBot.find_definitions
  end

  config.before(:each) do
    # Reset time for each test
    Timecop.return
    
    # Clear any cached configuration
    # This ensures tests start with clean state
  end

  config.after(:each) do
    # Clean up time mocking
    Timecop.return
  end

  # Shared examples and contexts
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Filter run when only examples are selected
  config.filter_run_when_matching :focus

  # Allow more verbose output when running an individual spec file
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  # Print the 10 slowest examples and example groups
  config.profile_examples = 10

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Configure output format
  config.formatter = :progress
end