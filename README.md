jira-omnifocus
==============

Ruby script to create and manage OmniFocus tasks based on your Jira tickets

http://www.digitalsanctuary.com/tech-blog/general/jira-to-omnifocus-integration.html

What it does:

It pulls back all unresolved Jira tickets that you are watching and if it hasn't already created a OmniFocus task for that ticket, it creates a new one.  The title of the task is the Jira ticket number followed by the summary from the ticket.  The note part of the OmniFocus task will contain the URL to the Jira ticket so you can easily go right to it.  I chose not to pull over the full description, or comment history into the task notes as it's usually more than I want to see in OmniFocus. If the ticket is assigned to you, it will be flagged. The context will be set based on who generated the ticket.  If there is no existing context, one will be created.

It also checks all the OmniFocus tasks that look like they are related to Jira tickets, and checks to see if the matching ticket has been resolved.  If so, it marks the task as complete. If a task has been re-assigned to someone else or unassigned it will no longer be flagged.

Very simple.  The Ruby code is straight forward and it should be easy to modify to do other things to meet your specific needs.

This uses [Bundler](http://bundler.io/), so you will need to run the following to set everything up.

```
gem install bundler
bundle install
```

This also supports [rbenv](http://rbenv.org/), if you happen to be using it.

You'll need to copy jofsync.yaml.sample from the git checkout to ~/.jofsync.yaml, and then edit it as appropriate.

Make sure that you have a project and context in OmniFocus that match what you used in the configuration file.

Your username and password for the Jira server must be defined in your keychain. Unlike previous versions of this script, your password is not stored in plain text.

This version of jofsync will not run under cron and instead needs to be run under launchd.  This is because it requires access to the keychain in lieu of hardcoded passwords.

To install it in launchd, edit jofsync.plist to meet your needs and copy it to ~/Library/LaunchAgents/jofsync.plist and run

```
launchctl load ~/Library/LaunchAgents/jofsync.plist
```

That should be it!  If it doesn't work, try adding some puts debug statements and running it manually.  
I can't offer any support, as I don't know Ruby that well and just magically cobbled this together:)

