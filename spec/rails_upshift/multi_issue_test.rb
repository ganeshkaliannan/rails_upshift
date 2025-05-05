require 'spec_helper'
require 'fileutils'

RSpec.describe "MultiIssueTest" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'models'))
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it 'fixes multiple issues in the same file' do
    # Create a file with multiple issues
    file_path = File.join(temp_dir, 'app', 'models', 'multi_issue.rb')
    File.write(file_path, <<~RUBY)
      class MultiIssue < ApplicationRecord
        def self.today_records
          where(date: Date.today)
        end
        
        def update_record_attributes(attrs)
          update_attributes(attrs)
        end
        
        def current_timestamp
          Time.now
        end
      end
    RUBY
    
    # Create issues array
    issues = [
      {
        file: 'app/models/multi_issue.rb',
        message: "Use Time.current.to_date instead of Date.today",
        pattern: 'Date\.today'
      },
      {
        file: 'app/models/multi_issue.rb',
        message: "Deprecated method 'update_attributes' - use 'update' instead",
        pattern: '\.update_attributes(\(|\!)'
      },
      {
        file: 'app/models/multi_issue.rb',
        message: "Use Time.current instead of Time.now",
        pattern: 'Time\.now'
      }
    ]
    
    # Create options hash
    options = { dry_run: false, safe_mode: false }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, issues, options)
    result = upgrader.upgrade
    
    # Print debug information
    puts "Result: #{result.inspect}"
    puts "Fixed files: #{result[:fixed_files].inspect}"
    puts "File content after upgrade:"
    puts File.read(file_path)
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('app/models/multi_issue.rb')
    
    content = File.read(file_path)
    expect(content).to include('Time.current.to_date')
    expect(content).to include('update(attrs)')
    expect(content).to include('Time.current')
    expect(content).not_to include('Date.today')
    expect(content).not_to include('update_attributes')
    expect(content).not_to include('Time.now')
  end
end
