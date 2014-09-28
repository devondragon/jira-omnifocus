#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require(:default)

require 'appscript'
require 'yaml'

opts = Trollop::options do
  banner ""
  banner <<-EOS
Jira Omnifocus Sync Tool

Usage:
       jofsync [options]

KNOWN ISSUES:
      * With long names you must use an equal sign ( i.e. --hostname=test-target-1 )

---
EOS
  version 'jofsync 1.0.0'
  opt :username, 'Jira Username', :type => :string, :short => 'u', :required => false
  opt :password, 'Jira Password', :type => :string, :short => 'p', :required => false
  opt :hostname, 'Jira Server Hostname', :type => :string, :short => 'h', :required => false
  opt :context, 'OF Default Context', :type => :string, :short => 'c', :required => false
  opt :project, 'OF Default Project', :type => :string, :short => 'r', :required => false
  opt :flag, 'Flag tasks in OF', :type => :boolean, :short => 'f', :required => false
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
  hostname: 'example.atlassian.net'
  username: 'jdoe'
  password: 'blahblahblah'
  context: 'Jira'
  project: 'Work'
  flag: true
  filter: 'assignee = currentUser() AND status not in (Closed, Resolved) AND sprint in openSprints()'
=end
end

syms = [:username, :hostname, :context, :project, :flag, :filter]
syms.each do |x|
  unless opts[x]
    if config[:jira][x]
      opts[x] = config[:jira][x]
    else
      puts 'Please provide a ' + x.to_s + ' value on the CLI or in the config file.'
      exit 1
    end
 end
end

unless opts[:password]
  if config[:jira][:password]
    opts[:password] = config[:jira][:password]
  else
    opts[:password] = ask("password: ") {|q| q.echo = false}
  end
end

#JIRA Configuration
JIRA_BASE_URL = 'https://' + opts[:hostname]
USERNAME = opts[:username]
PASSWORD = opts[:password]

QUERY = opts[:filter]
p ['QUERY', QUERY]

#OmniFocus Configuration
DEFAULT_CONTEXT = opts[:context]
DEFAULT_PROJECT = opts[:project]
FLAGGED = opts[:flag]


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

# class to hold jira issues
class Issue < Hash
  include Hashie::Extensions::MethodAccess
  include Hashie::Extensions::IndifferentAccess

  attr_reader :key, :summary, :properties, :fields
  attr_accessor :context, :project, :flagged, :omnifocus_project, :omnifocus_task, :omnifocus_context

  def initialize(key, issue_attributes={})
    @project = DEFAULT_PROJECT,
    @context = DEFAULT_CONTEXT,
    @flagged = FLAGGED  #TODO: check if issue is flagged, and use that instead
    @key = key
    @summary = issue_attributes['summary'] if issue_attributes['summary']
    @fields = Hashie::Mash.new issue_attributes 
    # @rank = @fields.rank if issue_attributes['rank']  #TODO: fetch sort order
  end

  def to_s
    task_name
  end

  # Create the task name by adding the ticket summary to the jira ticket key
  def task_name
    "#{key}: #{summary}"
  end

  # Create the task notes with the Jira Ticket URL to go into the notes
  def task_notes
    "#{JIRA_BASE_URL}/browse/#{key}"
  end

  # return a hash of properties used when adding or updating an omnifocus task
  def omnifocus_properties
    @props = {}
    @props['name'] = task_name
    @props['project'] = omnifocus_project
    @props['context'] = omnifocus_context
    @props['note'] = task_notes
    @props['flagged'] = FLAGGED
  end

  # retrieve current data from jira server for the single issue
  def fetch(opts)
    raise "TODO: not implemented yet"
    uri = URI(JIRA_BASE_URL + '/rest/api/2/issue/' + jira_id)
    Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      request.basic_auth USERNAME, PASSWORD
      response = http.request request
      if response.code =~ /20[0-9]{1}/
        data = JSON.parse(response.body)
        yield Issue.new(data["key"], data["fields"])
      else
       raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
      end
      
    end
  end

  # Fetch collection of issues from the api
  def self.fetch(jql=QUERY, &block)
    query = URI::encode(jql)
    uri = URI(JIRA_BASE_URL + '/rest/api/2/search?jql=' + query)
    Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      request.basic_auth USERNAME, PASSWORD
      response = http.request request
      # If the response was good, then grab the data
      if response.code =~ /20[0-9]{1}/
          data = JSON.parse(response.body)
          data["issues"].each do |item|
            yield item            
          end
      else
       raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
      end
    end
  end

  def self.query_results
    # TODO: add the description
    # TODO: use labels
    Issue.fetch do |item|
      jira_issues[item["key"]]=  Issue.new(item["key"], item["fields"])
      $stderr.puts [item["key"], jira_issues[item["key"]], item["fields"]["summary"]].inspect
    end
    return jira_issues    
  end

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
  p ["task created:", issue.omnifocus_properties]
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
    add_task(issue)
  end
end

def mark_resolved_jira_tickets_as_complete_in_omnifocus ()
  # get tasks from the project
  ctx = omnifocus.context
  ctx.tasks.get.find.each do |task|
    if task.note.get.match(JIRA_BASE_URL)
      # try to parse out jira id
      full_url= task.note.get
      jira_id=full_url.sub(JIRA_BASE_URL+"/browse/","")
      # check status of the jira
      uri = URI(JIRA_BASE_URL + '/rest/api/2/issue/' + jira_id)

      # issue = jira_issues[jira_id]
      #TODO: refactor to use cached issue if present
      # issue = jira_issues[jira_id] ? jira_issues[jira_id] : Issue.new(jira_id).fetch
      #TODO: only fetch when the issue was not already fetched, and present in jira_issues
      
      Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request.basic_auth USERNAME, PASSWORD
        response = http.request request

        if response.code =~ /20[0-9]{1}/
          data = JSON.parse(response.body)
          # Check to see if the Jira ticket has been resolved, if so mark it as complete.
          resolution = data["fields"]["resolution"]
          if resolution != nil #|| %w(Closed, Resolved).include?(issue.status)
            # if resolved, mark it as complete in OmniFocus
            task.completed.set(true)
          end
          # Check to see if the Jira ticket has been unassigned or assigned to someone else, if so delete it.
          # It will be re-created if it is assigned back to you.
          if ! data["fields"]["assignee"]
            omnifocus_document.delete task
          else
            assignee = data["fields"]["assignee"]["name"]
            if assignee != USERNAME
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

def main ()
   if app_is_running("OmniFocus")
	  add_jira_tickets_to_omnifocus
	  mark_resolved_jira_tickets_as_complete_in_omnifocus
   end
end

main
