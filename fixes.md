# JIRA-OmniFocus Improvement Plan

## Overview
This document outlines critical improvements needed for the jira-omnifocus Ruby script, organized by priority with specific implementation steps.

## Priority Levels
- 🔴 **CRITICAL**: Security vulnerabilities requiring immediate attention
- 🟠 **HIGH**: Major bugs or performance issues affecting functionality
- 🟡 **MEDIUM**: Code quality issues impacting maintainability
- 🟢 **LOW**: Minor improvements and optimizations

---

## 🔴 CRITICAL FIXES (Week 1)

### 1. ✅ Remove Password Exposure in Debug Mode - **COMPLETED**
**Location**: `bin/jiraomnifocus.rb:92-94`  
**Risk**: Passwords can be logged to console when DEBUG=true  
**Status**: Fixed in PR #59, merged to master

#### Implementation Steps:
1. Create a `SecureConfig` class that redacts sensitive fields:
```ruby
class SecureConfig
  attr_reader :hostname, :username, :filter, :ssl_verify
  
  def initialize(opts)
    @hostname = opts[:hostname]
    @username = opts[:username]
    @password = opts[:password]
    @filter = opts[:filter]
    @ssl_verify = opts[:ssl_verify]
  end
  
  def password
    @password
  end
  
  def to_s
    {
      hostname: @hostname,
      username: @username,
      password: '[REDACTED]',
      filter: @filter,
      ssl_verify: @ssl_verify
    }.to_s
  end
end
```

2. Replace all debug statements that could expose passwords:
```ruby
# Before
puts "JOFSYNC.get_issues: username and password loaded from Keychain" if $DEBUG

# After  
puts "JOFSYNC.get_issues: credentials loaded from Keychain" if $DEBUG
```

3. Never log response bodies that might contain auth tokens

### 2. ✅ Fix Silent Exception Swallowing - **COMPLETED**
**Location**: `bin/jiraomnifocus.rb:406`  
**Risk**: Critical errors are hidden, making debugging impossible  
**Status**: Fixed in PR #60, merged to master

#### Implementation Steps:
1. Replace bare rescue with specific exception handling:
```ruby
# Current dangerous code (line 406-408):
rescue
  next
end

# Replace with:
rescue Net::HTTPError => e
  puts "HTTP Error for JIRA #{jira_id}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if $DEBUG
  next
rescue JSON::ParserError => e
  puts "Failed to parse JIRA response for #{jira_id}: #{e.message}"
  next
rescue StandardError => e
  puts "Unexpected error processing #{jira_id}: #{e.class} - #{e.message}"
  puts e.backtrace.first(10).join("\n") if $DEBUG
  next
end
```

2. Add logging to file for persistent error tracking:
```ruby
require 'logger'

class JiraOmniFocus
  def initialize
    @logger = Logger.new(File.expand_path('~/.jofsync.log'))
    @logger.level = $DEBUG ? Logger::DEBUG : Logger::INFO
  end
  
  def log_error(context, error)
    @logger.error("#{context}: #{error.class} - #{error.message}")
    @logger.debug(error.backtrace.join("\n")) if error.backtrace
  end
end
```

---

## 🟠 HIGH PRIORITY FIXES (Week 2)

### 4. Fix N+1 Query Performance Problem
**Location**: `bin/jiraomnifocus.rb:303-411`  
**Impact**: Poor performance with many tasks

#### Implementation Steps:
1. Collect all JIRA IDs first:
```ruby
def get_jira_ids_from_omnifocus(omnifocus_document)
  jira_ids = []
  omnifocus_document.flattened_tasks.get.each do |task|
    if !task.completed.get && task.note.get.match($opts[:hostname])
      full_url = task.note.get.lines.first.chomp
      jira_id = full_url.sub($opts[:hostname] + "/browse/", "")
      jira_ids << jira_id
    end
  end
  jira_ids
end
```

