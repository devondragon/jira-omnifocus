# frozen_string_literal: true

require 'spec_helper'
require 'jira_omnifocus/jira_client'
require 'jira_omnifocus/configuration'

RSpec.describe 'Security Features' do
  let(:logger) { instance_double(JiraOmnifocus::Logger) }
  
  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe 'HTTPS enforcement' do
    it 'raises an error when using HTTP instead of HTTPS' do
      config = instance_double(JiraOmnifocus::Configuration,
        hostname: 'http://example.atlassian.net',
        username: 'user',
        password: 'pass',
        ssl_verify: true
      )
      
      expect {
        JiraOmnifocus::JiraClient.new(config, logger)
      }.to raise_error(RuntimeError, /JIRA hostname must use HTTPS/)
    end
    
    it 'allows HTTPS connections' do
      config = instance_double(JiraOmnifocus::Configuration,
        hostname: 'https://example.atlassian.net',
        username: 'user', 
        password: 'pass',
        ssl_verify: true
      )
      
      # Should not raise an error
      expect {
        JiraOmnifocus::JiraClient.new(config, logger)
      }.not_to raise_error
    end
  end
  
  describe 'SSL verification' do
    it 'logs a security warning when SSL verification is disabled' do
      config = instance_double(JiraOmnifocus::Configuration,
        hostname: 'https://example.atlassian.net',
        username: 'user',
        password: 'pass', 
        ssl_verify: false
      )
      
      expect(logger).to receive(:error).with(/SECURITY WARNING.*SSL verification is disabled/)
      expect(logger).to receive(:error).with(/Only use this for testing/)
      
      JiraOmnifocus::JiraClient.new(config, logger)
    end
    
    it 'does not log warnings when SSL verification is enabled' do
      config = instance_double(JiraOmnifocus::Configuration,
        hostname: 'https://example.atlassian.net',
        username: 'user',
        password: 'pass',
        ssl_verify: true
      )
      
      expect(logger).not_to receive(:error)
      
      JiraOmnifocus::JiraClient.new(config, logger)
    end
  end
  
  describe 'Configuration defaults' do
    it 'uses HTTPS by default for hostname' do
      # Test will fail with validation error for default hostname, that's expected
      expect {
        config = JiraOmnifocus::Configuration.new
      }.to raise_error(JiraOmnifocus::Validation::ValidationError)
      
      # Test the default config method directly
      default = JiraOmnifocus::Configuration.default_config
      expect(default['jira']['hostname']).to start_with('https://')
    end
    
    it 'enables SSL verification by default' do
      default = JiraOmnifocus::Configuration.default_config
      expect(default['jira']['ssl_verify']).to be true
    end
  end
  
  describe 'Keychain integration' do
    it 'supports keychain for credential storage' do
      # Need to provide valid hostname to avoid validation error
      config = JiraOmnifocus::Configuration.new(
        hostname: 'https://example.atlassian.net',
        usekeychain: true,
        username: 'test',
        password: 'test'
      )
      expect(config.use_keychain?).to be true
    end
    
    it 'does not expose password in to_s output' do
      config = JiraOmnifocus::Configuration.new(
        hostname: 'https://example.atlassian.net',
        password: 'supersecret123',
        username: 'user'
      )
      
      output = config.to_s
      expect(output).to include('[REDACTED]')
      expect(output).not_to include('supersecret123')
    end
  end
  
  describe 'Timeout constants' do
    it 'uses defined timeout constants' do
      expect(JiraOmnifocus::JiraClient::READ_TIMEOUT).to eq(30)
      expect(JiraOmnifocus::JiraClient::OPEN_TIMEOUT).to eq(10)
    end
  end
end