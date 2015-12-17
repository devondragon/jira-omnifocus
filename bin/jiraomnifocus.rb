#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require(:default)

require 'rb-scpt'
require 'yaml'
require 'net/http'
require 'keychain'
require 'pathname'

def get_opts
  if  File.file?(ENV['HOME']+'/.jofsync.yaml')
    config = YAML.load_file(ENV['HOME']+'/.jofsync.yaml')
  else config = YAML.load <<-EOS
#YAML CONFIG EXAMPLE
---
jira:
  hostname: 'http://please-configure-me-in-jofsync.yaml.atlassian.net'
  keychain: false
  username: ''
  password: ''
  filter:   'resolution = Unresolved and issue in watchedissues()'
omnifocus:
  context:  'Office'
  project:  'Jira'
  flag: true
EOS
  end

  return Trollop::options do
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
  opt :usekeychain,'Use Keychain for Jira',:type => :boolean,  :short => 'k', :required => false,   :default => config["jira"]["keychain"]
  opt :username,  'Jira Username',        :type => :string,   :short => 'u', :required => false,   :default => config["jira"]["username"]
  opt :password,  'Jira Password',        :type => :string,   :short => 'p', :required => false,   :default => config["jira"]["password"]
  opt :hostname,  'Jira Server Hostname', :type => :string,   :short => 'h', :required => false,   :default => config["jira"]["hostname"]
  opt :filter,    'JQL Filter',           :type => :string,   :short => 'j', :required => false,   :default => config["jira"]["filter"]
  opt :context,   'OF Default Context',   :type => :string,   :short => 'c', :required => false,   :default => config["omnifocus"]["context"]
  opt :project,   'OF Default Project',   :type => :string,   :short => 'r', :required => false,   :default => config["omnifocus"]["project"]
  opt :flag,      'Flag tasks in OF',     :type => :boolean,  :short => 'f', :required => false,   :default => config["omnifocus"]["flag"]
  opt :quiet,     'Disable output',       :type => :boolean,   :short => 'q',                      :default => true
end
end

# This method gets all issues that are assigned to your USERNAME and whos status isn't Closed or Resolved.  It returns a Hash where the key is the Jira Ticket Key and the value is the Jira Ticket Summary.
def get_issues
  jira_issues = Hash.new
  # This is the REST URL that will be hit.  Change the jql query if you want to adjust the query used here
  uri = URI($opts[:hostname] + '/rest/api/2/search?jql=' + URI::encode($opts[:filter]))

  if $opts[:usekeychain]
    keychainUri = URI($opts[:hostname])
    host = keychainUri.host
    if keychainitem = Keychain.internet_passwords.where(:server => host).first
	    keychainitem = Keychain.internet_passwords.where(:server => 'www.sparkred.com').first
    	$opts[:username] = keychainitem.account
    	$opts[:password] = keychainitem.password
    else
    	raise "Password for #{host} not found in keychain; add it using 'security add-internet-password -a <username> -s #{host} -w <password>'"
    end
  end

  Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new(uri)
    request.basic_auth $opts[:username], $opts[:password]
    response = http.request request
    # If the response was good, then grab the data
    if response.code =~ /20[0-9]{1}/
        data = JSON.parse(response.body)
        data["issues"].each do |item|
          jira_id = item["key"]
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
  # If there is, just stop.
  name   = new_task_properties["name"]
  exists = proj.tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == name }
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
def add_jira_tickets_to_omnifocus (omnifocus_document)
  # Get the open Jira issues assigned to you
  results = get_issues
  if results.nil?
    puts "No results from Jira"
    exit
  end

  # Iterate through resulting issues.
  results.each do |jira_id, ticket|
    # Create the task name by adding the ticket summary to the jira ticket key
    task_name = "#{jira_id}: #{ticket["fields"]["summary"]}"
    # Create the task notes with the Jira Ticket URL
    task_notes = "#{$opts[:hostname]}/browse/#{jira_id}"

    # Build properties for the Task
    @props = {}
    @props['name'] = task_name
    @props['project'] = $opts[:project]
    @props['context'] = $opts[:context]
    @props['note'] = task_notes
    @props['flagged'] = $opts[:flag]
    unless ticket["fields"]["duedate"].nil?
      @props["due_date"] = Date.parse(ticket["fields"]["duedate"])
    end
    add_task(omnifocus_document, @props)
  end
end

def mark_resolved_jira_tickets_as_complete_in_omnifocus (omnifocus_document)
  # get tasks from the project
  ctx = omnifocus_document.flattened_contexts[$opts[:context]]
  ctx.tasks.get.find.each do |task|
    if !task.completed.get && task.note.get.match($opts[:hostname])
      # try to parse out jira id
      full_url= task.note.get
      jira_id=full_url.sub($opts[:hostname]+"/browse/","")
      # check status of the jira
      uri = URI($opts[:hostname] + '/rest/api/2/issue/' + jira_id)

      Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request.basic_auth $opts[:username], $opts[:password]
        response = http.request request

        if response.code =~ /20[0-9]{1}/
            data = JSON.parse(response.body)
            # Check to see if the Jira ticket has been resolved, if so mark it as complete.
            resolution = data["fields"]["resolution"]
            if resolution != nil
              # if resolved, mark it as complete in OmniFocus
              if task.completed.get != true
                task.completed.set(true)
                puts "task marked completed"
              end
            end
            # Check to see if the Jira ticket has been unassigned or assigned to someone else, if so delete it.
            # It will be re-created if it is assigned back to you.
            if ! data["fields"]["assignee"]
              omnifocus_document.delete task
            else
              assignee = data["fields"]["assignee"]["name"]
              if assignee != $opts[:username]
                omnifocus_document.delete task
              end
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

def get_omnifocus_document
  return Appscript.app.by_name("OmniFocus").default_document
end

def main ()
   if app_is_running("OmniFocus")
     $opts = get_opts
     omnifocus_document = get_omnifocus_document
	   add_jira_tickets_to_omnifocus(omnifocus_document)
	   mark_resolved_jira_tickets_as_complete_in_omnifocus(omnifocus_document)
   end
end

main