2. Batch fetch JIRA statuses:
```ruby
def batch_fetch_jira_statuses(jira_ids)
  return {} if jira_ids.empty?
  
  # Use JQL to fetch multiple issues at once
  jql = "key in (#{jira_ids.join(',')})"
  uri = URI("#{$opts[:hostname]}/rest/api/2/search?jql=#{URI.encode_www_form_component(jql)}&fields=resolution,assignee")
  
  # Make single API call
  response = make_jira_request(uri)
  
  # Build status hash
  statuses = {}
  JSON.parse(response.body)["issues"].each do |issue|
    statuses[issue["key"]] = {
      resolution: issue["fields"]["resolution"],
      assignee: issue["fields"]["assignee"]
    }
  end
  statuses
end
```

3. Refactor main method to use cached data:
```ruby
def mark_resolved_jira_tickets_as_complete_in_omnifocus(omnifocus_document)
  # Collect all JIRA IDs
  jira_ids = get_jira_ids_from_omnifocus(omnifocus_document)
  
  # Batch fetch statuses
  jira_statuses = batch_fetch_jira_statuses(jira_ids)
  
  # Process tasks with cached data
  omnifocus_document.flattened_tasks.get.each do |task|
    next if task.completed.get
    next unless task.note.get.match($opts[:hostname])
    
    jira_id = extract_jira_id(task)
    status = jira_statuses[jira_id]
    
    next unless status
    
    process_task_status(task, jira_id, status)
  end
end
```

### 5. Add Input Validation
**Location**: `bin/jiraomnifocus.rb:76`  
**Risk**: Injection attacks via malformed hostnames

#### Implementation Steps:
1. Create validation module:
```ruby
module Validation
  VALID_HOSTNAME_REGEX = /\Ahttps?:\/\/[a-zA-Z0-9\-\.]+(\:[0-9]+)?(\/[a-zA-Z0-9\-\.\/]*)?\z/
  VALID_USERNAME_REGEX = /\A[a-zA-Z0-9\-_\.@]+\z/
  
  def self.validate_hostname!(hostname)
    unless hostname =~ VALID_HOSTNAME_REGEX
      raise ArgumentError, "Invalid hostname format: #{hostname}"
    end
    
    # Additional check for common mistakes
    if hostname.end_with?('/')
      raise ArgumentError, "Hostname should not end with '/': #{hostname}"
    end
    
    hostname
  end
  
  def self.validate_username!(username)
    unless username =~ VALID_USERNAME_REGEX
      raise ArgumentError, "Invalid username format: #{username}"
    end
    username
  end
  
  def self.sanitize_jql(filter)
    # Basic JQL injection prevention
    filter.gsub(/['";]/, '')
  end
end
```

2. Apply validation in `get_opts`:
```ruby
def get_opts
  # ... existing code ...
  
  opts = Optimist::options do
    # ... existing options ...
  end
  
  # Validate inputs
  opts[:hostname] = Validation.validate_hostname!(opts[:hostname])
  opts[:username] = Validation.validate_username!(opts[:username])
  opts[:filter] = Validation.sanitize_jql(opts[:filter])
  
  opts
end
```

### 6. Refactor Large Methods
**Location**: `bin/jiraomnifocus.rb:303-411`  
**Impact**: Unmaintainable code, difficult to test

#### Implementation Steps:
1. Break down `mark_resolved_jira_tickets_as_complete_in_omnifocus`:
```ruby
class TaskSynchronizer
  def sync_resolved_tickets(omnifocus_document)
    tasks = get_jira_linked_tasks(omnifocus_document)
    statuses = fetch_jira_statuses(tasks.keys)
    
    tasks.each do |jira_id, task|
      sync_single_task(task, jira_id, statuses[jira_id])
    end
  end
  
  private
  
  def get_jira_linked_tasks(document)
    # Extract JIRA-linked tasks
  end
  
  def fetch_jira_statuses(jira_ids)
    # Batch fetch from JIRA
  end
  
  def sync_single_task(task, jira_id, status)
    return unless status
    
    if status[:resolution]
      mark_task_complete(task, jira_id)
    elsif should_remove_task?(status)
      remove_task(task, jira_id)
    end
  end
  
  def should_remove_task?(status)
    return true unless status[:assignee]
    
    assignee_name = status[:assignee]["name"].downcase
    assignee_email = status[:assignee]["emailAddress"].downcase
    
    current_user = @config.username.downcase
    assignee_name != current_user && assignee_email != current_user
  end
end
```

