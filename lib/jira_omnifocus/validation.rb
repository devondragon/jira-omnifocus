# frozen_string_literal: true

module JiraOmnifocus
  module Validation
    HOSTNAME_PATTERN = %r{\Ahttps?://[\w\-.]+(:\d+)?(/[\w\-.]*)*\z}
    USERNAME_PATTERN = /\A[\w\-.@]+\z/
    
    class ValidationError < StandardError; end
    
    def self.validate_hostname!(hostname)
      hostname = hostname.to_s.strip
      raise ValidationError, "Hostname cannot be empty" if hostname.empty?
      raise ValidationError, "Invalid hostname format" unless hostname.match?(HOSTNAME_PATTERN)
      raise ValidationError, "Hostname cannot end with '/'" if hostname.end_with?('/')
      
      hostname
    end
    
    def self.validate_username!(username) 
      username = username.to_s.strip
      raise ValidationError, "Username cannot be empty" if username.empty?
      raise ValidationError, "Invalid username format" unless username.match?(USERNAME_PATTERN)
      
      username
    end
    
    def self.sanitize_jql(filter)
      # Remove potentially dangerous characters
      filter.to_s.gsub(/['";\\\0\n\r]/, '')
    end
    
    def self.validate_project_name!(project)
      project = project.to_s.strip
      raise ValidationError, "Project name cannot be empty" if project.empty?
      raise ValidationError, "Project name too long" if project.length > 255
      
      project
    end
    
    def self.validate_tag_name!(tag)
      tag = tag.to_s.strip
      raise ValidationError, "Tag name cannot be empty" if tag.empty?
      raise ValidationError, "Tag name too long" if tag.length > 255
      
      tag
    end
  end
end