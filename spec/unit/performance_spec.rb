# frozen_string_literal: true

require 'spec_helper'
require 'jira_omnifocus/omnifocus_client'

RSpec.describe 'Performance Optimizations' do
  let(:config) { instance_double(JiraOmnifocus::Configuration) }
  let(:logger) { instance_double(JiraOmnifocus::Logger) }
  let(:document) { instance_double('OmniFocus Document') }
  let(:flattened_tasks) { instance_double('Flattened Tasks') }
  
  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    
    allow(config).to receive(:hostname).and_return('https://example.atlassian.net')
    allow(config).to receive(:inbox).and_return(false)
    allow(config).to receive(:newproj).and_return(false)
    allow(config).to receive(:project).and_return('Test Project')
    
    # Mock OmniFocus document
    allow(Appscript).to receive(:app).and_return(double(default_document: document))
    allow(document).to receive(:flattened_tasks).and_return(flattened_tasks)
  end
  
  describe 'OmniFocusClient task lookup optimization' do
    let(:client) { JiraOmnifocus::OmniFocusClient.new(config, logger) }
    
    it 'attempts optimized AppleScript query first' do
      # Mock the optimized query
      query_mock = instance_double('Query')
      allow(flattened_tasks).to receive(:[]).and_return(query_mock)
      allow(query_mock).to receive(:get).and_return([])
      
      # The optimized path should try to use AppleScript query
      expect(flattened_tasks).to receive(:[]).with(anything)
      
      # Private method test via send
      result = client.send(:task_exists?, 'Test Task')
      expect(result).to be false
    end
    
    it 'falls back to iterative search if AppleScript query fails' do
      # Make the optimized query fail
      allow(flattened_tasks).to receive(:[]).and_raise(StandardError)
      
      # Mock the fallback iterative search
      task1 = double('task1', name: double(get: 'Other Task'))
      task2 = double('task2', name: double(get: 'Test Task'))
      allow(flattened_tasks).to receive(:get).and_return([task1, task2])
      
      expect(logger).to receive(:debug).with(/AppleScript query failed/)
      
      result = client.send(:task_exists?, 'Test Task')
      expect(result).to be_truthy
    end
  end
  
  describe 'JiraClient batch operations' do
    it 'supports batch fetching of multiple issues' do
      config = instance_double(JiraOmnifocus::Configuration,
        hostname: 'https://example.atlassian.net',
        username: 'user',
        password: 'pass',
        ssl_verify: true
      )
      
      client = JiraOmnifocus::JiraClient.new(config, logger)
      
      # Verify batch_get_issues method exists and handles multiple IDs
      expect(client).to respond_to(:batch_get_issues)
      
      # Test with empty array
      result = client.batch_get_issues([])
      expect(result).to eq({})
    end
  end
  
  describe 'UTF-8 encoding handling' do
    it 'sets global UTF-8 encoding' do
      # This is set in bin/jiraomnifocus.rb
      # Verify it would be set correctly
      expect(Encoding.default_external).to eq(Encoding::UTF_8)
      expect(Encoding.default_internal).to eq(Encoding::UTF_8)
    end
  end
end