require 'hashie'
require 'json'

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

  def inspect
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
  def fetch
    uri = URI(JIRA_BASE_URL + '/rest/api/2/issue/' + key)
    Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      request.basic_auth USERNAME, PASSWORD
      response = http.request request
      if response.code =~ /20[0-9]{1}/
        data = JSON.parse(response.body)
        fetched_issue = Issue.new(data["key"], data["fields"])
        yield fetched_issue if block_given?
      else
       raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
      end
      fetched_issue
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
      # puts [item["key"], jira_issues[item["key"]], item["fields"]["summary"]].inspect
    end
    return jira_issues    
  end

end