#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require(:default)

require 'appscript'
require 'yaml'
require 'keychain'
require 'jira'
require 'ruby-growl'
require 'pathname'

class Hash
  #take keys of hash and transform those to a symbols
  def self.transform_keys_to_symbols(value)
    return value if not value.is_a?(Hash)
    hash = value.inject({}){|memo,(k,v)| memo[k.to_sym] = Hash.transform_keys_to_symbols(v); memo}
    return hash
  end
end

if  File.file?(ENV['HOME']+'/.jofsync.yaml')
  config = YAML.load_file(ENV['HOME']+'/.jofsync.yaml')
  config = Hash.transform_keys_to_symbols(config)
=begin
YAML CONFIG EXAMPLE
---
jira:
  hostname: 'http://example.atlassian.net'
  context:  'Colleagues'
  project:  'Jira'
  filter:   'resolution = Unresolved and issue in watchedissues()'
=end
end

opts = Trollop::options do
  banner ""
  banner <<-EOS
Jira OmniFocus Sync Tool

Usage:
       jofsync [options]

KNOWN ISSUES:
      * With long names you must use an equal sign ( i.e. --hostname=test-target-1 )

---
EOS
  version 'jofsync 1.1.0'
  opt :hostname, 'Jira Server Hostname', :type => :string, :short => 'h', :default => config[:jira][:hostname]
  opt :context, 'OF Default Context', :type => :string, :short => 'c', :default => config[:jira][:context]
  opt :project, 'OF Default Project', :type => :string, :short => 'r', :default => config[:jira][:project]
  opt :filter, 'JQL Filter', :type => :string, :short => 'j', :default => config[:jira][:filter]
  opt :parenttaskfield, 'Field to use in identifying parent tasks', :default => config[:jira][:parenttaskfield]
  opt :quiet, 'Disable alerts', :short => 'q', :default => config[:jira][:quiet]
end

QUIET = opts[:quiet]
unless QUIET 
  Growler = Growl.new "localhost", Pathname.new($0).basename
  Growler.add_notification 'Error'
  Growler.add_notification 'No Results'
  Growler.add_notification 'Context Created'
  Growler.add_notification 'Task Created'
  Growler.add_notification 'Task Not Completed'
  Growler.add_notification 'Task Completed'
end

#JIRA Configuration
JIRA_BASE_URL = opts[:hostname]

uri = URI(JIRA_BASE_URL)
host = uri.host
path = uri.path
uri.path = ''
keychainitem = Keychain.internet_passwords.where(:server => host).first
USERNAME = keychainitem.account
JIRACLIENT = JIRA::Client.new(
  :username => USERNAME,
  :password => keychainitem.password,
  :site     => uri.to_s,
  :context_path => path,
  :auth_type => :basic
)

QUERY = opts[:filter]
JQL = URI::encode(QUERY)

#OmniFocus Configuration
DEFAULT_CONTEXT = opts[:context]
DEFAULT_PROJECT = opts[:project]

ParentTaskField = opts[:parenttaskfield]

