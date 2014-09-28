#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require(:default)

require 'appscript'
require 'issue'

class Omnifocus
  attr_reader :app, :default_document
  def initialize
    @app = Appscript.app.by_name("OmniFocus")
    @default_document = @app.default_document  
  end

  def context(name=DEFAULT_CONTEXT)
    default_document.flattened_contexts[name]
  end

  def project(name=DEFAULT_PROJECT)
    default_document.flattened_projects[name].get
  end

end

# helper to normalize access to omnifoucs
def omnifocus
  @omni ||= Omnifocus.new
end

# hash to hold the results of api queries
def jira_issues
  @jira_issues ||= Hash.new
end


# This method adds a new Task to OmniFocus based on the new_task_properties passed in
def add_task(issue)
  # If there is a passed in OF project name, get the actual project object
  issue.omnifocus_project = omnifocus.project if issue.project
  # If there is a passed in OF context name, get the actual context object
  # Update the context property to be the actual context object not the context name
  issue.omnifocus_context = omnifocus.context if issue.context

  # Check to see if there's already an OF Task with that name in the referenced Project
  # If there is, just stop.
  # puts "fetching omnifocus task for: \"#{issue.task_name}\""
  existing_task = issue.omnifocus_project.tasks.get.find { |t|
   t.name.get == issue.task_name 
  }

  #TODO: update_issue if exists
  return false if existing_task

  # You can uncomment this line and comment the one below if you want the tasks to end up in your Inbox instead of a specific Project
  # new_task = omnifocus_document.make(:new => :inbox_task, :with_properties => issue.omnifocus_properties)

  # Make a new Task in the Project
  proj.make(:new => :task, :with_properties => issue.omnifocus_properties)
  puts ["task created:", issue.omnifocus_properties].inspect
  return true
end

# This method is responsible for getting your assigned Jira Tickets and adding them to OmniFocus as Tasks
def add_jira_tickets_to_omnifocus ()
  # Get the open Jira issues assigned to you
  results = Issue.query_results
  if results.nil?
    puts "No results from Jira"
    exit
  end
  puts "\"#{QUERY}\" returned #{results.size} results from #{JIRA_BASE_URL}"

  # Iterate through resulting issues.
  results.each do |jira_id, issue|
    jira_issues[jira_id] = issue  # cache results
    add_task(issue)
  end
end

def mark_resolved_jira_tickets_as_complete_in_omnifocus ()
  # get tasks from the project
  ctx = omnifocus.context
  ctx.tasks.get.find.each do |task|
    if task.note.get.match(JIRA_BASE_URL)
      # try to parse out jira id
      full_url = task.note.get
      jira_id = full_url.sub(JIRA_BASE_URL+"/browse/","")
      issue = jira_issues[jira_id] ? jira_issues[jira_id] : Issue.new(jira_id).fetch

      # Check to see if the Jira ticket has been resolved, if so mark it as complete.
      if issue.fields.resoloution != nil #|| %w(Closed, Resolved).include?(issue.status)
        # if resolved, mark it as complete in OmniFocus
        task.completed.set(true)
      end
      # Check to see if the Jira ticket has been unassigned or assigned to someone else, if so delete it.
      # It will be re-created if it is assigned back to you.
      if ! issue.fields.assignee
        omnifocus_document.delete task
      else
        assignee = issue.fields.assignee.name
        if assignee != USERNAME
          omnifocus_document.delete task
        end
      end
    
    end
  end
end
