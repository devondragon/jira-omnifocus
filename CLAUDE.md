# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

jira-omnifocus is a Ruby script that syncs JIRA tickets with OmniFocus tasks. It:
- Creates OmniFocus tasks from JIRA tickets assigned to you
- Marks OmniFocus tasks complete when JIRA tickets are resolved
- Removes tasks when tickets are reassigned or unassigned

## Development Commands

### Setup and Dependencies
```bash
# Install bundler if not present
gem install bundler

# Install project dependencies
bundle install
```

### Running the Script
```bash
# Run manually
bundle exec bin/jiraomnifocus.rb

# Test with debug output
DEBUG=true bundle exec bin/jiraomnifocus.rb
```

### Configuration
The script requires a configuration file at `~/.jofsync.yaml`. Copy the sample:
```bash
cp jofsync.yaml.sample ~/.jofsync.yaml
```

## Architecture

### Core Components

**bin/jiraomnifocus.rb** - Main script (456 lines)
- Entry point and orchestration
- Key methods:
  - `get_issues` - Fetches JIRA tickets via REST API (lines 70-138)
  - `add_task` - Creates OmniFocus tasks (lines 141-246)
  - `add_jira_tickets_to_omnifocus` - Main sync logic (lines 249-301)
  - `mark_resolved_jira_tickets_as_complete_in_omnifocus` - Updates task status (lines 303-411)

### Data Flow
1. Script reads config from `~/.jofsync.yaml`
2. Fetches issues from JIRA REST API using JQL filter
3. Creates/updates OmniFocus tasks via AppleScript bridge (rb-scpt)
4. Marks completed tickets and removes reassigned ones

### Configuration Structure
- **jira**: Connection settings, credentials, JQL filter
- **omnifocus**: Task creation settings (project, tag, flags, inbox mode)

### Key Dependencies
- `rb-scpt` - AppleScript bridge for OmniFocus automation
- `ruby-keychain` - macOS keychain integration for credentials
- `terminal-notifier` - User notifications
- `optimist` - Command-line option parsing

### Authentication Options
1. Direct password in config
2. JIRA API token as password
3. macOS Keychain storage (recommended for automation)

### Task Creation Modes
- **Standard**: Tasks in specific project
- **Inbox**: Tasks go to OmniFocus inbox
- **Project**: Each JIRA ticket becomes a project

## Important Implementation Details

- Uses JIRA REST API v2 (`/rest/api/2/search` and `/rest/api/2/issue/`)
- Handles SSL verification (configurable)
- UTF-8 encoding for task names (line 170, 179, 188)
- Supports due dates from JIRA tickets
- Optional description sync to task notes
- Duplicate prevention by checking existing task names