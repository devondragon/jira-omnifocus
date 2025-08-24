# frozen_string_literal: true

RSpec.describe JiraOmnifocus::Logger do
  let(:output) { StringIO.new }
  
  before do
    allow($stdout).to receive(:puts) do |message|
      output.puts(message)
    end
  end
  
  describe '#initialize' do
    it 'defaults to info level' do
      logger = described_class.new
      expect(logger.instance_variable_get(:@level)).to eq(1) # info level
    end
    
    it 'accepts custom log level' do
      logger = described_class.new(level: :debug)
      expect(logger.instance_variable_get(:@level)).to eq(0) # debug level
    end
    
    it 'accepts quiet mode' do
      logger = described_class.new(quiet: true)
      expect(logger.instance_variable_get(:@quiet)).to be true
    end
  end
  
  describe '#debug' do
    context 'with debug level' do
      let(:logger) { described_class.new(level: :debug) }
      
      it 'logs debug messages' do
        logger.debug('Debug message')
        expect(output.string).to include('DEBUG: Debug message')
      end
      
      it 'includes timestamp' do
        Timecop.freeze(Time.parse('2024-01-01 12:00:00')) do
          logger.debug('Test message')
          expect(output.string).to include('[2024-01-01 12:00:00]')
        end
      end
    end
    
    context 'with info level' do
      let(:logger) { described_class.new(level: :info) }
      
      it 'does not log debug messages' do
        logger.debug('Debug message')
        expect(output.string).to be_empty
      end
    end
  end
  
  describe '#info' do
    let(:logger) { described_class.new(level: :info) }
    
    it 'logs info messages' do
      logger.info('Info message')
      expect(output.string).to include(' INFO: Info message')
    end
    
    context 'in quiet mode' do
      let(:logger) { described_class.new(level: :info, quiet: true) }
      
      it 'does not log info messages' do
        logger.info('Info message')
        expect(output.string).to be_empty
      end
    end
  end
  
  describe '#warn' do
    let(:logger) { described_class.new(level: :warn) }
    
    it 'logs warning messages' do
      logger.warn('Warning message')
      expect(output.string).to include(' WARN: Warning message')
    end
    
    context 'in quiet mode' do
      let(:logger) { described_class.new(level: :warn, quiet: true) }
      
      it 'does not log warning messages' do
        logger.warn('Warning message')
        expect(output.string).to be_empty
      end
    end
  end
  
  describe '#error' do
    let(:logger) { described_class.new(level: :error) }
    
    it 'logs error messages' do
      logger.error('Error message')
      expect(output.string).to include('ERROR: Error message')
    end
    
    context 'in quiet mode' do
      let(:logger) { described_class.new(level: :error, quiet: true) }
      
      it 'still logs error messages' do
        logger.error('Error message')
        expect(output.string).to include('ERROR: Error message')
      end
    end
  end
  
  describe 'log level hierarchy' do
    let(:logger) { described_class.new(level: :warn) }
    
    it 'only logs messages at or above the configured level' do
      logger.debug('Debug message')
      logger.info('Info message')
      logger.warn('Warning message')
      logger.error('Error message')
      
      output_string = output.string
      expect(output_string).not_to include('Debug message')
      expect(output_string).not_to include('Info message')
      expect(output_string).to include('Warning message')
      expect(output_string).to include('Error message')
    end
  end
  
  describe 'message formatting' do
    let(:logger) { described_class.new(level: :info) }
    
    it 'formats messages consistently' do
      Timecop.freeze(Time.parse('2024-01-01 15:30:45')) do
        logger.info('Test message')
        
        expected_format = '[2024-01-01 15:30:45]  INFO: Test message'
        expect(output.string.strip).to eq(expected_format)
      end
    end
    
    it 'right-justifies log level labels' do
      logger.info('Info')
      logger.error('Error') 
      
      lines = output.string.split("\n").reject(&:empty?)
      expect(lines.first).to match(/\s+INFO:/)
      expect(lines.last).to match(/\sERROR:/)
    end
  end
end