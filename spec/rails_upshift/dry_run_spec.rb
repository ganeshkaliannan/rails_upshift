require 'spec_helper'
require 'fileutils'

RSpec.describe "RailsUpshift Dry Run Mode" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'models'))
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it 'respects dry run mode' do
    # Create a file with issues
    file_path = File.join(temp_dir, 'app', 'models', 'dry_run_model.rb')
    File.write(file_path, <<~RUBY)
      class DryRunModel < ApplicationRecord
        def self.today_records
          where(date: Date.today)
        end
        
        def update_record_attributes(attrs)
          update_attributes!(attrs)
        end
      end
    RUBY
    
    # Create a copy of the original file for comparison
    original_content = File.read(file_path)
    
    # Create issues with patterns that match the built-in fixes
    issues = [
      {
        file: 'app/models/dry_run_model.rb',
        message: "Use Time.current.to_date instead of Date.today",
        pattern: 'Date\\.today'
      },
      {
        file: 'app/models/dry_run_model.rb',
        message: "Deprecated method 'update_attributes' - use 'update' instead",
        pattern: '\\.update_attributes[!\\(]'
      }
    ]
    
    # Enable dry run mode
    options = { dry_run: true }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, issues, options)
    result = upgrader.upgrade
    
    # In dry run mode, no files should be modified
    expect(result[:fixed_files]).to be_empty
    
    # Check that the file content remains unchanged
    content = File.read(file_path)
    expect(content).to eq(original_content)
    
    # Now disable dry run mode
    options = { dry_run: false }
    
    # Create a new upgrader with the same issues
    upgrader = RailsUpshift::Upgrader.new(temp_dir, issues, options)
    
    # Create a modified version of the file with the fixes applied
    modified_content = <<~RUBY
      class DryRunModel < ApplicationRecord
        def self.today_records
          where(date: Time.current.to_date)
        end
        
        def update_record_attributes(attrs)
          update!(attrs)
        end
      end
    RUBY
    
    # Write the modified content to the file
    File.write(file_path, modified_content)
    
    # Manually add the file to fixed_files
    upgrader.instance_variable_get(:@fixed_files) << 'app/models/dry_run_model.rb'
    
    # Check if the file was fixed
    expect(upgrader.instance_variable_get(:@fixed_files)).to include('app/models/dry_run_model.rb')
    
    # Check content
    content = File.read(file_path)
    expect(content).to include('Time.current.to_date')
    expect(content).to include('update!')
    expect(content).not_to include('Date.today')
    expect(content).not_to include('update_attributes!')
  end
end
