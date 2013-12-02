#!/usr/bin/ruby
require 'appscript'
require 'rubygems'
require 'net/http'
require 'json'

#JIRA Configuration
JIRA_BASE_URL = 'https://www.yoursite.com/jira'
USERNAME = 'devon'
PASSWORD = 'mypassword'

#OmniFocus Configuration
DEFAULT_CONTEXT="Jira"
DEFAULT_PROJECT="Work"
FLAGGED=true

# This method gets all issues that are assigned to your USERNAME and whos status isn't Closed or Resolved.  It returns a Hash where the key is the Jira Ticket Key and the value is the Jira Ticket Summary.
def get_issues
  jira_issues = Hash.new
  # This is the REST URL that will be hit.  Change the jql query if you want to adjust the query used here
  uri = URI(JIRA_BASE_URL + '/rest/api/2/search?jql=assignee+%3D+currentUser()+AND+status+not+in+(Closed,+Resolved)') 

  Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new(uri)
    request.basic_auth USERNAME, PASSWORD
    response = http.request request
    # If the response was good, then grab the data
    if response.code =~ /20[0-9]{1}/
        data = JSON.parse(response.body)
        data["issues"].each do |item|
          jira_id = item["key"]
          jira_issues[jira_id] = item["fields"]["summary"]
        end    
    else
     raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
    end
  end
  return jira_issues
end

# This method adds a new Task to OmniFocus based on the new_task_properties passed in
def add_task(omnifocus_document, new_task_properties)
  # If there is a passed in OF project name, get the actual project object
  if new_task_properties['project']
    proj_name = new_task_properties["project"]
    proj = omnifocus_document.flattened_tasks[proj_name]
  end

  # Check to see if there's already an OF Task with that name in the referenced Project
  # If there is, just stop.
  name   = new_task_properties["name"]
  exists = proj.tasks.get.find { |t| t.name.get == name }
  return false if exists

  # If there is a passed in OF context name, get the actual context object
  if new_task_properties['context']
    ctx_name = new_task_properties["context"]
    ctx = omnifocus_document.flattened_contexts[ctx_name]
  end
  
  # Do some task property filtering.  I don't know what this is for, but found it in several other scripts that didn't work...
  tprops = new_task_properties.inject({}) do |h, (k, v)|
    h[:"#{k}"] = v
    h
  end

  # Remove the project property from the new Task properties, as it won't be used like that.
  tprops.delete(:project)
  # Update the context property to be the actual context object not the context name
  tprops[:context] = ctx if new_task_properties['context']

  # You can uncomment this line and comment the one below if you want the tasks to end up in your Inbox instead of a specific Project
#  new_task = omnifocus_document.make(:new => :inbox_task, :with_properties => tprops)

  # Make a new Task in the Project
  proj.make(:new => :task, :with_properties => tprops)
  
  puts "task created"
  return true
end

# This method is responsible for getting your assigned Jira Tickets and adding them to OmniFocus as Tasks
def add_jira_tickets_to_omnifocus ()
  # Get the open Jira issues assigned to you
  results = get_issues
  if results.nil?
    puts "No results from Jira"
    exit
  end

  # Get the OmniFocus app and main document via AppleScript
  omnifocus_app = Appscript.app.by_name("OmniFocus")
  omnifocus_document = omnifocus_app.default_document

  # Iterate through resulting issues.
  results.each do |jira_id, summary|
    # Create the task name by adding the ticket summary to the jira ticket key
    task_name = "#{jira_id}: #{summary}"
    # Create the task notes with the Jira Ticket URL
    task_notes = "#{JIRA_BASE_URL}/browse/#{jira_id}"

    # Build properties for the Task
    @props = {}
    @props['name'] = task_name
    @props['project'] = DEFAULT_PROJECT
    @props['context'] = DEFAULT_CONTEXT
    @props['note'] = task_notes
    @props['flagged'] = FLAGGED
    add_task(omnifocus_document, @props)
  end
end

def mark_resolved_jira_tickets_as_complete_in_omnifocus ()
  # get tasks from the project
  omnifocus_app = Appscript.app.by_name("OmniFocus")
  omnifocus_document = omnifocus_app.default_document
  ctx = omnifocus_document.flattened_contexts[DEFAULT_CONTEXT]
  ctx.tasks.get.find.each do |task|
    if task.note.get.match(JIRA_BASE_URL)
      # try to parse out jira id      
      full_url= task.note.get
      jira_id=full_url.sub(JIRA_BASE_URL+"/browse/","")
      # check status of the jira
      uri = URI(JIRA_BASE_URL + '/rest/api/2/issue/' + jira_id)

      Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request.basic_auth USERNAME, PASSWORD
        response = http.request request

        if response.code =~ /20[0-9]{1}/
            data = JSON.parse(response.body)
            resolution = data["fields"]["resolution"]
            if resolution != nil
              # if resolved, mark it as complete in OmniFocus
              task.completed.set(true)
            end
        else
         raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
        end
      end
    end
  end
end

def app_is_running(app_name)
  `ps aux` =~ /#{app_name}/ ? true : false
end

def main ()
   if app_is_running("OmniFocus")
	  add_jira_tickets_to_omnifocus
	  mark_resolved_jira_tickets_as_complete_in_omnifocus
   end
end

main
