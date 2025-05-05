require 'spec_helper'
require 'fileutils'

RSpec.describe "CheckJobTest" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs'))
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it 'fixes CheckJob to Sidekiq::PosStatus::Check namespace' do
    # Create a check job file
    check_file_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_file_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :pos_status
        
        def perform(location_id)
          # Check POS status
        end
      end
    RUBY
    
    # Create an issue that matches the pattern in the fix_issue method
    issues = [
      {
        file: 'app/jobs/check_job.rb',
        message: "Consider using Sidekiq::PosStatus::Check namespace instead of CheckJob",
        pattern: 'class\\s+CheckJob\\s+<\\s+ApplicationJob'
      }
    ]
    
    # Enable update_job_namespaces option
    options = { update_job_namespaces: true }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, issues, options)
    
    # Print debug information
    puts "Issues: #{issues.inspect}"
    puts "Options: #{options.inspect}"
    puts "File content before upgrade:"
    puts File.read(check_file_path)
    
    # Run upgrade
    result = upgrader.upgrade
    
    # Print more debug information
    puts "Result: #{result.inspect}"
    puts "File content after upgrade:"
    puts File.read(check_file_path)
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('app/jobs/check_job.rb')
    
    # Check content
    check_content = File.read(check_file_path)
    expect(check_content).to include('module Sidekiq')
    expect(check_content).to include('module PosStatus')
    expect(check_content).to include('class Check < ApplicationJob')
    expect(check_content).not_to include('class CheckJob')
  end
end
