#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'rb-scpt'
require 'yaml'
require 'net/http'
require 'keychain'
require 'pathname'
require 'optimist'

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
  password: '' 			# JIRA password OR api_token
  filter:   'resolution = Unresolved and issue in watchedissues()'
  ssl_verify: true     # Verify the server certificate
omnifocus:
  tag:  'Office'   # The default OF Tag where new tasks are created.
  project:  'Jira'     # The default OF Project where new tasks are created.
  flag:     true       # Set this to 'true' if you want the new tasks to be flagged.
  inbox:    false      # Set 'true' if you want tasks in the Inbox instead of in a specific project.
  newproj:  false      # Set 'true' to add each JIRA ticket to OF as a Project instead of a Task.
  folder:   'Jira'     # Sets the OF folder where new Projects are created (only applies if 'newproj' is 'true').
  descsync:  false     # Set 'true' if you want JIRA task descriptions synced to OF task notes
EOS
  end

  return Optimist::options do
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
    opt :ssl_verify, 'SSL verification', :type => :boolean,  :short => 's', :required => false,  :default => config['jira'].has_key?('ssl_verify') ? config['jira']['ssl_verify'] : true
    opt :tag,   'OF Default Tag',   :type => :string,   :short => 'c', :required => false,   :default => config["omnifocus"]["tag"]
    opt :project,   'OF Default Project',   :type => :string,   :short => 'r', :required => false,   :default => config["omnifocus"]["project"]
    opt :flag,      'Flag tasks in OF',     :type => :boolean,  :short => 'f', :required => false,   :default => config["omnifocus"]["flag"]
    opt :folder,  'OF Default Folder',  :type => :string,  :short => 'o', :required => false,   :default => config["omnifocus"]["folder"]
    opt :inbox,     'Create inbox tasks',  :type => :boolean,  :short => 'i', :required => false,   :default => config["omnifocus"]["inbox"]
    opt :newproj,  'Create as projects',  :type => :boolean,  :short => 'n', :required => false,   :default => config["omnifocus"]["newproj"]
    opt :descsync,  'Sync Description to Notes',  :type => :boolean,  :short => 'd', :required => false,   :default => config["omnifocus"]["descsync"]
    opt :quiet,     'Disable output',       :type => :boolean,  :short => 'q',                       :default => true
  end
end

# This method gets all issues that are assigned to your USERNAME and whos status isn't Closed or Resolved.  It returns a Hash where the key is the Jira Ticket Key and the value is the Jira Ticket Summary.
def get_issues
  if $DEBUG
    puts "JOFSYNC.get_issues: starting method..."
  end
  jira_issues = Hash.new
  # This is the REST URL that will be hit.  Change the jql query if you want to adjust the query used here
  uri = URI($opts[:hostname] + '/rest/api/2/search?jql=' + URI::encode($opts[:filter]) + '&maxResults=-1')
  if $DEBUG
    puts "JOFSYNC.get_issues: about to hit URL: " + uri.to_s()
  end
  if $opts[:usekeychain]
    if $DEBUG
      puts "JOFSYNC.get_issues: using Keychain for auth"
    end
    keychainUri = URI($opts[:hostname])
    host = keychainUri.host
    if $DEBUG
      puts "JOFSYNC.get_issues: looking for first Keychain entry for host: " + host
    end
    if keychainitem = Keychain.internet_passwords.where(:server => host).first
      $opts[:username] = keychainitem.account
      $opts[:password] = keychainitem.password
      if $DEBUG
        puts "JOFSYNC.get_issues: credentials loaded from Keychain"
      end
    else
      raise "Password for #{host} not found in keychain; add it using 'security add-internet-password -a <username> -s #{host} -w <password>'"
    end
  end

  if $DEBUG
    puts "JOFSYNC.get_issues: abount to connect...."
  end

  verify_mode = $opts[:ssl_verify] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
  Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https', :verify_mode => verify_mode) do |http|
    request = Net::HTTP::Get.new(uri)
    request.basic_auth $opts[:username], $opts[:password]
    response = http.request request
    # If the response was good, then grab the data
    if $DEBUG
      puts "JOFSYNC.get_issues: response code: " + response.code
    end
    if response.code =~ /20[0-9]{1}/
      puts "Connected successfully to " + uri.hostname
      data = JSON.parse(response.body)
      if $DEBUG
        puts "JOFSYNC.get_issues: response parsed successfully!"
      end
      data["issues"].each do |item|
        jira_id = item["key"]
        if $DEBUG
          puts "JOFSYNC.get_issues: adding JIRA item: " + jira_id + " to the jira_issues array"
        end
        jira_issues[jira_id] = item
      end
    else
      # Use terminal-notifier to notify the user of the bad response--useful when running this script from a LaunchAgent
      notify_message = "Response code: " + response.code
      TerminalNotifier.notify(notify_message, :title => "JIRA OmniFocus Sync", :subtitle => uri.hostname, :sound => 'default')
      raise StandardError, "Unsuccessful HTTP response code " + response.code + " from " + uri.hostname
    end
  end
  if $DEBUG
    puts "JOFSYNC.get_issues: method_complete, returning jira_issues."
  end
  return jira_issues
