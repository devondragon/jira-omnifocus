# jira-omnifocus

Ruby script to create and manage OmniFocus tasks based on your JIRA tickets

http://www.digitalsanctuary.com/tech-blog/general/jira-to-omnifocus-integration.html

## What it does:

It pulls back all unresolved JIRA tickets that are assigned to you and if it hasn't already created a OmniFocus task for that ticket, it creates a new one.  The title of the task is the JIRA ticket number followed by the summary from the ticket.  The note part of the OmniFocus task will contain the URL to the JIRA ticket so you can easily go right to it.  I chose not to pull over the full description, or comment history into the task notes as it's usually more than I want to see in OmniFocus.

It also checks all the OmniFocus tasks that look like they are related to JIRA tickets, and checks to see if the matching ticket has been resolved.  If so, it marks the task as complete. If a task has been re-assigned to someone else or unassigned it will remove it from OmniFocus.

Very simple.  The Ruby code is straight forward and it should be easy to modify to do other things to meet your specific needs.

## Dependencies
This project expect you have a Ruby development environment installed, and also supports [rbenv](http://rbenv.org/), if you happen to be using it.

jira-omnifocus also uses [Bundler](http://bundler.io/), so you will need to install it.

```
gem install bundler
bundle install
```

## Using the script

Clone this repository.

```
git clone https://github.com/devondragon/jira-omnifocus.git
cd jira-omnifocus
```

You'll need to copy jofsync.yaml.sample from the git checkout to ~/.jofsync.yaml, and then edit is as appropriate.

```
cp jofsync.yaml.sample ~/.jofsync.yaml
```

### Editing the configuration

In ~/.jofsync.yaml, you'll find various options for configuring your connection to JIRA, and specifying how and where you would like to categorize issues in OmniFocus as they are added by the script.

#### `jira` configuration options
**`hostname`**
The URL of your JIRA project. Make sure to specify `https` if your project requires it.

**`keychain`**
Set this option to `true` if you wish to pull your JIRA credentials from you OS keychain. If you set this option, jira-omnifocus will ignore any values for `password` in the config. If you plan to use this option and automate the process of running this script, you must run it with `launchd` and not `cron`. To use the keychain option, you have to create the keychain entry:

```
security add-internet-password -a <username> -s <hostname> -w <password>
```

**`username` and `password`**
Username needs be set to your actual username, NOT your email address.  You only need to set the password if you've set `keychain` to `false`.  If you are using the new api_token for JIRA, just put the token in as the password.

**`filter`**
This is the JQL (JIRA's custom query language) command jira-omnifocus will use to find issues.

#### `omnifocus` configuration options
**`context`**
The default OmniFocus context assigned to new tasks. Make sure this context exists in OmniFocus. Leave this blank if you'd prefer not to set a context.

**`project`**
The default OmniFocus project assigned to new tasks. Make sure this project exists in OmniFocus. Leave this blank if you'd prefer not to set a project. If you leave this option blank, be sure to set either `inbox` or `newproj` to `true`.

**`flag`**
Set this to `true` if you want the new tasks to be flagged.

**`inbox`**
Set this option to `true` if you want tasks added to the inbox instead of in a specific project. Leave `project` blank and set `newproj` to `false` if this option is set to `true`.

**`newproj`**
Set this option to `true` to add each JIRA ticket to OmniFocus as a project instead of a task. Leave `project` blank and set `inbox` to `false` if this option is set to `true`.

**`folder`**
Sets the OmniFocus folder where new projects are created if `newproj` is `true`. Make sure this folder exists in OmniFocus.

### Running the script

You can run the script manually with `bundle exec bin/jiraomnifocus.rb`, use OS X's `launchd` to schedule it (this is preferred), or add a cron entry to run it periodically (it will take a minute or so to run so don't run it too often).  If you are using the keychain option, you MUST use the `launchd` scheduler instead of `cron`.

#### If you have SSL Connection errors

This is due to an older version of Ruby not supporting modern cipher suites.  In order to fix this on my Mac (running macOS Sierra 10.12.6) I used rbenv to install ruby 2.1.2, and then I set it to be the global default (you don't have to do this if you change how you launch the script, etc...):

```
rbenv install 2.1.2
rbenv global 2.1.2
```

This solved my SSL Connection errors!  At least when running the script manually, there was still something I had to do to make the launchd solution below work, so please read the section below in detail.


#### Running automatically with `launchd`
To install it in launchd, copy jofsync.plist to ~/Library/LaunchAgents/jofsync.plist

```
cp jofsync.plist ~/Library/LaunchAgents/jofsync.plist
```

Edit `~/Library/LaunchAgents/jofsync.plist` to meet your needs. The `WorkingDirectory` and second `ProgramArguments` strings must be set. You can optionally change the `Label` or `StartInterval`. 

**`WorkingDirectory`**
Replace the value of `<string>` with the path to your local clone of the project's `bin`.
```
<key>WorkingDirectory</key>
  <string>/Users/your-username/path/to/local/clone/jira-omnifocus/bin</string>
```

**`ProgramArguments`**
Replace the value of the second `<string>` argument with the path to your local clone of the project's `jiraomnifocus.rb` file.

```
<key>ProgramArguments</key>
  <array>
    <string>/usr/bin/ruby</string>
    <string>/Users/your-username/path/to/local/clone/jira-omnifocus/bin/jiraomnifocus.rb</string>
  </array>
```

Please note that if you had to install a newer version of ruby, such as 2.1.2 in the above section about SSL Connection errors, when launchd runs the script it will not respect your user rbenv settings.  So I edited the ProgramArguments above and changed the path for ruby to:

```
/Users/your-username/.rbenv/shims/ruby
```

Which forced the scheduled launchd script to use the ruby 2.1.2 version.


**`StartInterval`**
Replace the integer value to change the time in seconds that controls how often the script will run.

```
<key>StartInterval</key>
  <integer>300</integer>
```




Then run:

```
launchctl load ~/Library/LaunchAgents/jofsync.plist
```

To set it to run automatically.

#### Running automatically with `cron`
You can use crontab -e to edit your user crontab and create an entry like this:

```
*/10 * * * * cd ~/dev/git/jira-omnifocus/bin && ./jiraomnifocus.rb
```

That should be it!  If it doesn't work, try adding some puts debug statements and running it manually.  
I can't offer any support, as I don't know Ruby that well and just magically cobbled this together:)

UPDATE:

I have manually merged in some features from https://github.com/cgarrigues/jira-omnifocus as per discussion on https://github.com/devondragon/jira-omnifocus/pull/15   
