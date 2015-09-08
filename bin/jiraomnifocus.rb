#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require(:default)

require 'appscript'
require 'yaml'
require 'net/http'
require 'keychain'

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
  version 'jofsync 1.0.0'
  opt :hostname, 'Jira Server Hostname', :type => :string, :short => 'h', :required => false
  opt :context, 'OF Default Context', :type => :string, :short => 'c', :required => false
  opt :project, 'OF Default Project', :type => :string, :short => 'r', :required => false
  opt :filter, 'JQL Filter', :type => :string, :short => 'j', :required => false
  opt :quiet, 'Disable terminal output', :short => 'q', :default => true
end

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

syms = [:hostname, :context, :project, :filter]
syms.each { |x|
  unless opts[x]
    if config[:jira][x]
      opts[x] = config[:jira][x]
    else
      puts 'Please provide a ' + x.to_s + ' value on the CLI or in the config file.'
      exit 1
    end
 end
}

#JIRA Configuration
JIRA_BASE_URL = opts[:hostname]

host = URI(JIRA_BASE_URL).host
keychainitem = Keychain.internet_passwords.where(:server => host).first
USERNAME = keychainitem.account
PASSWORD = keychainitem.password

QUERY = opts[:filter]
JQL = URI::encode(QUERY)

#OmniFocus Configuration
DEFAULT_CONTEXT = opts[:context]
DEFAULT_PROJECT = opts[:project]

# This method gets all issues that you are watching and whose resolution is Unresolved.  It returns a Hash where the key is the Jira Ticket Key and the value is the Jira Ticket Summary.
def get_issues
  jira_issues = Hash.new
  # This is the REST URL that will be hit.  Change the jql query if you want to adjust the query used here
  uri = URI(JIRA_BASE_URL + '/rest/api/2/search?jql=' + JQL)

  Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new(uri)
    request.basic_auth USERNAME, PASSWORD
    response = http.request request
    # If the response was good, then grab the data
    if response.code =~ /20[0-9]{1}/
        data = JSON.parse(response.body)
        data["issues"].each do |item|
          jira_id = item["key"]
#          jira_issues[jira_id] = item["fields"]["summary"]
          jira_issues[jira_id] = item
        end
    else
     raise StandardError, "Unsuccessful HTTP response code: " + response.code
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
  name   = new_task_properties["name"]
  flagged = new_task_properties["flagged"]
  task = proj.tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == name }

  if not task
    ctx = omnifocus_document.flattened_contexts[DEFAULT_CONTEXT]
    # If there is a passed in OF context name, get the actual context object (creating if necessary)
    if ctx_name = new_task_properties["context"]
      ctx = ctx.contexts.get.find { |c| c.name.get.force_encoding("UTF-8") == ctx_name } || ctx.make(:new => :context, :with_properties => {:name => ctx_name})
    end
    
    # Do some task property filtering.  I don't know what this is for, but found it in several other scripts that didn't work...
    tprops = new_task_properties.inject({}) do |h, (k, v)|
      h[:"#{k}"] = v
      h
    end
    
    # Remove the project property from the new Task properties, as it won't be used like that.
    tprops.delete(:project)
    # Update the context property to be the actual context object not the context name
    tprops[:context] = ctx
    
    # You can uncomment this line and comment the one below if you want the tasks to end up in your Inbox instead of a specific Project
#  new_task = omnifocus_document.make(:new => :inbox_task, :with_properties => tprops)

    # Make a new Task in the Project
    task = proj.make(:new => :task, :with_properties => tprops)
    puts "task created"
    return task
  else
    # Make sure the flag is set correctly.
    task.flagged.set(flagged)
    return task
  end
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
  results.each do |jira_id, ticket|
    # Create the task name by adding the ticket summary to the jira ticket key
    task_name = "#{jira_id}: #{ticket["fields"]["summary"]}"
    # Create the task notes with the Jira Ticket URL
    task_notes = "#{JIRA_BASE_URL}/browse/#{jira_id}"
    
    # Build properties for the Task
    @props = {}
    @props['name'] = task_name
    @props['project'] = DEFAULT_PROJECT
#   @props['context'] = ticket["fields"]["reporter"]["displayName"]
    @props['context'] = ticket["fields"]["reporter"]["displayName"].split(", ").reverse.join(" ")
    @props['note'] = task_notes
    # Flag the task iff it's assigned to me.
    @props['flagged'] = ((not ticket["fields"]["assignee"].nil?) and (ticket["fields"]["assignee"]["name"] == USERNAME))
    unless ticket["fields"]["duedate"].nil?
      @props["due_date"] = Date.parse(ticket["fields"]["duedate"])
    end
    add_task(omnifocus_document, @props)
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
        # check status of the jira
        uri = URI(JIRA_BASE_URL + '/rest/api/2/issue/' + jira_id)
        
        Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new(uri)
          request.basic_auth USERNAME, PASSWORD
          response = http.request request
          
          if response.code =~ /20[0-9]{1}/
            data = JSON.parse(response.body)
            # Check to see if the Jira ticket has been resolved, if so mark it as complete.
            status = data["fields"]["status"]
            if ['Closed', 'Resolved'].include? status["name"]
              # if resolved, mark it as complete in OmniFocus
              if task.completed.get != true
                task.completed.set(true)
                puts "task marked completed"
              end
            end
          else
            raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
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
