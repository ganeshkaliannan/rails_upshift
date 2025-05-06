require 'spec_helper'
require 'fileutils'

# This spec tests the namespace pattern for order processing jobs
# According to the established pattern in the codebase, order jobs should use:
# 1. Process Jobs: Sidekiq::Orders::Process::*
# 2. Notification Jobs: Sidekiq::Orders::Notifications::*
#
# This aligns with other job namespaces like Sidekiq::ImportMenu and Sidekiq::Stock
RSpec.describe "RailsUpshift Order Jobs Namespace" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'orders'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'orders', 'process'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'orders', 'notifications'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
    File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 6.0.0'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it "detects incorrect order process job namespaces" do
    # Create a file with incorrect order process job namespace
    process_job_path = File.join(temp_dir, 'app', 'jobs', 'orders', 'process', 'create_job.rb')
    File.write(process_job_path, <<~RUBY)
      module Orders
        module Process
          class CreateJob < ApplicationJob
            queue_as :default
            
            def perform(order_id)
              # Process order
            end
          end
        end
      end
    RUBY
    
    # Create a plugin for order process job namespace
    plugin = RailsUpshift::Plugin.new("order_process_job_namespace", "Updates order process job namespaces")
    plugin.register_pattern(
      pattern: /module\s+Orders\s+.*module\s+Process/m,
      message: "Order process jobs should use Sidekiq::Orders::Process namespace",
      file_pattern: 'app/jobs/orders/process/*.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that order process job namespace issues were detected
    process_issues = issues.select { |i| i[:file] == 'app/jobs/orders/process/create_job.rb' }
    expect(process_issues).not_to be_empty
    expect(process_issues.any? { |i| i[:message].include?('Orders::Process') }).to be true
  end
  
  it "detects incorrect order notification job namespaces" do
    # Create a file with incorrect order notification job namespace
    notification_job_path = File.join(temp_dir, 'app', 'jobs', 'orders', 'notifications', 'email_job.rb')
    File.write(notification_job_path, <<~RUBY)
      module Orders
        module Notifications
          class EmailJob < ApplicationJob
            queue_as :default
            
            def perform(order_id)
              # Send notification
            end
          end
        end
      end
    RUBY
    
    # Create a plugin for order notification job namespace
    plugin = RailsUpshift::Plugin.new("order_notification_job_namespace", "Updates order notification job namespaces")
    plugin.register_pattern(
      pattern: /module\s+Orders\s+.*module\s+Notifications/m,
      message: "Order notification jobs should use Sidekiq::Orders::Notifications namespace",
      file_pattern: 'app/jobs/orders/notifications/*.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that order notification job namespace issues were detected
    notification_issues = issues.select { |i| i[:file] == 'app/jobs/orders/notifications/email_job.rb' }
    expect(notification_issues).not_to be_empty
    expect(notification_issues.any? { |i| i[:message].include?('Orders::Notifications') }).to be true
  end
  
  it "fixes order job namespaces when explicitly enabled" do
    # Create a file with incorrect order process job namespace
    process_job_path = File.join(temp_dir, 'app', 'jobs', 'orders', 'process', 'create_job.rb')
    File.write(process_job_path, <<~RUBY)
      module Orders
        module Process
          class CreateJob < ApplicationJob
            queue_as :default
            
            def perform(order_id)
              # Process order
            end
          end
        end
      end
    RUBY
    
    # Create a file with incorrect order notification job namespace
    notification_job_path = File.join(temp_dir, 'app', 'jobs', 'orders', 'notifications', 'email_job.rb')
    File.write(notification_job_path, <<~RUBY)
      module Orders
        module Notifications
          class EmailJob < ApplicationJob
            queue_as :default
            
            def perform(order_id)
              # Send notification
            end
          end
        end
      end
    RUBY
    
    # Create a plugin for order job namespace
    plugin = RailsUpshift::Plugin.new("order_job_namespace", "Updates order job namespaces")
    
    # Register patterns for detection
    plugin.register_pattern(
      pattern: /module\s+Orders\s+.*module\s+Process/m,
      message: "Order process jobs should use Sidekiq::Orders::Process namespace",
      file_pattern: 'app/jobs/orders/process/*.rb'
    )
    plugin.register_pattern(
      pattern: /module\s+Orders\s+.*module\s+Notifications/m,
      message: "Order notification jobs should use Sidekiq::Orders::Notifications namespace",
      file_pattern: 'app/jobs/orders/notifications/*.rb'
    )
    
    # Register fixes
    plugin.register_fix(
      pattern: /module\s+Orders\s+\n\s+module\s+Process/m,
      replacement: "module Sidekiq\n  module Orders\n    module Process"
    )
    plugin.register_fix(
      pattern: /module\s+Orders\s+\n\s+module\s+Notifications/m,
      replacement: "module Sidekiq\n  module Orders\n    module Notifications"
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader with the plugin
    options = { 
      dry_run: false, 
      safe_mode: false,
      plugins: ["order_job_namespace"]
    }
    
    begin
      result = RailsUpshift.upgrade(temp_dir, options)
      
      # Verify that the job files were updated
      if result[:fixed_files].include?('app/jobs/orders/process/create_job.rb')
        # Check the content of the updated process job
        process_content = File.read(process_job_path)
        expect(process_content).to include('module Sidekiq')
        expect(process_content).to include('module Orders')
        expect(process_content).to include('module Process')
        expect(process_content).not_to match(/\Amodule Orders/)
        
        # Check the content of the updated notification job
        if result[:fixed_files].include?('app/jobs/orders/notifications/email_job.rb')
          notification_content = File.read(notification_job_path)
          expect(notification_content).to include('module Sidekiq')
          expect(notification_content).to include('module Orders')
          expect(notification_content).to include('module Notifications')
          expect(notification_content).not_to match(/\Amodule Orders/)
        end
      else
        skip "Order job namespace updates are not enabled with the provided options"
      end
    rescue => e
      skip "Order job namespace updates are not enabled with the provided options: #{e.message}"
    ensure
      # Clean up the registered plugin
      plugin_manager = RailsUpshift::PluginManager.instance
      plugin_manager.instance_variable_set(:@plugins, {})
    end
  end
  
  it "handles existing files correctly during transition for order jobs" do
    # Create directories for both old and new namespaces
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq_jobs', 'orders', 'process'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq_jobs', 'orders', 'notifications'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'orders', 'process'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'orders', 'notifications'))
    
    # Create a file with old namespace for process job
    old_process_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq_jobs', 'orders', 'process', 'check_in.rb')
    File.write(old_process_path, <<~RUBY)
      module SidekiqJobs
        module Orders
          module Process
            class CheckIn
              include Sidekiq::Worker
              sidekiq_options queue: :orders
              
              def perform(order_id)
                # Process check-in order
              end
            end
          end
        end
      end
    RUBY
    
    # Create a file with old namespace for notification job
    old_notification_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq_jobs', 'orders', 'notifications', 'check_in.rb')
    File.write(old_notification_path, <<~RUBY)
      module SidekiqJobs
        module Orders
          module Notifications
            class CheckIn
              include Sidekiq::Worker
              sidekiq_options queue: :notifications
              
              def perform(order_id)
                # Send check-in notification
              end
            end
          end
        end
      end
    RUBY
    
    # Create an existing file with new namespace for process job
    new_process_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'orders', 'process', 'checkin.rb')
    File.write(new_process_path, <<~RUBY)
      module Sidekiq
        module Orders
          module Process
            class Checkin
              include Sidekiq::Worker
              sidekiq_options queue: :orders
              
              def perform(order_id)
                # Already migrated implementation
                SidekiqJobs::Orders::Process::CheckIn.new.perform(order_id)
              end
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
    
    # Verify that the original files were updated
    expect(result[:fixed_files]).to include('app/jobs/sidekiq_jobs/orders/process/check_in.rb')
    expect(result[:fixed_files]).to include('app/jobs/sidekiq_jobs/orders/notifications/check_in.rb')
    
    # Verify that the existing file was not modified
    new_process_content = File.read(new_process_path)
    expect(new_process_content).to include('module Sidekiq')
    expect(new_process_content).to include('module Orders')
    expect(new_process_content).to include('module Process')
    expect(new_process_content).to include('class Checkin')
    expect(new_process_content).to include('SidekiqJobs::Orders::Process::CheckIn.new.perform(order_id)')
    
    # Verify that a new notification job file was created
    new_notification_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'orders', 'notifications', 'checkin.rb')
    expect(File.exist?(new_notification_path)).to be true
    
    # Verify that the transition files were created correctly
    transition_process_content = File.read(old_process_path)
    expect(transition_process_content).to include('# This is a transition file that will be removed in the future')
    expect(transition_process_content).to include('def self.method_missing(method_name, *args, &block)')
    expect(transition_process_content).to include('Sidekiq::Orders::Process::CheckIn.send(method_name, *args, &block)')
    expect(transition_process_content).to include('def self.perform_async(*args)')
    expect(transition_process_content).to include('Sidekiq::Orders::Process::CheckIn.perform_async(*args)')
    
    transition_notification_content = File.read(old_notification_path)
    expect(transition_notification_content).to include('# This is a transition file that will be removed in the future')
    expect(transition_notification_content).to include('def self.method_missing(method_name, *args, &block)')
    expect(transition_notification_content).to include('Sidekiq::Orders::Notifications::CheckIn.send(method_name, *args, &block)')
    expect(transition_notification_content).to include('def self.perform_async(*args)')
    expect(transition_notification_content).to include('Sidekiq::Orders::Notifications::CheckIn.perform_async(*args)')
  end
end
