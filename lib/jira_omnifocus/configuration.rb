# frozen_string_literal: true

require 'yaml'
require 'keychain'

module JiraOmnifocus
  class Configuration
    attr_reader :hostname, :username, :filter, :ssl_verify, :debug
    attr_reader :tag, :project, :flag, :folder, :inbox, :newproj, :descsync
    
    def initialize(opts = {})
      # JIRA configuration - handle empty/nil values gracefully
      @hostname = opts[:hostname] && !opts[:hostname].empty? ? Validation.validate_hostname!(opts[:hostname]) : 'http://please-configure-me.atlassian.net'
      @username = opts[:username] && !opts[:username].empty? ? Validation.validate_username!(opts[:username]) : ''
      @filter = Validation.sanitize_jql(opts[:filter] || 'resolution = Unresolved and issue in watchedissues()')
      @ssl_verify = opts.fetch(:ssl_verify, true)
      @usekeychain = opts.fetch(:usekeychain, false)
      @password = opts[:password] || '' # Keep private
      
      # OmniFocus configuration
      @tag = opts[:tag] && !opts[:tag].empty? ? Validation.validate_tag_name!(opts[:tag]) : nil
      @project = opts[:project] && !opts[:project].empty? ? Validation.validate_project_name!(opts[:project]) : nil
      @flag = opts.fetch(:flag, false)
      @folder = opts[:folder] && !opts[:folder].empty? ? Validation.validate_project_name!(opts[:folder]) : nil
      @inbox = opts.fetch(:inbox, false)
      @newproj = opts.fetch(:newproj, false) 
      @descsync = opts.fetch(:descsync, false)
      
      # General configuration
      @debug = opts.fetch(:debug, false)
      @quiet = opts.fetch(:quiet, true)
      
      load_keychain_credentials if @usekeychain
      
      # Validate required fields after keychain loading
      validate_required_fields!
    end
    
    def self.load_from_file(config_path = nil)
      config_path ||= File.join(ENV['HOME'], '.jofsync.yaml')
      
      config_data = if File.exist?(config_path)
        YAML.safe_load_file(config_path)
      else
        default_config
      end
      
      # Flatten nested config structure
      opts = {}
      opts.merge!(config_data['jira']) if config_data['jira']
      opts.merge!(config_data['omnifocus']) if config_data['omnifocus']
      
      # Convert string keys to symbols
      opts = opts.transform_keys(&:to_sym)
      
      new(opts)
    rescue StandardError => e
      # If config loading fails, return defaults
      warn "Warning: Failed to load config file (#{e.message}), using defaults"
      new(flatten_default_config)
    end
    
    def password
      @password
    end
    
    def debug?
      @debug
    end
    
    def quiet?
      @quiet
    end
    
    def use_keychain?
      @usekeychain
    end
    
    def to_s
      {
        hostname: @hostname,
        username: @username,
        filter: @filter,
        ssl_verify: @ssl_verify,
        debug: @debug,
        tag: @tag,
        project: @project,
        flag: @flag,
        folder: @folder,
        inbox: @inbox,
        newproj: @newproj,
        descsync: @descsync,
        password: '[REDACTED]'
      }.inspect
    end
    
    private
    
    def load_keychain_credentials
      uri = URI(@hostname)
      host = uri.host
      
      keychain_item = Keychain.internet_passwords.where(server: host).first
      if keychain_item
        @username = keychain_item.account
        @password = keychain_item.password
      else
        raise Validation::ValidationError, "Password for #{host} not found in keychain; add it using 'security add-internet-password -a <username> -s #{host} -w <password>'"
      end
    end
    
    def self.default_config
      {
        'jira' => {
          'hostname' => 'http://please-configure-me-in-jofsync.yaml.atlassian.net',
          'usekeychain' => false,
          'username' => '',
          'password' => '',
          'filter' => 'resolution = Unresolved and issue in watchedissues()',
          'ssl_verify' => true
        },
        'omnifocus' => {
          'tag' => 'Office',
          'project' => 'Jira',
          'flag' => true,
          'inbox' => false,
          'newproj' => false,
          'folder' => 'Jira',
          'descsync' => false
        }
      }
    end
    
    def self.flatten_default_config
      config = default_config
      opts = {}
      opts.merge!(config['jira']) if config['jira']
      opts.merge!(config['omnifocus']) if config['omnifocus']
      opts.transform_keys(&:to_sym)
    end
    
    def validate_required_fields!
      if @hostname.include?('please-configure-me')
        raise Validation::ValidationError, "Please configure your JIRA hostname in ~/.jofsync.yaml"
      end
      
      if @username.empty? && !@usekeychain
        raise Validation::ValidationError, "Username is required (set in config file or use --usekeychain)"
      end
      
      if @password.empty? && !@usekeychain
        raise Validation::ValidationError, "Password is required (set in config file or use --usekeychain)"
      end
    end
  end
end