# This method adds a new Task to OmniFocus based on the new_task_properties passed in
def add_task(omnifocus_document, project:nil, parent_task:nil, context:nil, **new_task_properties)
  # If there is a passed in OF project name, get the actual project object
  if project
    proj = omnifocus_document.flattened_tasks[project]
  end

  # Check to see if there's already an OF Task with that name in the referenced Project
  name   = new_task_properties[:name]
  flagged = new_task_properties[:flagged]
  task = proj.flattened_tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == name }

  if task
    # Make sure the flag is set correctly.
    task.flagged.set(flagged)
    if task.completed.get == true
      task.completed.set(false)
      QUIET or Growler.notify 'Task Not Completed', task.name.get, "OmniFocus task no longer marked completed"
    end
    task.completed.set(false)
    return task
  else
    defaultctx = omnifocus_document.flattened_contexts[DEFAULT_CONTEXT]
    # If there is a passed in OF context name, get the actual context object (creating if necessary)
    if context
      unless ctx = defaultctx.contexts.get.find { |c| c.name.get.force_encoding("UTF-8") == context }
        ctx = defaultctx.make(:new => :context, :with_properties => {:name => context})
        QUIET or Growler.notify 'Context Created', "#{defaultctx.name.get}: #{context}", 'OmniFocus context created'
      end
    else
      ctx = defaultctx
    end

    # If there is a passed in parent task, get the actual parent task object (creating if necessary)
    if parent_task
      unless parent = proj.tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == parent_task }
        parent = proj.make(:new => :task,
                           :with_properties => {:name => parent_task,
                                                :sequential => false,
                                                :completed_by_children => true})
        QUIET or Growler.notify 'Task Created', parent_task, 'OmniFocus task created'
      end
    end
    
    # Update the context property to be the actual context object not the context name
    new_task_properties[:context] = ctx
    
    # You can uncomment this line and comment the one below if you want the tasks to end up in your Inbox instead of a specific Project
    #  new_task = omnifocus_document.make(:new => :inbox_task, :with_properties => new_task_properties)

    # Make a new Task in the Project
    task = proj.make(:new => :task,
                     :at => parent,
                     :with_properties => new_task_properties)
    QUIET or Growler.notify 'Task Created', name, 'OmniFocus task created'
    return task
  end
end

# This method is responsible for getting your assigned Jira Tickets and adding them to OmniFocus as Tasks
def add_jira_tickets_to_omnifocus ()
  # Get the open Jira issues assigned to you
  fields = ['summary', 'reporter', 'assignee', 'duedate']
  if ParentTaskField
    fields.push ParentTaskField
  end
  results = JIRACLIENT.Issue.jql(QUERY, fields: fields)
  if results.nil?
    QUIET or Growler.notify 'No Results', Pathname.new($0).basename, "No results from Jira"
    exit
  end

  # Get the OmniFocus app and main document via AppleScript
  omnifocus_app = Appscript.app.by_name("OmniFocus")
  omnifocus_document = omnifocus_app.default_document

  # Iterate through resulting issues.
  results.each do |ticket|
    jira_id = ticket.key
    add_task(omnifocus_document,
             # Create the task name by adding the ticket summary to the jira ticket key
             name: "#{jira_id}: #{ticket.summary}",
             project: DEFAULT_PROJECT,
             # Base context on the reporter
             #context: ticket.reporter.attrs["displayName"]
             context: ticket.reporter.attrs["displayName"].split(", ").reverse.join(" "),
             # Create the task notes with the Jira Ticket URL
             note: "#{JIRA_BASE_URL}/browse/#{jira_id}",
             # Flag the task iff it's assigned to me.
             flagged: ((not ticket.assignee.nil?) and ticket.assignee.attrs["name"] == USERNAME),
             # Get parent task, if any
             parent_task: ticket.fields[ParentTaskField],
             # Get due date, if any
             due_date: (ticket.duedate && Date.parse(ticket.duedate))
            )
  end

end

def mark_resolved_jira_tickets_as_complete_in_omnifocus ()
  # get tasks from the project
  omnifocus_app = Appscript.app.by_name("OmniFocus")
  omnifocus_document = omnifocus_app.default_document
  ctx = omnifocus_document.flattened_contexts[DEFAULT_CONTEXT]
  ctx.flattened_contexts.get.each do |ctx|
    tasks = ctx.tasks.get
    tasks.each do |task|
      if !task.completed.get && task.note.get.match(JIRA_BASE_URL)
        # try to parse out jira id
        full_url= task.note.get
        jira_id=full_url.sub(JIRA_BASE_URL+"/browse/","")
        ticket = JIRACLIENT.Issue.find(jira_id)
        status = ticket.fields["status"]
        if ['Closed', 'Resolved'].include? status["name"]
          # if resolved, mark it as complete in OmniFocus
          if task.completed.get == false
            task.completed.set(true)
            QUIET or Growler.notify 'Task Completed', task.name.get, "OmniFocus task marked completed"
          end
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