end

# This method adds a new Task to OmniFocus based on the new_task_properties passed in
def add_task(omnifocus_document, new_task_properties)
  # If there is a passed in OF project name, get the actual project object
  if $DEBUG
    puts "JOFSYNC.add_task: starting method..."
  end

  if new_task_properties['project']
    proj_name = new_task_properties["project"]
    if $DEBUG
      puts "JOFSYNC.add_task: new task specified a project name of: " + proj_name + " so going to load that up"
    end
    proj = omnifocus_document.flattened_tasks[proj_name]
    if $DEBUG
      puts "JOFSYNC.add_task: project loaded successfully"
    end
  end

  # Check to see if there's already an OF Task with that name
  # If there is, just stop.
  name   = new_task_properties["name"]
  if $DEBUG
    puts "JOFSYNC.add_task: going to check for existing tasks with the same name: " + name
  end

  if $opts[:inbox]
    # Search your entire OF document, instead of a specific project.
    if $DEBUG
      puts "JOFSYNC.add_task: inbox flag set, so need to search the entire OmniFocus document"
    end
    exists = omnifocus_document.flattened_tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == name }
    if $DEBUG
      puts "JOFSYNC.add_task: task exists = " + exists.to_s()
    end
  elsif $opts[:newproj]
    # Search your entire OF document, instead of a specific project.
    if $DEBUG
      puts "JOFSYNC.add_task: new project flag set, so need to search the entire OmniFocus document"
    end
    exists = omnifocus_document.flattened_tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == name }
    if $DEBUG
      puts "JOFSYNC.add_task: task exists = " + exists.to_s()
    end
  else
    # If you are keeping all your JIRA tasks in a single Project, we only need to search that Project
    if $DEBUG
      puts "JOFSYNC.add_task: searching only project: " + proj.name.get
    end
    exists = proj.tasks.get.find { |t| t.name.get.force_encoding("UTF-8") == name }
    if $DEBUG
      puts "JOFSYNC.add_task: task exists = " + exists.to_s()
    end
  end

  return false if exists

	# If there is a passed in OF tag name, get the actual tag object
	if new_task_properties['tag']
		tag_name = new_task_properties["tag"]
		tag = omnifocus_document.flattened_tags[tag_name]
	end

  # Do some task property filtering.  I don't know what this is for, but found it in several other scripts that didn't work...
  tprops = new_task_properties.inject({}) do |h, (k, v)|
    h[:"#{k}"] = v
    h
  end

  # Remove the project property from the new Task properties, as it won't be used like that.
  tprops.delete(:project)
  # Update the tag property to be the actual tag object not the tag name
  tprops.delete(:tag)
	tprops[:primary_tag] = tag if new_task_properties['tag']

  if $DEBUG
    puts "JOFSYNC.add_task: task props - deleted project and set tag"
  end

  # Create the task in the appropriate place as set in the config file
  if $opts[:inbox]
    # Create the tasks in your Inbox instead of a specific Project
    if $DEBUG
      puts "JOFSYNC.add_task: adding Task to Inbox"
    end
    new_task = omnifocus_document.make(:new => :inbox_task, :with_properties => tprops)
    puts "Created inbox task: " + tprops[:name]
  elsif $opts[:newproj]
    # Create the task as a new project in a folder
    if $DEBUG
      puts "JOFSYNC.add_task: adding Task as a new Project"
    end
    of_folder = omnifocus_document.folders[$opts[:folder]]
    new_task = of_folder.make(:new => :project, :with_properties => tprops)
    puts "Created project in " + $opts[:folder] + " folder: " + tprops[:name]
  else
    # Make a new Task in the Project
    if $DEBUG
      puts "JOFSYNC.add_task: adding Task to project: " + proj_name
    end
    proj.make(:new => :task, :with_properties => tprops)
    puts "Created task [" + tprops[:name] + "] in project " + proj_name
  end
  if $DEBUG
    puts "JOFSYNC.add_task: completed method."
  end
  return true
