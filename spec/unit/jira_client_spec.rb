# frozen_string_literal: true

RSpec.describe JiraOmnifocus::JiraClient do
  let(:config) do
    double('Configuration',
      hostname: 'https://test.atlassian.net',
      username: 'testuser',
      password: 'testpass',
      filter: 'assignee = currentUser()',
      ssl_verify: true
    )
  end
  let(:logger) { double('Logger', debug: nil, info: nil, warn: nil, error: nil) }
  let(:client) { described_class.new(config, logger) }
  
  describe '#initialize' do
    it 'sets up HTTP client with SSL verification' do
      expect(client.instance_variable_get(:@config)).to eq(config)
      expect(client.instance_variable_get(:@logger)).to eq(logger)
      
      http_client = client.instance_variable_get(:@http_client)
      expect(http_client.use_ssl?).to be true
      expect(http_client.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
    end
    
    it 'disables SSL verification when configured' do
      allow(config).to receive(:ssl_verify).and_return(false)
      client = described_class.new(config, logger)
      
      http_client = client.instance_variable_get(:@http_client)
      expect(http_client.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
    end
    
    it 'sets appropriate timeouts' do
      http_client = client.instance_variable_get(:@http_client)
      expect(http_client.read_timeout).to eq(30)
      expect(http_client.open_timeout).to eq(10)
    end
  end
  
  describe '#get_issues' do
    let(:jira_response) do
      {
        'issues' => [
          build(:jira_issue, key: 'TEST-1'),
          build(:jira_issue, key: 'TEST-2')
        ],
        'total' => 2
      }
    end
    
    before do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_return(
          status: 200,
          body: jira_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end
    
    it 'fetches issues from JIRA API' do
      issues = client.get_issues
      
      expect(issues).to have_key('TEST-1')
      expect(issues).to have_key('TEST-2')
      expect(issues.size).to eq(2)
    end
    
    it 'makes authenticated request with correct parameters' do
      client.get_issues
      
      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(
          headers: { 'Authorization' => /Basic/ },
          query: hash_including(
            'jql' => 'assignee = currentUser()',
            'maxResults' => '-1'
          )
        )
    end
    
    it 'includes User-Agent header' do
      client.get_issues
      
      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(headers: { 'User-Agent' => "jira-omnifocus/#{JiraOmnifocus::VERSION}" })
    end
    
    it 'logs successful connection' do
      client.get_issues
      
      expect(logger).to have_received(:info).with(/Connected successfully/)
    end
    
    it 'logs debug information' do
      client.get_issues
      
      expect(logger).to have_received(:debug).with(/Starting JIRA issue retrieval/)
      expect(logger).to have_received(:debug).with(/Response parsed successfully/)
    end
    
    it 'handles HTTP errors gracefully' do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_return(status: 401, body: 'Unauthorized')
      
      expect { client.get_issues }
        .to raise_error(/HTTP 401/)
      
      expect(logger).to have_received(:error).with(/Failed to retrieve JIRA issues/)
    end
    
    it 'handles JSON parsing errors' do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_return(status: 200, body: 'Invalid JSON')
      
      expect { client.get_issues }
        .to raise_error(JSON::ParserError)
      
      expect(logger).to have_received(:error).with(/Failed to parse JIRA response/)
    end
  end
  
  describe '#batch_get_issues' do
    let(:jira_ids) { %w[TEST-1 TEST-2 TEST-3] }
    let(:batch_response) do
      {
        'issues' => [
          {
            'key' => 'TEST-1',
            'fields' => {
              'resolution' => nil,
              'assignee' => { 'name' => 'testuser' }
            }
          },
          {
            'key' => 'TEST-2',
            'fields' => {
              'resolution' => { 'name' => 'Done' },
              'assignee' => { 'name' => 'testuser' }
            }
          }
        ]
      }
    end
    
    before do
      stub_request(:get, %r{https://test\.atlassian\.net/rest/api/2/search})
        .to_return(
          status: 200,
          body: batch_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end
    
    it 'fetches status for multiple issues' do
      statuses = client.batch_get_issues(jira_ids)
      
      expect(statuses).to have_key('TEST-1')
      expect(statuses).to have_key('TEST-2')
      
      expect(statuses['TEST-1'][:resolution]).to be_nil
      expect(statuses['TEST-2'][:resolution]).to eq('name' => 'Done')
    end
    
    it 'constructs proper JQL query' do
      client.batch_get_issues(jira_ids)
      
      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(query: hash_including('jql' => 'key in (TEST-1,TEST-2,TEST-3)'))
    end
    
    it 'requests only necessary fields' do
      client.batch_get_issues(jira_ids)
      
      expect(WebMock).to have_requested(:get, %r{/rest/api/2/search})
        .with(query: hash_including('fields' => 'resolution,assignee'))
    end
    
    it 'returns empty hash for empty input' do
      expect(client.batch_get_issues([])).to eq({})
    end
    
    it 'logs batch operation details' do
      client.batch_get_issues(jira_ids)
      
      expect(logger).to have_received(:debug)
        .with(/Batch fetching status for 3 JIRA issues/)
      expect(logger).to have_received(:debug)
        .with(/Batch fetch complete, retrieved \d+ issue statuses/)
    end
  end
  
  describe '#get_issue_details' do
    let(:issue_key) { 'TEST-123' }
    let(:issue_response) do
      {
        'key' => issue_key,
        'fields' => {
          'summary' => 'Test issue',
          'description' => 'Test description',
          'status' => { 'name' => 'Open' }
        }
      }
    end
    
    before do
      stub_request(:get, "https://test.atlassian.net/rest/api/2/issue/#{issue_key}")
        .to_return(
          status: 200,
          body: issue_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end
    
    it 'fetches single issue details' do
      issue = client.get_issue_details(issue_key)
      
      expect(issue['key']).to eq(issue_key)
      expect(issue['fields']['summary']).to eq('Test issue')
    end
    
    it 'makes authenticated request' do
      client.get_issue_details(issue_key)
      
      expect(WebMock).to have_requested(:get, /issue\/#{issue_key}/)
        .with(headers: { 'Authorization' => /Basic/ })
    end
    
    it 'logs debug information' do
      client.get_issue_details(issue_key)
      
      expect(logger).to have_received(:debug)
        .with("Fetching details for issue: #{issue_key}")
    end
    
    it 'handles errors for specific issue' do
      stub_request(:get, "https://test.atlassian.net/rest/api/2/issue/#{issue_key}")
        .to_return(status: 404, body: 'Issue not found')
      
      expect { client.get_issue_details(issue_key) }
        .to raise_error(/HTTP 404/)
      
      expect(logger).to have_received(:error)
        .with(/Failed to fetch issue details for #{issue_key}/)
    end
  end
end