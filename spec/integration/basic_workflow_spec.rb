# frozen_string_literal: true

RSpec.describe 'Basic Workflow Integration' do
  let(:config) { JiraOmnifocus::Configuration.new(build(:configuration, :default)) }
  let(:logger) { JiraOmnifocus::Logger.new(quiet: true) }
  let(:jira_client) { JiraOmnifocus::JiraClient.new(config, logger) }

  let(:sample_jira_response) do
    {
      'issues' => [
        {
          'key' => 'TEST-123',
          'fields' => {
            'summary' => 'Sample test issue',
            'description' => 'This is a test issue for integration testing',
            'status' => { 'name' => 'Open' },
            'resolution' => nil,
            'assignee' => { 'name' => 'testuser' },
            'priority' => { 'name' => 'Medium' }
          }
        },
        {
          'key' => 'TEST-124',
          'fields' => {
            'summary' => 'Completed test issue',
            'description' => 'This test issue is completed',
            'status' => { 'name' => 'Done' },
            'resolution' => { 'name' => 'Fixed' },
            'assignee' => { 'name' => 'testuser' },
            'priority' => { 'name' => 'High' }
          }
        }
      ],
      'total' => 2
    }
  end

  before do
    stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
      .to_return(
        status: 200,
        body: sample_jira_response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe 'JIRA client integration with configuration' do
    it 'successfully fetches and parses JIRA issues' do
      issues = jira_client.get_issues

      expect(issues).to be_a(Hash)
      expect(issues.size).to eq(2)
      expect(issues).to have_key('TEST-123')
      expect(issues).to have_key('TEST-124')

      # Verify issue data structure
      test_123 = issues['TEST-123']
      expect(test_123['fields']['summary']).to eq('Sample test issue')
      expect(test_123['fields']['assignee']['name']).to eq('testuser')
    end

    it 'handles authentication properly' do
      jira_client.get_issues

      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(headers: {
          'Authorization' => /Basic/,
          'User-Agent' => /jira-omnifocus/
        })
    end

    it 'respects configuration settings' do
      jira_client.get_issues

      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(query: hash_including(
          'jql' => config.filter,
          'maxResults' => '-1'
        ))
    end
  end

  describe 'batch operations integration' do
    let(:batch_issue_keys) { ['TEST-123', 'TEST-124', 'TEST-125'] }
    let(:batch_response) do
      {
        'issues' => [
          {
            'key' => 'TEST-123',
            'fields' => {
              'resolution' => nil,
              'assignee' => { 'name' => 'testuser' }
            }
          },
          {
            'key' => 'TEST-124',
            'fields' => {
              'resolution' => { 'name' => 'Fixed' },
              'assignee' => { 'name' => 'testuser' }
            }
          }
        ]
      }
    end

    before do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .with(query: hash_including('jql' => /key in \(/))
        .to_return(
          status: 200,
          body: batch_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'efficiently processes batch status requests' do
      statuses = jira_client.batch_get_issues(batch_issue_keys)

      expect(statuses).to be_a(Hash)
      expect(statuses).to have_key('TEST-123')
      expect(statuses).to have_key('TEST-124')

      expect(statuses['TEST-123'][:resolution]).to be_nil
      expect(statuses['TEST-124'][:resolution]).to eq('name' => 'Fixed')
    end

    it 'constructs proper batch JQL query' do
      jira_client.batch_get_issues(batch_issue_keys)

      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(query: hash_including(
          'jql' => 'key in (TEST-123,TEST-124,TEST-125)',
          'fields' => 'resolution,assignee'
        ))
    end
  end

  describe 'error handling integration' do
    it 'handles HTTP errors with proper logging' do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_return(status: 401, body: 'Unauthorized')

      expect(logger).to receive(:error).with(/Failed to retrieve JIRA issues/)

      expect { jira_client.get_issues }.to raise_error(/HTTP 401/)
    end

    it 'handles network timeouts gracefully' do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_timeout

      expect { jira_client.get_issues }.to raise_error(Net::OpenTimeout)
    end

    it 'handles malformed JSON responses' do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_return(status: 200, body: 'Invalid JSON Response')

      expect(logger).to receive(:error).with(/Failed to parse JIRA response/)
      expect { jira_client.get_issues }.to raise_error(JSON::ParserError)
    end
  end

  describe 'logging integration' do
    let(:logger) { JiraOmnifocus::Logger.new(level: :debug, quiet: false) }

    it 'provides comprehensive debug logging' do
      expect(logger).to receive(:debug).at_least(5).times
      expect(logger).to receive(:info).at_least(1).times

      jira_client.get_issues
    end

    it 'logs important debug information' do
      expect(logger).to receive(:debug).at_least(:once)
      expect(logger).to receive(:info).at_least(:once)

      jira_client.get_issues
    end
  end

  describe 'configuration and validation integration' do
    it 'validates configuration before making requests' do
      invalid_config_data = build(:configuration, :default).merge(
        hostname: 'http://please-configure-me.atlassian.net'
      )

      expect {
        JiraOmnifocus::Configuration.new(invalid_config_data)
      }.to raise_error(JiraOmnifocus::Validation::ValidationError, /Please configure your JIRA hostname/)
    end

    it 'sanitizes JQL queries to prevent injection' do
      dangerous_jql = 'project = TEST; DROP TABLE--'
      sanitized = JiraOmnifocus::Validation.sanitize_jql(dangerous_jql)

      expect(sanitized).not_to include(';')
      expect(sanitized).to eq('project = TEST DROP TABLE--')
    end

    it 'validates hostnames properly' do
      valid_hostname = 'https://company.atlassian.net'
      result = JiraOmnifocus::Validation.validate_hostname!(valid_hostname)
      expect(result).to eq(valid_hostname)

      expect {
        JiraOmnifocus::Validation.validate_hostname!('invalid-url')
      }.to raise_error(JiraOmnifocus::Validation::ValidationError)
    end
  end
end