end

# This method is responsible for getting your assigned Jira Tickets and adding them to OmniFocus as Tasks
def add_jira_tickets_to_omnifocus (omnifocus_document)
  # Get the open Jira issues assigned to you
  if $DEBUG
    puts "JOFSYNC.add_jira_tickets_to_omnifocus: starting method... and about to get_issues"
  end
  results = get_issues
  if results.nil?
    puts "No results from Jira"
    exit
  end

  if $DEBUG
    puts "JOFSYNC.add_jira_tickets_to_omnifocus: looping through issues found."
  end
  # Iterate through resulting issues.
  results.each do |jira_id, ticket|
    if $DEBUG
      puts "JOFSYNC.add_jira_tickets_to_omnifocus: looking at jira_id: " + jira_id
    end
    # Create the task name by adding the ticket summary to the jira ticket key
    task_name = "#{jira_id}: #{ticket["fields"]["summary"]}"
    if $DEBUG
      puts "JOFSYNC.add_jira_tickets_to_omnifocus: created task_name: " + task_name
    end
    # Create the task notes with the Jira Ticket URL
    if $opts[:descsync]
      task_notes = "#{$opts[:hostname]}/browse/#{jira_id}\n\n#{ticket["fields"]["description"]}"
    else
      task_notes = "#{$opts[:hostname]}/browse/#{jira_id}\n"
    end

    # Build properties for the Task
    @props = {}
    @props['name'] = task_name
    @props['project'] = $opts[:project]
    @props['tag'] = $opts[:tag] if $opts[:tag]
    @props['note'] = task_notes
    @props['flagged'] = $opts[:flag]
    unless ticket["fields"]["duedate"].nil?
      @props["due_date"] = Date.parse(ticket["fields"]["duedate"])
    end
    if $DEBUG
      puts "JOFSYNC.add_jira_tickets_to_omnifocus: built properties, about to add Task to OmniFocus"
    end
    add_task(omnifocus_document, @props)
    if $DEBUG
      puts "JOFSYNC.add_jira_tickets_to_omnifocus: task added to OmniFocus."
    end
  end
  if $DEBUG
    puts "JOFSYNC.add_jira_tickets_to_omnifocus: method complete"
  end
end

