# frozen_string_literal: true

FactoryBot.define do
  factory :configuration, class: 'Hash' do
    skip_create
    
    trait :default do
      hostname { 'https://test.atlassian.net' }
      username { 'testuser' }
      password { 'testpass123' }
      filter { 'resolution = Unresolved and issue in watchedissues()' }
      ssl_verify { true }
      usekeychain { false }
      tag { 'Test' }
      project { 'Test Project' }
      flag { false }
      folder { 'Test Folder' }
      inbox { false }
      newproj { false }
      descsync { false }
      debug { false }
      quiet { true }
    end
    
    trait :with_keychain do
      usekeychain { true }
      username { nil }
      password { nil }
    end
    
    trait :for_inbox do
      inbox { true }
      project { nil }
    end
    
    trait :for_projects do
      newproj { true }
      folder { 'JIRA Projects' }
    end
    
    trait :with_description_sync do
      descsync { true }
    end
    
    trait :debug_mode do
      debug { true }
      quiet { false }
    end
    
    initialize_with { attributes }
  end
end