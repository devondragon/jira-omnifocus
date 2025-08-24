# frozen_string_literal: true

require_relative 'jira_omnifocus/version'
require_relative 'jira_omnifocus/validation'
require_relative 'jira_omnifocus/configuration'
require_relative 'jira_omnifocus/logger'
require_relative 'jira_omnifocus/jira_client'
require_relative 'jira_omnifocus/omnifocus_client'
require_relative 'jira_omnifocus/task_synchronizer'
require_relative 'jira_omnifocus/cli'

module JiraOmnifocus
  # Main entry point for the application
  def self.run(args = ARGV)
    CLI.new.run(args)
  rescue StandardError => e
    warn "Error: #{e.message}"
    exit 1
  end
end