---

## 🟡 MEDIUM PRIORITY FIXES (Week 3)

### 7. Eliminate Global Variables
**Location**: Throughout, especially `$opts` and `$DEBUG`

#### Implementation Steps:
1. Create application class:
```ruby
class JiraOmniFocusApp
  attr_reader :config, :logger
  
  def initialize(args = ARGV)
    @config = Configuration.new(args)
    @logger = setup_logger
    @jira_client = JiraClient.new(@config, @logger)
    @omnifocus_client = OmniFocusClient.new(@config, @logger)
    @synchronizer = TaskSynchronizer.new(@jira_client, @omnifocus_client, @logger)
  end
  
  def run
    unless OmniFocusClient.running?
      @logger.info "OmniFocus is not running"
      return
    end
    
    @logger.info "Starting synchronization..."
    @synchronizer.sync_all
    @logger.info "Synchronization complete"
  rescue StandardError => e
    @logger.error "Sync failed: #{e.message}"
    @logger.debug e.backtrace.join("\n")
    exit 1
  end
  
  private
  
  def setup_logger
    logger = Logger.new(STDOUT)
    logger.level = @config.debug? ? Logger::DEBUG : Logger::INFO
    logger
  end
end
```

### 8. Extract HTTP Communication
**Location**: `bin/jiraomnifocus.rb:105-108, 337-340`

#### Implementation Steps:
1. Create JIRA client class:
```ruby
class JiraClient
  def initialize(config, logger)
    @config = config
    @logger = logger
    @http = setup_http_client
  end
  
  def get_issues
    response = get("/rest/api/2/search", {
      jql: @config.filter,
      maxResults: -1
    })
    
    JSON.parse(response.body)["issues"]
  rescue JSON::ParserError => e
    @logger.error "Failed to parse JIRA response: #{e.message}"
    raise
  end
  
  def get_issue(jira_id)
    response = get("/rest/api/2/issue/#{jira_id}")
    JSON.parse(response.body)
  end
  
  private
  
  def setup_http_client
    uri = URI(@config.hostname)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.verify_mode = @config.ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    http
  end
  
  def get(path, params = {})
    uri = build_uri(path, params)
    request = Net::HTTP::Get.new(uri)
    request.basic_auth(@config.username, @config.password)
    
    @logger.debug "GET #{uri}"
    response = @http.request(request)
    
    unless response.code =~ /20[0-9]/
      raise Net::HTTPError.new("HTTP #{response.code}: #{response.message}", response)
    end
    
    response
  end
  
  def build_uri(path, params)
    uri = URI("#{@config.hostname}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    uri
  end
end
```

### 9. Implement Connection Pooling
**Location**: HTTP requests throughout

#### Implementation Steps:
1. Add connection pooling gem to Gemfile:
```ruby
gem 'net-http-persistent'
```

2. Update JiraClient:
```ruby
class JiraClient
  def initialize(config, logger)
    @config = config
    @logger = logger
    @http = Net::HTTP::Persistent.new
    configure_http
  end
  
  def configure_http
    @http.verify_mode = @config.ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    @http.idle_timeout = 30
    @http.max_requests = 100
  end
  
  def get(path, params = {})
    uri = build_uri(path, params)
    request = Net::HTTP::Get.new(uri)
    request.basic_auth(@config.username, @config.password)
    
    response = @http.request(uri, request)
    # ... rest of method
  end
  
  def shutdown
    @http.shutdown
  end
end
```

---

