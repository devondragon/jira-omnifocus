# frozen_string_literal: true

RSpec.describe JiraOmnifocus::Configuration do
  describe '#initialize' do
    it 'creates configuration with default values' do
      config = described_class.new(build(:configuration, :default))
      
      expect(config.hostname).to eq('https://test.atlassian.net')
      expect(config.username).to eq('testuser')
      expect(config.ssl_verify).to be true
      expect(config.debug?).to be false
      expect(config.quiet?).to be true
    end
    
    it 'validates required fields' do
      expect { described_class.new(hostname: 'http://please-configure-me.atlassian.net') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       /Please configure your JIRA hostname/)
    end
    
    it 'requires username when not using keychain' do
      expect { 
        described_class.new(
          hostname: 'https://test.atlassian.net',
          username: '',
          usekeychain: false
        )
      }.to raise_error(JiraOmnifocus::Validation::ValidationError,
                      /Username is required/)
    end
    
    it 'requires password when not using keychain' do
      expect { 
        described_class.new(
          hostname: 'https://test.atlassian.net',
          username: 'testuser',
          password: '',
          usekeychain: false
        )
      }.to raise_error(JiraOmnifocus::Validation::ValidationError,
                      /Password is required/)
    end
    
    it 'allows empty credentials with keychain' do
      # We'll mock keychain loading to avoid actual keychain interaction
      allow_any_instance_of(described_class).to receive(:load_keychain_credentials)
      
      config = described_class.new(
        hostname: 'https://test.atlassian.net',
        username: '',
        password: '',
        usekeychain: true
      )
      
      expect(config.use_keychain?).to be true
    end
    
    it 'sanitizes JQL filter' do
      config = described_class.new(
        hostname: 'https://test.atlassian.net',
        username: 'testuser',
        password: 'testpass',
        filter: 'project = TEST; DROP TABLE--'
      )
      
      expect(config.filter).not_to include(';')
    end
    
    it 'validates project names' do
      expect { 
        described_class.new(
          hostname: 'https://test.atlassian.net',
          username: 'testuser',
          password: 'testpass',
          project: 'A' * 256  # Too long
        )
      }.to raise_error(JiraOmnifocus::Validation::ValidationError,
                      /Project name too long/)
    end
    
    it 'handles nil optional values gracefully' do
      config = described_class.new(
        hostname: 'https://test.atlassian.net',
        username: 'testuser',
        password: 'testpass',
        project: nil,
        tag: nil,
        folder: nil
      )
      
      expect(config.project).to be_nil
      expect(config.tag).to be_nil
      expect(config.folder).to be_nil
    end
  end
  
  describe '.load_from_file' do
    let(:config_file_path) { '/tmp/test_jofsync.yaml' }
    let(:sample_config) do
      {
        'jira' => {
          'hostname' => 'https://test.atlassian.net',
          'username' => 'testuser',
          'password' => 'testpass123',
          'filter' => 'assignee = currentUser()',
          'ssl_verify' => true
        },
        'omnifocus' => {
          'project' => 'JIRA Tasks',
          'tag' => 'Work',
          'flag' => true
        }
      }
    end
    
    before do
      File.write(config_file_path, sample_config.to_yaml)
    end
    
    after do
      File.delete(config_file_path) if File.exist?(config_file_path)
    end
    
    it 'loads configuration from YAML file' do
      config = described_class.load_from_file(config_file_path)
      
      expect(config.hostname).to eq('https://test.atlassian.net')
      expect(config.username).to eq('testuser')
      expect(config.project).to eq('JIRA Tasks')
      expect(config.tag).to eq('Work')
      expect(config.flag).to be true
    end
    
    it 'returns default configuration when file does not exist' do
      expect { described_class.load_from_file('/nonexistent/path') }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       /Please configure your JIRA hostname/)
    end
    
    it 'handles YAML parsing errors gracefully' do
      File.write(config_file_path, "invalid: yaml: content: [")
      
      expect { described_class.load_from_file(config_file_path) }
        .to raise_error(JiraOmnifocus::Validation::ValidationError,
                       /Please configure your JIRA hostname/)
    end
  end
  
  describe '#to_s' do
    it 'redacts password in string representation' do
      config = described_class.new(build(:configuration, :default))
      
      config_string = config.to_s
      expect(config_string).to include('[REDACTED]')
      expect(config_string).not_to include('testpass123')
    end
    
    it 'includes other configuration values' do
      config = described_class.new(build(:configuration, :default))
      
      config_string = config.to_s
      expect(config_string).to include('https://test.atlassian.net')
      expect(config_string).to include('testuser')
      expect(config_string).to include('Test Project')
    end
  end
  
  describe '#use_keychain?' do
    it 'returns true when keychain is enabled' do
      allow_any_instance_of(described_class).to receive(:load_keychain_credentials)
      config = described_class.new(build(:configuration, :default, :with_keychain))
      expect(config.use_keychain?).to be true
    end
    
    it 'returns false when keychain is disabled' do
      config = described_class.new(build(:configuration, :default))
      expect(config.use_keychain?).to be false
    end
  end
  
  describe '#debug?' do
    it 'returns true in debug mode' do
      config = described_class.new(build(:configuration, :default, :debug_mode))
      expect(config.debug?).to be true
    end
    
    it 'returns false in normal mode' do
      config = described_class.new(build(:configuration, :default))
      expect(config.debug?).to be false
    end
  end
end