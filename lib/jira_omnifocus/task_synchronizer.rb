# frozen_string_literal: true

module JiraOmnifocus
  class TaskSynchronizer
    def initialize(config, logger, jira_client, omnifocus_client)
      @config = config
      @logger = logger
      @jira_client = jira_client
      @omnifocus_client = omnifocus_client
    end
    
    def sync
      @logger.info "Starting JIRA-OmniFocus synchronization"
      
      add_new_tickets_to_omnifocus
      mark_resolved_tickets_complete
      
      @logger.info "Synchronization completed"
    end
    
    private
    
    def add_new_tickets_to_omnifocus
      @logger.debug "Adding new JIRA tickets to OmniFocus"
      
      # Get open JIRA issues
      jira_issues = @jira_client.get_issues
      if jira_issues.empty?
        @logger.info "No JIRA issues found"
        return
      end
      
      @logger.info "Processing #{jira_issues.size} JIRA issues"
      
      # Add each issue as a task
      jira_issues.each do |jira_id, ticket|
        @logger.debug "Processing JIRA ID: #{jira_id}"
        
        task_properties = build_task_properties(jira_id, ticket)
        @omnifocus_client.add_task(task_properties)
      end
      
      @logger.debug "Finished adding JIRA tickets to OmniFocus"
    end
    
    def mark_resolved_tickets_complete
      @logger.debug "Checking for resolved JIRA tickets to mark complete"
      
      # Get JIRA IDs from OmniFocus tasks
      jira_ids = @omnifocus_client.get_jira_ids_from_tasks
      return if jira_ids.empty?
      
      @logger.info "Checking status of #{jira_ids.size} JIRA tickets"
      
      # Batch fetch current JIRA statuses
      jira_statuses = @jira_client.batch_get_issues(jira_ids)
      
      jira_statuses.each do |jira_id, status|
        handle_jira_status_change(jira_id, status)
      end
      
      @logger.debug "Finished processing JIRA status changes"
    end
    
    def build_task_properties(jira_id, ticket)
      fields = ticket["fields"]
      
      # Create task name
      task_name = "#{jira_id}: #{fields["summary"]}"
      
      # Create task notes
      task_notes = if @config.descsync
        "#{@config.hostname}/browse/#{jira_id}\n\n#{fields["description"]}"
      else
        "#{@config.hostname}/browse/#{jira_id}\n"
      end
      
      # Build task properties
      properties = {
        'name' => task_name,
        'note' => task_notes,
        'flagged' => @config.flag
      }
      
      # Add optional properties
      properties['project'] = @config.project if @config.project
      properties['tag'] = @config.tag if @config.tag
      
      # Add due date if present
      if fields["duedate"]
        properties['due_date'] = fields["duedate"]
      end
      
      @logger.debug "Built task properties for #{jira_id}"
      properties
    end
    
    def handle_jira_status_change(jira_id, status)
      resolution = status[:resolution]
      assignee = status[:assignee]
      
      if resolution
        # Ticket is resolved - mark complete
        @logger.debug "JIRA #{jira_id} is resolved, marking complete"
        @omnifocus_client.mark_task_complete(jira_id)
      elsif assignee.nil?
        # Ticket is unassigned - remove task
        @logger.debug "JIRA #{jira_id} is unassigned, removing task"
        @omnifocus_client.remove_task(jira_id)
      elsif assignee && assignee["name"] != @config.username
        # Ticket reassigned to someone else - remove task
        @logger.debug "JIRA #{jira_id} reassigned to #{assignee["name"]}, removing task"
        @omnifocus_client.remove_task(jira_id)
      end
    end
  end
end