## 🟢 LOW PRIORITY IMPROVEMENTS (Week 4)

### 10. Replace Deprecated Methods
**Location**: `bin/jiraomnifocus.rb:76`

```ruby
# Replace
URI::encode(filter)

# With
URI.encode_www_form_component(filter)
```

### 11. Improve Logging System
```ruby
class AppLogger
  LEVELS = {
    debug: Logger::DEBUG,
    info: Logger::INFO,
    warn: Logger::WARN,
    error: Logger::ERROR
  }
  
  def initialize(config)
    @stdout_logger = Logger.new(STDOUT)
    @file_logger = Logger.new(File.expand_path('~/.jofsync.log'), 'daily')
    
    level = config.debug? ? :debug : :info
    set_level(level)
    
    @stdout_logger.formatter = simple_formatter
    @file_logger.formatter = detailed_formatter
  end
  
  def method_missing(method, *args)
    if LEVELS.key?(method)
      @stdout_logger.send(method, *args)
      @file_logger.send(method, *args)
    else
      super
    end
  end
  
  private
  
  def simple_formatter
    proc do |severity, datetime, progname, msg|
      "#{severity[0]}: #{msg}\n"
    end
  end
  
  def detailed_formatter
    proc do |severity, datetime, progname, msg|
      "[#{datetime.iso8601}] #{severity}: #{msg}\n"
    end
  end
end
```

### 12. Add Tests
Create `spec/` directory with test coverage:

```ruby
# spec/jira_client_spec.rb
require 'rspec'
require_relative '../lib/jira_client'

RSpec.describe JiraClient do
  let(:config) { double(hostname: 'https://example.atlassian.net', username: 'user', password: 'pass') }
  let(:logger) { Logger.new(nil) }
  let(:client) { JiraClient.new(config, logger) }
  
  describe '#get_issues' do
    it 'fetches issues from JIRA API' do
      # Test implementation
    end
    
    it 'handles API errors gracefully' do
      # Test error handling
    end
  end
end
```

---

## Implementation Timeline

### Week 1: Critical Security Fixes
- [x] Remove password from debug output - **COMPLETED** (PR #59)
- [x] Fix exception handling - **COMPLETED** (PR #60)
- [ ] Enforce secure credential storage
- [ ] Deploy hotfix version

### Week 2: Performance & Reliability
- [ ] Implement batch API calls
- [ ] Add input validation
- [ ] Refactor large methods
- [ ] Performance testing

### Week 3: Code Quality
- [ ] Remove global variables
- [ ] Extract client classes
- [ ] Implement connection pooling
- [ ] Code review

### Week 4: Polish & Documentation
- [ ] Fix deprecated methods
- [ ] Improve logging
- [ ] Add test suite
- [ ] Update documentation

---

## Testing Strategy

### Manual Testing Checklist
- [ ] Test with keychain authentication
- [ ] Test with API token
- [ ] Test with invalid credentials
- [ ] Test with no network connection
- [ ] Test with 0, 1, 10, 100+ JIRA tickets
- [ ] Test task creation in inbox mode
- [ ] Test task creation in project mode
- [ ] Test with debug mode enabled

### Automated Testing Goals
- Unit test coverage > 80%
- Integration tests for JIRA API
- Mock OmniFocus interactions
- Performance benchmarks

---

## Deployment Notes

1. **Version Numbering**: Increment to 2.0.0 for breaking changes
2. **Migration Guide**: Document config file changes
3. **Rollback Plan**: Keep version 1.x branch for emergency rollback
4. **Communication**: Notify users of security fixes via GitHub releases

---

## Long-term Improvements

1. **Consider Rewrite**: Ruby on Rails for web interface
2. **Add Features**: 
   - Two-way sync
   - Custom field mapping
   - Multiple JIRA project support
3. **Modern Authentication**: OAuth 2.0 support
4. **Monitoring**: Add telemetry and error reporting
5. **Distribution**: Homebrew formula for easier installation