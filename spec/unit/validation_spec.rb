# frozen_string_literal: true

RSpec.describe JiraOmnifocus::Validation do
  describe '.validate_hostname!' do
    it 'accepts valid HTTP URLs' do
      valid_hostnames = [
        'http://example.com',
        'https://test.atlassian.net',
        'http://localhost:3000',
        'https://my-company.atlassian.net',
        'http://192.168.1.100:8080'
      ]
      
      valid_hostnames.each do |hostname|
        expect(described_class.validate_hostname!(hostname)).to eq(hostname)
      end
    end
    
    it 'rejects invalid hostname formats' do
      invalid_hostnames = [
        'not-a-url',
        'ftp://example.com',
        'example.com',
        'http://',
        'https://example.com/',
        ''
      ]
      
      invalid_hostnames.each do |hostname|
        expect { described_class.validate_hostname!(hostname) }
          .to raise_error(JiraOmnifocus::Validation::ValidationError)
      end
    end
    
    it 'strips whitespace' do
      expect(described_class.validate_hostname!('  http://example.com  '))
        .to eq('http://example.com')
    end
    
    it 'rejects hostnames ending with slash' do
      expect { described_class.validate_hostname!('http://example.com/') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError, 
                       'Hostname cannot end with \'/\'')
    end
    
    it 'raises error for empty hostname' do
      expect { described_class.validate_hostname!('') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       'Hostname cannot be empty')
    end
  end
  
  describe '.validate_username!' do
    it 'accepts valid usernames' do
      valid_usernames = [
        'testuser',
        'test.user',
        'test-user',
        'user@company.com',
        'user123'
      ]
      
      valid_usernames.each do |username|
        expect(described_class.validate_username!(username)).to eq(username)
      end
    end
    
    it 'rejects invalid username formats' do
      invalid_usernames = [
        'user with spaces',
        'user/with/slashes',
        'user;with;semicolons',
        'user"with"quotes',
        ''
      ]
      
      invalid_usernames.each do |username|
        expect { described_class.validate_username!(username) }
          .to raise_error(JiraOmnifocus::Validation::ValidationError)
      end
    end
    
    it 'strips whitespace' do
      expect(described_class.validate_username!('  testuser  '))
        .to eq('testuser')
    end
    
    it 'raises error for empty username' do
      expect { described_class.validate_username!('') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       'Username cannot be empty')
    end
  end
  
  describe '.sanitize_jql' do
    it 'removes dangerous characters' do
      dangerous_jql = 'project = TEST; DROP TABLE issues--'
      sanitized = described_class.sanitize_jql(dangerous_jql)
      
      expect(sanitized).to eq('project = TEST DROP TABLE issues--')
      expect(sanitized).not_to include(';')
    end
    
    it 'removes quotes and escape characters' do
      jql_with_quotes = 'summary ~ "test\'s issue\\" AND status = "Open"'
      sanitized = described_class.sanitize_jql(jql_with_quotes)
      
      expect(sanitized).not_to include('"')
      expect(sanitized).not_to include("'")
      expect(sanitized).not_to include('\\')
    end
    
    it 'removes newlines and carriage returns' do
      multiline_jql = "project = TEST\nAND status = Open\r\nAND assignee = currentUser()"
      sanitized = described_class.sanitize_jql(multiline_jql)
      
      expect(sanitized).not_to include("\n")
      expect(sanitized).not_to include("\r")
    end
    
    it 'handles nil and empty input' do
      expect(described_class.sanitize_jql(nil)).to eq('')
      expect(described_class.sanitize_jql('')).to eq('')
    end
  end
  
  describe '.validate_project_name!' do
    it 'accepts valid project names' do
      valid_names = [
        'Test Project',
        'My-Project_123',
        'Short',
        'A' * 255
      ]
      
      valid_names.each do |name|
        expect(described_class.validate_project_name!(name)).to eq(name)
      end
    end
    
    it 'rejects empty project names' do
      expect { described_class.validate_project_name!('') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       'Project name cannot be empty')
    end
    
    it 'rejects project names that are too long' do
      long_name = 'A' * 256
      expect { described_class.validate_project_name!(long_name) }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       'Project name too long')
    end
    
    it 'strips whitespace' do
      expect(described_class.validate_project_name!('  Test Project  '))
        .to eq('Test Project')
    end
  end
  
  describe '.validate_tag_name!' do
    it 'accepts valid tag names' do
      valid_names = [
        'Work',
        'High Priority',
        'tag-123',
        'A' * 255
      ]
      
      valid_names.each do |name|
        expect(described_class.validate_tag_name!(name)).to eq(name)
      end
    end
    
    it 'rejects empty tag names' do
      expect { described_class.validate_tag_name!('') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       'Tag name cannot be empty')
    end
    
    it 'rejects tag names that are too long' do
      long_name = 'A' * 256
      expect { described_class.validate_tag_name!(long_name) }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       'Tag name too long')
    end
  end
end