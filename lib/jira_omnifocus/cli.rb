# frozen_string_literal: true

require 'optimist'

module JiraOmnifocus
  class CLI
    def initialize
      @config = nil
      @logger = nil
    end
    
    def run(args)
      opts = parse_options(args)
      
      # Initialize configuration first (may raise validation errors)
      begin
        @config = build_configuration(opts)
      rescue Validation::ValidationError => e
        warn "Configuration error: #{e.message}"
        exit 1
      end
      
      # Initialize logger
      @logger = Logger.new(
        level: @config.debug? ? :debug : :info,
        quiet: @config.quiet?
      )
      
      @logger.info "Starting JIRA-OmniFocus sync"
      @logger.debug "Configuration: #{@config}"
      
      # Initialize clients
      jira_client = JiraClient.new(@config, @logger)
      omnifocus_client = OmniFocusClient.new(@config, @logger)
      
      # Run synchronization
      synchronizer = TaskSynchronizer.new(@config, @logger, jira_client, omnifocus_client)
      synchronizer.sync
      
      @logger.info "Sync completed successfully"
    rescue StandardError => e
      if @logger
        @logger.error "Sync failed: #{e.message}"
        @logger.debug "Backtrace: #{e.backtrace.join("\n")}" if @config&.debug?
      else
        warn "Error: #{e.message}"
      end
      exit 1
    end
    
    private
    
    def parse_options(args)
      # Load default config from file
      default_config = Configuration.load_from_file
      
      Optimist.options(args) do
        version "jira-omnifocus #{JiraOmnifocus::VERSION}"
        banner <<~BANNER
          Jira OmniFocus Sync Tool
          
          Usage:
                 jiraomnifocus [options]
          
          KNOWN ISSUES:
                * With long names you must use an equal sign ( i.e. --hostname=test-target-1 )
          
          ---
        BANNER
        
        opt :usekeychain, 'Use Keychain for Jira', 
            type: :boolean, short: 'k', required: false, 
            default: default_config.use_keychain?
            
        opt :username, 'Jira Username', 
            type: :string, short: 'u', required: false, 
            default: default_config.username
            
        opt :password, 'Jira Password', 
            type: :string, short: 'p', required: false, 
            default: default_config.password
            
        opt :hostname, 'Jira Server Hostname', 
            type: :string, short: 'h', required: false, 
            default: default_config.hostname
            
        opt :filter, 'JQL Filter', 
            type: :string, short: 'j', required: false, 
            default: default_config.filter
            
        opt :ssl_verify, 'SSL verification', 
            type: :boolean, short: 's', required: false, 
            default: default_config.ssl_verify
            
        opt :tag, 'OF Default Tag', 
            type: :string, short: 'c', required: false, 
            default: default_config.tag
            
        opt :project, 'OF Default Project', 
            type: :string, short: 'r', required: false, 
            default: default_config.project
            
        opt :flag, 'Flag tasks in OF', 
            type: :boolean, short: 'f', required: false, 
            default: default_config.flag
            
        opt :folder, 'OF Default Folder', 
            type: :string, short: 'o', required: false, 
            default: default_config.folder
            
        opt :inbox, 'Create inbox tasks', 
            type: :boolean, short: 'i', required: false, 
            default: default_config.inbox
            
        opt :newproj, 'Create as projects', 
            type: :boolean, short: 'n', required: false, 
            default: default_config.newproj
            
        opt :descsync, 'Sync Description to Notes', 
            type: :boolean, short: 'd', required: false, 
            default: default_config.descsync
            
        opt :quiet, 'Disable output', 
            type: :boolean, short: 'q', required: false, 
            default: true
            
        opt :debug, 'Enable debug output',
            type: :boolean, required: false,
            default: false
      end
    end
    
    def build_configuration(opts)
      # Convert CLI options to configuration
      Configuration.new(opts)
    end
  end
end