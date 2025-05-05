require 'spec_helper'
require 'fileutils'
require 'stringio'

RSpec.describe RailsUpshift::CLI do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  describe '#run' do
    it 'shows help when --help option is provided' do
      cli = described_class.new(['--help'])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        output = $stdout.string
        
        expect(exit_code).to eq(0)
        expect(output).to include('Usage: rails_upshift [options] [path]')
      ensure
        $stdout = original_stdout
      end
    end
    
    it 'shows version when --version option is provided' do
      cli = described_class.new(['--version'])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        output = $stdout.string
        
        expect(exit_code).to eq(0)
        expect(output).to include('RailsUpshift version')
      ensure
        $stdout = original_stdout
      end
    end
    
    it 'validates that the path is a directory' do
      non_existent_path = File.join(temp_dir, 'non_existent')
      cli = described_class.new([non_existent_path])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        output = $stdout.string
        
        expect(exit_code).to eq(1)
        expect(output).to include('is not a valid directory')
      ensure
        $stdout = original_stdout
      end
    end
    
    it 'validates that the path is a Rails application' do
      empty_dir = File.join(temp_dir, 'empty')
      FileUtils.mkdir_p(empty_dir)
      
      cli = described_class.new([empty_dir])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        output = $stdout.string
        
        expect(exit_code).to eq(1)
        expect(output).to include('does not appear to be a Rails application')
      ensure
        $stdout = original_stdout
      end
    end
    
    it 'runs analyze when --analyze option is provided' do
      # Mock the RailsUpshift.analyze method
      expect(RailsUpshift).to receive(:analyze).with(temp_dir).and_return([])
      
      cli = described_class.new(['--analyze', temp_dir])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        output = $stdout.string
        
        expect(exit_code).to eq(0)
        expect(output).to include('Analyzing Rails application')
      ensure
        $stdout = original_stdout
      end
    end
    
    it 'runs upgrade when no --analyze option is provided' do
      # Mock the RailsUpshift.upgrade method
      expect(RailsUpshift).to receive(:upgrade).with(temp_dir, hash_including({})).and_return({ issues: [], fixed_files: [] })
      
      cli = described_class.new([temp_dir])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        output = $stdout.string
        
        expect(exit_code).to eq(0)
        expect(output).to include('Upgrading Rails application')
      ensure
        $stdout = original_stdout
      end
    end
    
    it 'passes options to the upgrader' do
      # Mock the RailsUpshift.upgrade method and capture the options
      expect(RailsUpshift).to receive(:upgrade) do |path, options|
        expect(path).to eq(temp_dir)
        expect(options[:dry_run]).to be true
        expect(options[:update_gems]).to be true
        expect(options[:target_version]).to eq('6.1.0')
        { issues: [], fixed_files: [] }
      end
      
      cli = described_class.new(['--dry-run', '--update-gems', '--target', '6.1.0', temp_dir])
      
      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      begin
        exit_code = cli.run
        expect(exit_code).to eq(0)
      ensure
        $stdout = original_stdout
      end
    end
  end
  
  describe '#parse_options' do
    it 'parses analyze option' do
      cli = described_class.new(['--analyze'])
      expect(cli.options[:analyze_only]).to be true
    end
    
    it 'parses dry-run option' do
      cli = described_class.new(['--dry-run'])
      expect(cli.options[:dry_run]).to be true
    end
    
    it 'parses unsafe option' do
      cli = described_class.new(['--unsafe'])
      expect(cli.options[:safe_mode]).to be false
    end
    
    it 'parses verbose option' do
      cli = described_class.new(['--verbose'])
      expect(cli.options[:verbose]).to be true
    end
    
    it 'parses target version option' do
      cli = described_class.new(['--target', '6.1.0'])
      expect(cli.options[:target_version]).to eq('6.1.0')
    end
    
    it 'parses update-gems option' do
      cli = described_class.new(['--update-gems'])
      expect(cli.options[:update_gems]).to be true
    end
    
    it 'parses update-configs option' do
      cli = described_class.new(['--update-configs'])
      expect(cli.options[:update_configs]).to be true
    end
    
    it 'parses update-form-helpers option' do
      cli = described_class.new(['--update-form-helpers'])
      expect(cli.options[:update_form_helpers]).to be true
    end
    
    it 'parses update-job-namespaces option' do
      cli = described_class.new(['--update-job-namespaces'])
      expect(cli.options[:update_job_namespaces]).to be true
    end
    
    it 'parses help option' do
      cli = described_class.new(['--help'])
      expect(cli.options[:help]).to be true
    end
    
    it 'parses version option' do
      cli = described_class.new(['--version'])
      expect(cli.options[:version]).to be true
    end
    
    it 'parses path argument' do
      cli = described_class.new(['/path/to/app'])
      expect(cli.path).to eq('/path/to/app')
    end
    
    it 'defaults to current directory when no path is provided' do
      cli = described_class.new([])
      expect(cli.path).to eq(Dir.pwd)
    end
  end
end
