jira-omnifocus
==============

Ruby script to create and manage OmniFocus tasks based on your Jira tickets


http://www.digitalsanctuary.com/tech-blog/general/jira-to-omnifocus-integration.html

What it does is two things:

It pulls back all unresolved Jira tickets that are assigned to you and if it hasn’t already created a OmniFocus task for that ticket, it creates a new one.  The title of the task is the Jira ticket number followed by the summary from the ticket.  The note part of the OmniFocus task is just the URL to the Jira ticket so you can easily go right to it.  I chose not to pull over the full description, or comment history into the task notes as it’s usually more than I want to see in OmniFocus.

It also checks all the OmniFocus tasks that look like they are related to Jira tickets, and checks to see if the matching ticket has been resolved.  If so, it marks the task as complete.

Very simple.  The Ruby code is straight forward and it should be easy to modify to do other things to meet your specific needs.

You will need to install a few gems

gem install rb-appscript json
You’ll need to edit the configuration values at the top of the script (please note this current version does not hide/encrypt your password), and then save it somewhere.  I have mine in /Users/devon/bin/ but you can put it anywhere.  Then you can add a cron entry to run it every 5 minutes or 10 minutes or whatever you need (it will take a minute or so to run so don’t make it run too often).

You can use crontab -e to edit your user crontab and create an entry like this:

*/10 * * * * /Users/devon/bin/jiraomnifocus.rb
That should be it!  If it doesn’t work, try adding some puts debug statements and running it manually.  I can’t offer any support, as I don’t know Ruby that well and just magically cobbled this together:)

