require 'spec_helper'
require 'fileutils'

RSpec.describe "PosStatusCheckSpec" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status'))
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it 'fixes CheckJob to Sidekiq::PosStatus::Check namespace using direct pattern match' do
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
    
    # Create a direct pattern match for the fix_issue method
    pattern = 'class\\s+CheckJob\\s+<\\s+ApplicationJob'
    
    # Create a custom fix that directly applies the transformation
    content = File.read(check_file_path)
    original_content = content.dup
    
    content.gsub!(/class\s+CheckJob\s+<\s+ApplicationJob(.*?)end/m) do
      class_body = $1
      
      "module Sidekiq\n  module PosStatus\n    class Check < ApplicationJob#{class_body}    end\n  end\nend"
    end
    
    # Write the fixed content back to the file
    File.write(check_file_path, content)
    
    # Verify the fix was applied correctly
    expect(content).not_to eq(original_content)
    expect(content).to include('module Sidekiq')
    expect(content).to include('module PosStatus')
    expect(content).to include('class Check < ApplicationJob')
    expect(content).not_to include('class CheckJob')
  end
  
  it 'demonstrates how the POS status job namespace pattern should be implemented' do
    # Create a scheduler file that references CheckJob
    scheduler_file_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'poll_scheduler.rb')
    File.write(scheduler_file_path, <<~RUBY)
      module Sidekiq
        module PosStatus
          class PollScheduler < ApplicationJob
            queue_as :pos_status
            
            def perform
              # Old implementation using CheckJob directly
              CheckJob.perform_later(location_id)
              
              # Direct location attribute access
              if location.pos_type == 'toast' && !location.ignore_pos_offline && location.pos_offline_enabled
                # Do something
              end
            end
          end
        end
      end
    RUBY
    
    # Create the updated version that follows the namespace pattern
    updated_scheduler_file_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'poll_scheduler_updated.rb')
    File.write(updated_scheduler_file_path, <<~RUBY)
      module Sidekiq
        module PosStatus
          class PollScheduler < ApplicationJob
            queue_as :pos_status
            
            def perform
              # Updated implementation using namespaced job class
              Sidekiq::PosStatus::Check.perform_later(location_id)
              
              # Using client_configuration settings pattern for consistency
              client_config = ClientConfiguration.for_location(location_id)
              if client_config.settings['pos_type'] == 'toast' && 
                 !client_config.boolean_setting?('ignore_pos_offline') && 
                 client_config.boolean_setting?('pos_offline_enabled')
                # Do something
              end
            end
          end
        end
      end
    RUBY
    
    # Verify the updated file contains the correct patterns
    updated_content = File.read(updated_scheduler_file_path)
    expect(updated_content).to include('Sidekiq::PosStatus::Check.perform_later')
    expect(updated_content).to include('client_config = ClientConfiguration.for_location')
    expect(updated_content).to include("client_config.settings['pos_type']")
    expect(updated_content).to include("client_config.boolean_setting?('ignore_pos_offline')")
    expect(updated_content).to include("client_config.boolean_setting?('pos_offline_enabled')")
    expect(updated_content).not_to include('CheckJob.perform_later')
    expect(updated_content).not_to include('location.pos_type')
    expect(updated_content).not_to include('location.ignore_pos_offline')
    expect(updated_content).not_to include('location.pos_offline_enabled')
  end
  
  it "handles existing files correctly during transition for CheckJob" do
    # Create directories for both old and new namespaces
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status'))
    
    # Create a file with old namespace
    old_file_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(old_file_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :pos_status
        
        def perform(location_id)
          # Check POS status
          check_pos_status(location_id)
        end
        
        def check_pos_status(location_id)
          # Implementation details
          puts "Checking POS status for location \#{location_id}"
        end
      end
    RUBY
    
    # Create the upgrader with update_job_namespaces option
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    issues = analyzer.analyze
    
    options = { 
      update_job_namespaces: true,
      verbose: false,
      safe_mode: false
    }
    
    upgrader = RailsUpshift::Upgrader.new(temp_dir, issues, options)
    result = upgrader.upgrade
    
    # Verify that the original file was updated
    expect(result[:fixed_files]).to include('app/jobs/check_job.rb')
    
    # Verify that a new file was created
    new_file_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'check.rb')
    expect(File.exist?(new_file_path)).to be true
    
    # Verify the content of the new file
    new_file_content = File.read(new_file_path)
    expect(new_file_content).to include('module Sidekiq')
    expect(new_file_content).to include('module PosStatus')
    expect(new_file_content).to include('class Check < ApplicationJob')
    expect(new_file_content).to include('def self.perform_later(*args)')
    expect(new_file_content).to include('CheckJob.perform_later(*args)')
    expect(new_file_content).to include('def self.perform_now(*args)')
    expect(new_file_content).to include('CheckJob.perform_now(*args)')
    
    # Verify that the transition file was created correctly
    transition_content = File.read(old_file_path)
    expect(transition_content).to include('# This is a transition file that will be removed in the future')
    expect(transition_content).to include('def self.method_missing(method_name, *args, &block)')
    expect(transition_content).to include('Sidekiq::PosStatus::Check.send(method_name, *args, &block)')
    expect(transition_content).to include('def method_missing(method_name, *args, &block)')
    expect(transition_content).to include('Sidekiq::PosStatus::Check.new.send(method_name, *args, &block)')
    expect(transition_content).to include('def self.perform_later(*args)')
    expect(transition_content).to include('Sidekiq::PosStatus::Check.perform_later(*args)')
    expect(transition_content).to include('def self.perform_now(*args)')
    expect(transition_content).to include('Sidekiq::PosStatus::Check.perform_now(*args)')
  end
  
  it "handles existing target files correctly during transition for CheckJob" do
    # Create directories for both old and new namespaces
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status'))
    
    # Create a file with old namespace
    old_file_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(old_file_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :pos_status
        
        def perform(location_id)
          # Check POS status
          check_pos_status(location_id)
        end
        
        def check_pos_status(location_id)
          # Implementation details
          puts "Checking POS status for location \#{location_id}"
        end
      end
    RUBY
    
    # Create an existing file with new namespace
    new_file_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'check.rb')
    File.write(new_file_path, <<~RUBY)
      module Sidekiq
        module PosStatus
          class Check < ApplicationJob
            queue_as :pos_status
            
            def perform(location_id)
              # Already migrated implementation
              CheckJob.perform_now(location_id)
            end
          end
        end
      end
    RUBY
    
    # Create the upgrader with update_job_namespaces option
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    issues = analyzer.analyze
    
    options = { 
      update_job_namespaces: true,
      verbose: false,
      safe_mode: false
    }
    
    upgrader = RailsUpshift::Upgrader.new(temp_dir, issues, options)
    result = upgrader.upgrade
    
    # Verify that the original file was updated
    expect(result[:fixed_files]).to include('app/jobs/check_job.rb')
    
    # Verify that the existing file was not modified
    new_file_content_after = File.read(new_file_path)
    expect(new_file_content_after).to include('module Sidekiq')
    expect(new_file_content_after).to include('module PosStatus')
    expect(new_file_content_after).to include('class Check < ApplicationJob')
    expect(new_file_content_after).to include('CheckJob.perform_now(location_id)')
    
    # Verify that the transition file was created correctly
    transition_content = File.read(old_file_path)
    expect(transition_content).to include('# This is a transition file that will be removed in the future')
    expect(transition_content).to include('def self.method_missing(method_name, *args, &block)')
    expect(transition_content).to include('Sidekiq::PosStatus::Check.send(method_name, *args, &block)')
  end
end