def mark_resolved_jira_tickets_as_complete_in_omnifocus (omnifocus_document)
  # get tasks from the project
  if $DEBUG
    puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: starting method"
  end
  omnifocus_document.flattened_tasks.get.find.each do |task|
  if $DEBUG
    puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: About to iterate through all tasks in OmniFocus document"
  end
    if $DEBUG
      puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: working on task: " + task.name.get
    end
    if !task.completed.get && task.note.get.match($opts[:hostname])
      if $DEBUG
        puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: task is NOT already marked complete, so let's check the status of the JIRA ticket."
      end
      # try to parse out jira id
      full_url= task.note.get.lines.first.chomp
      if $DEBUG
        puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: got full_url: " + full_url
      end
      jira_id=full_url.sub($opts[:hostname]+"/browse/","")
      if $DEBUG
        puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: got jira_id: " + jira_id
      end
      # check status of the jira
      begin
        uri = URI($opts[:hostname] + '/rest/api/2/issue/' + jira_id)
        if $DEBUG
          puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: about to hit: " + uri.to_s()
        end
        
        
        verify_mode = $opts[:ssl_verify] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
        Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https', :verify_mode => verify_mode) do |http|
          request = Net::HTTP::Get.new(uri)
          request.basic_auth $opts[:username], $opts[:password]
          response = http.request request
          if $DEBUG
            puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: response code: " + response.code
          end
          if response.code =~ /20[0-9]{1}/
            data = JSON.parse(response.body)
            # Check to see if the Jira ticket has been resolved, if so mark it as complete.
            resolution = data["fields"]["resolution"]
            if $DEBUG
              puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: resolution: " + resolution.to_s()
            end
            if resolution != nil
              # if resolved, mark it as complete in OmniFocus
              if $DEBUG
                puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: resolution was non-nil, so marking this Task as completed. "
              end
              if task.completed.get != true
                task.mark_complete()
                puts "Marked task completed " + jira_id
              end
            else
              # Moving the assignment check block into the else block here...  The upside is that if you resolve a ticket and assign it back
              # to the creator, you get the Completed checked task in OF which makes you feel good, instead of the current behavior where the task is deleted and vanishes from OF.
              # Check to see if the Jira ticket has been unassigned or assigned to someone else, if so delete it.
              # It will be re-created if it is assigned back to you.
              if $DEBUG
                puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: Checking to see if the task was assigned to someone else. "
              end
              if ! data["fields"]["assignee"]
                if $DEBUG
                  puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: There is no assignee, so deleting. "
                end
                omnifocus_document.delete task
              else
                assignee = data["fields"]["assignee"]["name"].downcase
                if $DEBUG
                  puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: curent assignee is: " + assignee
                end
                if assignee != $opts[:username].downcase
                  if $DEBUG
                    puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: That doesn't match your username of \"" + $opts[:username].downcase + "\" so deleting the task from OmniFocus"
                  end
                  omnifocus_document.delete task
                  
                else 
                  assignee = data["fields"]["assignee"]["name"].downcase 
                  assigneeEmail = data["fields"]["assignee"]["emailAddress"].downcase 
                  
                  if $DEBUG 
                    puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: curent assignee is: " + assignee 
                  end 
                  
                  if assignee != $opts[:username].downcase && assigneeEmail != $opts[:username].downcase 
                    if $DEBUG 
                      puts "JOFSYNC.mark_resolved_jira_tickets_as_complete_in_omnifocus: That doesn't match your username of \"" + $opts[:username].downcase + "\" so deleting the task from OmniFocus" 
                    end 
                    omnifocus_document.delete task 
                  end
                end
              end
            end
          else
            raise StandardError, "Unsuccessful response code " + response.code + " for issue " + jira_id
          end
        end
      rescue Net::HTTPError => e
        puts "HTTP Error for JIRA #{jira_id}: #{e.message}"
        puts e.backtrace.first(5).join("\n") if $DEBUG
        next
      rescue JSON::ParserError => e
        puts "Failed to parse JIRA response for #{jira_id}: #{e.message}"
        next
      rescue StandardError => e
        puts "Unexpected error processing #{jira_id}: #{e.class} - #{e.message}"
        puts e.backtrace.first(10).join("\n") if $DEBUG
        next
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

def check_options()
  if $opts[:hostname] == 'http://please-configure-me-in-jofsync.yaml.atlassian.net'
    raise StandardError, "The hostname is not set. Did you create ~/.jofsync.yaml?"
  end
end

def main ()
  if $DEBUG
    puts "JOFSYNC.main: Running..."
  end
  if app_is_running("OmniFocus")
    if $DEBUG
      puts "JOFSYNC.main: OmniFocus is running so let's go!"
    end
    $opts = get_opts
    check_options()
    if $DEBUG
      puts "JOFSYNC.main: Options have been checked, moving on...."
    end
    omnifocus_document = get_omnifocus_document
    if $DEBUG
      puts "JOFSYNC.main: Got OmniFocus document to work on, about to add JIRA tickets to OmniFocus"
    end
    add_jira_tickets_to_omnifocus(omnifocus_document)
    if $DEBUG
      puts "JOFSYNC.main: Done adding JIRA tickets to OmniFocus, about to mark resolved JIRA tickets as complete in OmniFocus."
    end
    mark_resolved_jira_tickets_as_complete_in_omnifocus(omnifocus_document)
    if $DEBUG
      puts "JOFSYNC.main: Done!"
    end
  end
end

main
