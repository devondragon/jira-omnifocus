#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

# Add lib to load path
lib_path = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

require 'jira_omnifocus'

# Check for debug mode from environment
ENV['DEBUG'] = '1' if ARGV.include?('--debug') || ENV['DEBUG']

# Run the application
JiraOmnifocus.run(ARGV)