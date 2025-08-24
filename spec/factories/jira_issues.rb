# frozen_string_literal: true

FactoryBot.define do
  factory :jira_issue, class: 'Hash' do
    skip_create
    
    sequence(:key) { |n| "TEST-#{n}" }
    
    fields do
      {
        'summary' => Faker::Lorem.sentence(word_count: 5),
        'description' => Faker::Lorem.paragraph(sentence_count: 3),
        'resolution' => nil,
        'assignee' => {
          'name' => 'testuser',
          'displayName' => 'Test User'
        },
        'duedate' => nil
      }
    end
    
    trait :resolved do
      fields do
        attributes_for(:jira_issue)[:fields].merge(
          'resolution' => {
            'name' => 'Done',
            'description' => 'Work has been completed on this issue.'
          }
        )
      end
    end
    
    trait :unassigned do
      fields do
        attributes_for(:jira_issue)[:fields].merge('assignee' => nil)
      end
    end
    
    trait :assigned_to_other do
      fields do
        attributes_for(:jira_issue)[:fields].merge(
          'assignee' => {
            'name' => 'otheruser',
            'displayName' => 'Other User'
          }
        )
      end
    end
    
    trait :with_due_date do
      fields do
        attributes_for(:jira_issue)[:fields].merge(
          'duedate' => (Date.today + rand(1..30)).strftime('%Y-%m-%d')
        )
      end
    end
    
    trait :unresolved do
      fields do
        {
          'summary' => Faker::Lorem.sentence(word_count: 5),
          'description' => 'Test description content',
          'status' => { 'name' => 'Open' },
          'resolution' => nil,
          'assignee' => { 'name' => 'testuser' },
          'priority' => { 'name' => 'Medium' }
        }
      end
    end
    
    trait :high_priority do
      fields do
        attributes_for(:jira_issue)[:fields].merge(
          'priority' => {
            'name' => 'High',
            'iconUrl' => 'https://test.atlassian.net/images/icons/priorities/high.svg'
          }
        )
      end
    end
    
    initialize_with { attributes }
  end
  
  factory :jira_search_response, class: 'Hash' do
    skip_create
    
    transient do
      issue_count { 3 }
      issues_traits { [] }
    end
    
    issues do
      Array.new(issue_count) do |i|
        build(:jira_issue, *issues_traits, key: "TEST-#{i + 1}")
      end
    end
    
    total { issues.size }
    startAt { 0 }
    maxResults { 50 }
    
    initialize_with { attributes }
  end
end