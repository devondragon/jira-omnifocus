# frozen_string_literal: true

require 'rb-scpt'
require 'date'

module JiraOmnifocus
  class OmniFocusClient
    def initialize(config, logger)
      @config = config
      @logger = logger
      @document = Appscript.app('OmniFocus').default_document
    end
    
    def add_task(task_properties)
      @logger.debug "Starting task creation: #{task_properties['name']}"
      
      # Check for existing task
      return false if task_exists?(task_properties['name'])
      
      # Get project if specified
      project = nil
      if task_properties['project'] && !@config.inbox && !@config.newproj
        proj_name = task_properties['project']
        @logger.debug "Loading project: #{proj_name}"
        project = @document.flattened_tasks[proj_name]
      end
      
      # Get tag if specified
      tag = nil
      if task_properties['tag']
        tag_name = task_properties['tag']
        @logger.debug "Loading tag: #{tag_name}"
        tag = @document.flattened_tags[tag_name]
      end
      
      # Build task properties for OmniFocus
      of_props = build_omnifocus_properties(task_properties, tag)
      
      # Create the task in appropriate location
      create_task_in_location(of_props, project)
      
      @logger.debug "Task creation completed."
      true
    end
    
    def get_jira_ids_from_tasks
      @logger.debug "Extracting JIRA IDs from OmniFocus tasks"
      
      jira_ids = []
      @document.flattened_tasks.get.each do |task|
        next if task.completed.get
        
        task_note = task.note.get
        next unless task_note&.match(@config.hostname)
        
        full_url = task_note.lines.first.chomp
        jira_id = full_url.sub("#{@config.hostname}/browse/", "")
        jira_ids << jira_id
      end
      
      @logger.debug "Found #{jira_ids.size} JIRA IDs in OmniFocus tasks"
      jira_ids
    end
    
    def mark_task_complete(jira_id)
      @logger.debug "Marking task complete for JIRA ID: #{jira_id}"
      
      task = find_task_by_jira_id(jira_id)
      return false unless task
      
      task.completed.set(true)
      task_name = task.name.get.force_encoding("UTF-8")
      @logger.info "Marked complete: #{task_name}"
      true
    end
    
    def remove_task(jira_id)
      @logger.debug "Removing task for JIRA ID: #{jira_id}"
      
      task = find_task_by_jira_id(jira_id)
      return false unless task
      
      task_name = task.name.get.force_encoding("UTF-8")
      task.delete
      @logger.info "Removed: #{task_name}"
      true
    end
    
    private
    
    def task_exists?(task_name)
      @logger.debug "Checking for existing task: #{task_name}"
      
      exists = if @config.inbox || @config.newproj
        # Search entire document
        @logger.debug "Searching entire OmniFocus document"
        @document.flattened_tasks.get.find do |t| 
          t.name.get.force_encoding("UTF-8") == task_name 
        end
      else
        # Search only in specified project
        project = @document.flattened_tasks[@config.project]
        @logger.debug "Searching only project: #{project.name.get}"
        project.tasks.get.find do |t| 
          t.name.get.force_encoding("UTF-8") == task_name 
        end
      end
      
      @logger.debug "Task exists = #{!exists.nil?}"
      !exists.nil?
    end
    
    def build_omnifocus_properties(task_properties, tag)
      # Convert to symbol keys for OmniFocus API
      of_props = task_properties.transform_keys(&:to_sym)
      
      # Remove properties that need special handling
      of_props.delete(:project)
      of_props.delete(:tag)
      
      # Set tag as primary_tag if provided
      of_props[:primary_tag] = tag if tag
      
      # Parse due date if provided
      if task_properties['due_date']
        of_props[:due_date] = Date.parse(task_properties['due_date'])
      end
      
      of_props
    end
    
    def create_task_in_location(of_props, project)
      if @config.inbox
        @logger.debug "Adding Task to Inbox"
        @document.make(new: :inbox_task, with_properties: of_props)
        @logger.info "Created inbox task: #{of_props[:name]}"
      elsif @config.newproj
        @logger.debug "Adding Task as a new Project"
        of_folder = @document.folders[@config.folder]
        of_folder.make(new: :project, with_properties: of_props)
        @logger.info "Created project in #{@config.folder} folder: #{of_props[:name]}"
      else
        @logger.debug "Adding Task to project: #{@config.project}"
        project.make(new: :task, with_properties: of_props)
        @logger.info "Created task [#{of_props[:name]}] in project #{@config.project}"
      end
    end
    
    def find_task_by_jira_id(jira_id)
      url_pattern = "#{@config.hostname}/browse/#{jira_id}"
      
      @document.flattened_tasks.get.find do |task|
        task_note = task.note.get
        task_note&.include?(url_pattern)
      end
    end
  end
end