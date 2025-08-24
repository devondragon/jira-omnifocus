# frozen_string_literal: true

module JiraOmnifocus
  class Logger
    LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    }.freeze
    
    def initialize(level: :info, quiet: false)
      @level = LEVELS[level] || LEVELS[:info]
      @quiet = quiet
    end
    
    def debug(message)
      log(:debug, message)
    end
    
    def info(message)
      log(:info, message)
    end
    
    def warn(message)
      log(:warn, message)
    end
    
    def error(message)
      log(:error, message)
    end
    
    private
    
    def log(level, message)
      return if @quiet && level != :error
      return if LEVELS[level] < @level
      
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      prefix = level.to_s.upcase.rjust(5)
      
      puts "[#{timestamp}] #{prefix}: #{message}"
    end
  end
end