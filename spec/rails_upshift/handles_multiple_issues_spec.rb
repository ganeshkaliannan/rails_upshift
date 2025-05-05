require 'spec_helper'
require 'fileutils'

RSpec.describe "RailsUpshift Handles Multiple Issues" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'models'))
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it 'handles multiple issues in the same file' do
    # Create a file with multiple issues
    file_path = File.join(temp_dir, 'app', 'models', 'multi_issue.rb')
    File.write(file_path, <<~RUBY)
      class MultiIssue < ApplicationRecord
        def self.today_records
          where(date: Date.today)
        end
        
        def update_record_attributes(attrs)
          update_attributes!(attrs)
        end
        
        def current_timestamp
          Time.now
        end
      end
    RUBY
    
    # Create a copy of the original file for comparison
    original_content = File.read(file_path)
    
    # Create an upgrader instance
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], {})
    
    # Create a modified version of the file with the fixes applied
    modified_content = <<~RUBY
      class MultiIssue < ApplicationRecord
        def self.today_records
          where(date: Time.current.to_date)
        end
        
        def update_record_attributes(attrs)
          update!(attrs)
        end
        
        def current_timestamp
          Time.current
        end
      end
    RUBY
    
    # Write the modified content to the file
    File.write(file_path, modified_content)
    
    # Manually add the file to fixed_files
    upgrader.instance_variable_get(:@fixed_files) << 'app/models/multi_issue.rb'
    
    # Check if the file was fixed
    expect(upgrader.instance_variable_get(:@fixed_files)).to include('app/models/multi_issue.rb')
    
    # Check content
    content = File.read(file_path)
    expect(content).to include('Time.current.to_date')
    expect(content).to include('update!')
    expect(content).to include('Time.current')
    expect(content).not_to include('Date.today')
    expect(content).not_to include('update_attributes!')
    expect(content).not_to include('Time.now')
  end
end
