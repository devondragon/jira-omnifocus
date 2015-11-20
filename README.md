jira-omnifocus
==============

Ruby script to create and manage OmniFocus tasks based on your Jira tickets

http://www.digitalsanctuary.com/tech-blog/general/jira-to-omnifocus-integration.html

What it does:

It pulls back all unresolved Jira tickets that are assigned to you and if it hasn't already created a OmniFocus task for that ticket, it creates a new one.  The title of the task is the Jira ticket number followed by the summary from the ticket.  The note part of the OmniFocus task will contain the URL to the Jira ticket so you can easily go right to it.  I chose not to pull over the full description, or comment history into the task notes as it's usually more than I want to see in OmniFocus.

It also checks all the OmniFocus tasks that look like they are related to Jira tickets, and checks to see if the matching ticket has been resolved.  If so, it marks the task as complete. If a task has been re-assigned to someone else or unassigned it will remove it from Omnifocus.

Very simple.  The Ruby code is straight forward and it should be easy to modify to do other things to meet your specific needs.

This uses [Bundler](http://bundler.io/), so you will need to run the following to set everything up.

```
gem install bundler
bundle install
```

This also support [rbenv](http://rbenv.org/), if you happen to be using it.

You'll need to copy jofsync.yaml.sample from the git checkout to ~/.jofsync.yaml, and then edit is as appropriate.

Make sure that you have a project in context in Omnifocus that matches what you used in the configuration file.

You can run the script manually or you can add a cron entry to run it periodically (it will take a minute or so to run so don't run it too often), or you can use the OS X launchd to schedule it (this is preferred).  If you are using the keychain option, you MUST use the launchd scheduler isntead of cron.

You can use crontab -e to edit your user crontab and create an entry like this:

```
*/10 * * * * cd ~/dev/git/jira-omnifocus/bin && ./jiraomnifocus.rb
```


To install it in launchd, edit jofsync.plist to meet your needs and copy it to ~/Library/LaunchAgents/jofsync.plist and run

```
launchctl load ~/Library/LaunchAgents/jofsync.plist
```

That should be it!  If it doesn't work, try adding some puts debug statements and running it manually.  
I can't offer any support, as I don't know Ruby that well and just magically cobbled this together:)

UPDATE:

I have manually merged in some features from https://github.com/cgarrigues/jira-omnifocus as per discussion on https://github.com/devondragon/jira-omnifocus/pull/15   

To use the keychain option, you have to create the keychain entry:

security add-internet-password -a <username> -s <hostname> -w <password>
	
