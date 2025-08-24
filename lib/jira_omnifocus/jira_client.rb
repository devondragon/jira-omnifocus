# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'json'
require 'uri'

module JiraOmnifocus
  class JiraClient
    # HTTP timeout constants (in seconds)
    READ_TIMEOUT = 30
    OPEN_TIMEOUT = 10
    
    def initialize(config, logger)
      @config = config
      @logger = logger
      @http_client = setup_http_client
    end
    
    def get_issues
      @logger.debug "Starting JIRA issue retrieval..."
      
      response = get("/rest/api/2/search", {
        jql: @config.filter,
        maxResults: -1
      })
      
      @logger.info "Connected successfully to #{URI(@config.hostname).hostname}"
      
      data = JSON.parse(response.body)
      @logger.debug "Response parsed successfully!"
      
      jira_issues = {}
      data["issues"].each do |item|
        jira_id = item["key"]
        @logger.debug "Adding JIRA item: #{jira_id} to the jira_issues array"
        jira_issues[jira_id] = item
      end
      
      @logger.debug "Method complete, returning jira_issues."
      jira_issues
    rescue JSON::ParserError => e
      @logger.error "Failed to parse JIRA response: #{e.message}"
      raise
    rescue StandardError => e
      @logger.error "Failed to retrieve JIRA issues: #{e.message}"
      notify_error("Failed to retrieve JIRA issues", e.message)
      raise
    end
    
    def batch_get_issues(jira_ids)
      return {} if jira_ids.empty?
      
      @logger.debug "Batch fetching status for #{jira_ids.size} JIRA issues"
      
      jql = "key in (#{jira_ids.join(',')})"
      response = get("/rest/api/2/search", {
        jql: jql,
        fields: "resolution,assignee",
        maxResults: jira_ids.size
      })
      
      data = JSON.parse(response.body)
      statuses = {}
      
      data["issues"].each do |issue|
        statuses[issue["key"]] = {
          resolution: issue["fields"]["resolution"],
          assignee: issue["fields"]["assignee"]
        }
      end
      
      @logger.debug "Batch fetch complete, retrieved #{statuses.size} issue statuses"
      statuses
    rescue JSON::ParserError => e
      @logger.error "Failed to parse batch response: #{e.message}"
      raise
    rescue StandardError => e
      @logger.error "Failed to batch fetch JIRA issues: #{e.message}"
      raise
    end
    
    def get_issue_details(issue_key)
      @logger.debug "Fetching details for issue: #{issue_key}"
      
      response = get("/rest/api/2/issue/#{issue_key}")
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      @logger.error "Failed to parse issue details for #{issue_key}: #{e.message}"
      raise
    rescue StandardError => e
      @logger.error "Failed to fetch issue details for #{issue_key}: #{e.message}"
      raise
    end
    
    private
    
    def setup_http_client
      uri = URI(@config.hostname)
      
      # Enforce HTTPS for security
      unless uri.scheme == 'https'
        raise "Security Error: JIRA hostname must use HTTPS. Current value: #{@config.hostname}"
      end
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      # Warn if SSL verification is disabled
      if @config.ssl_verify
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      else
        @logger.error "⚠️  SECURITY WARNING: SSL verification is disabled. This is vulnerable to MITM attacks!"
        @logger.error "⚠️  Only use this for testing. Enable SSL verification for production use."
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      
      http.read_timeout = READ_TIMEOUT
      http.open_timeout = OPEN_TIMEOUT
      http
    end
    
    def get(path, params = {})
      uri = build_uri(path, params)
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(@config.username, @config.password)
      request['User-Agent'] = "jira-omnifocus/#{JiraOmnifocus::VERSION}"
      
      @logger.debug "GET #{uri}"
      response = @http_client.request(request)
      
      @logger.debug "Response code: #{response.code}"
      
      unless response.code.match?(/\A2\d{2}\z/)
        error_message = "HTTP #{response.code}: #{response.message}"
        notify_error("HTTP Error", "Response code: #{response.code}")
        raise error_message
      end
      
      response
    end
    
    def build_uri(path, params)
      uri = URI("#{@config.hostname}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      uri
    end
    
    def notify_error(title, message)
      return unless defined?(TerminalNotifier)
      
      TerminalNotifier.notify(message, 
        title: "JIRA OmniFocus Sync",
        subtitle: title,
        sound: 'default')
    rescue StandardError => e
      @logger.warn "Failed to send notification: #{e.message}"
    end
  end
end