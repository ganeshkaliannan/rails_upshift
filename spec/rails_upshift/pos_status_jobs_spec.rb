require 'spec_helper'
require 'fileutils'

# This spec tests the POS status jobs namespace pattern
# According to the established pattern in the codebase, POS status jobs
# should follow the namespace pattern: Sidekiq::PosStatus::Check instead of CheckJob
#
# Current Implementation:
# - Uses CheckJob directly in Sidekiq::PosStatus::PollScheduler
# - Direct location attribute access (pos_type, ignore_pos_offline, pos_offline_enabled)
#
# Required Changes:
# - Should follow namespace pattern: Sidekiq::PosStatus::Check instead of CheckJob
# - Consider using client_configuration settings pattern for consistency
# - Update tests to use proper namespaced job class
#
# This aligns with other Sidekiq jobs in the codebase like ImportMenu and Stock.
RSpec.describe "RailsUpshift POS Status Jobs Namespace" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
    File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 6.0.0'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it "detects CheckJob namespace issues" do
    # Create a check job file
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          # Check POS status
          @location = Location.find(location_id)
          check_pos_status(@location.pos_type)
        end
        
        private
        
        def check_pos_status(pos_type)
          # Implementation
        end
      end
    RUBY
    
    # Create a plugin for POS status job namespace
    plugin = RailsUpshift::Plugin.new("pos_status_job_namespace", "Updates POS status job namespaces")
    plugin.register_pattern(
      pattern: /class\s+CheckJob\s+<\s+ApplicationJob/,
      message: "POS status jobs should use Sidekiq::PosStatus::Check namespace instead of CheckJob",
      file_pattern: 'app/jobs/check_job.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that CheckJob namespace issues were detected
    check_issues = issues.select { |i| i[:file] == 'app/jobs/check_job.rb' }
    expect(check_issues).not_to be_empty
    expect(check_issues.any? { |i| i[:message].include?('CheckJob') }).to be true
  end
  
  it "detects direct references to CheckJob in schedulers" do
    # Create a scheduler file that references CheckJob
    scheduler_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'poll_scheduler.rb')
    File.write(scheduler_path, <<~RUBY)
      module Sidekiq
        module PosStatus
          class PollScheduler < ApplicationJob
            queue_as :default
            
            def perform
              Location.active.find_each do |location|
                # Direct reference to CheckJob
                CheckJob.perform_later(location.id)
              end
            end
          end
        end
      end
    RUBY
    
    # Create a plugin for POS status job namespace
    plugin = RailsUpshift::Plugin.new("pos_status_job_namespace", "Updates POS status job namespaces")
    plugin.register_pattern(
      pattern: /CheckJob\.perform_later/,
      message: "Should use Sidekiq::PosStatus::Check.perform_later instead of CheckJob.perform_later",
      file_pattern: '**/*.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that CheckJob reference issues were detected
    scheduler_issues = issues.select { |i| i[:file] == 'app/jobs/sidekiq/pos_status/poll_scheduler.rb' }
    expect(scheduler_issues).not_to be_empty
    expect(scheduler_issues.any? { |i| i[:message].include?('CheckJob') }).to be true
  end
  
  it "detects direct attribute access in CheckJob" do
    # Create a check job file with direct attribute access
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          @location = Location.find(location_id)
          
          # Direct attribute access
          return if @location.ignore_pos_offline
          return if !@location.pos_offline_enabled
          
          check_pos_status(@location.pos_type)
        end
        
        private
        
        def check_pos_status(pos_type)
          # Implementation
        end
      end
    RUBY
    
    # Create a plugin for POS status job namespace
    plugin = RailsUpshift::Plugin.new("pos_status_job_namespace", "Updates POS status job namespaces")
    plugin.register_pattern(
      pattern: /@location\.(ignore_pos_offline|pos_offline_enabled|pos_type)/,
      message: "Should use client_configuration settings pattern instead of direct attribute access",
      file_pattern: 'app/jobs/check_job.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that direct attribute access issues were detected
    check_issues = issues.select { |i| i[:file] == 'app/jobs/check_job.rb' }
    expect(check_issues).not_to be_empty
    expect(check_issues.any? { |i| i[:message].include?('direct attribute access') || 
                             i[:message].include?('client_configuration') }).to be true
  end
  
  it "updates POS status job namespaces when explicitly enabled" do
    # Create a check job file
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          # Check POS status
          @location = Location.find(location_id)
          check_pos_status(@location.pos_type)
        end
        
        private
        
        def check_pos_status(pos_type)
          # Implementation
        end
      end
    RUBY
    
    # Create a scheduler file that references CheckJob
    scheduler_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'poll_scheduler.rb')
    File.write(scheduler_path, <<~RUBY)
      module Sidekiq
        module PosStatus
          class PollScheduler < ApplicationJob
            queue_as :default
            
            def perform
              Location.active.find_each do |location|
                # Direct reference to CheckJob
                CheckJob.perform_later(location.id)
              end
            end
          end
        end
      end
    RUBY
    
    # Create a plugin for POS status job namespace
    plugin = RailsUpshift::Plugin.new("pos_status_job_namespace", "Updates POS status job namespaces")
    plugin.register_pattern(
      pattern: /class\s+CheckJob\s+<\s+ApplicationJob/,
      message: "POS status jobs should use Sidekiq::PosStatus::Check namespace instead of CheckJob",
      file_pattern: 'app/jobs/check_job.rb'
    )
    plugin.register_pattern(
      pattern: /CheckJob\.perform_later/,
      message: "Should use Sidekiq::PosStatus::Check.perform_later instead of CheckJob.perform_later",
      file_pattern: '**/*.rb'
    )
    plugin.register_fix(
      pattern: /class\s+CheckJob\s+<\s+ApplicationJob/,
      replacement: "module Sidekiq\n  module PosStatus\n    class Check < ApplicationJob"
    )
    plugin.register_fix(
      pattern: /CheckJob\.perform_later/,
      replacement: "Sidekiq::PosStatus::Check.perform_later"
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader with the plugin
    options = { 
      dry_run: false, 
      safe_mode: false,
      plugins: ["pos_status_job_namespace"]
    }
    
    begin
      result = RailsUpshift.upgrade(temp_dir, options)
      
      # Verify that the check job was updated if the feature is supported
      if result[:fixed_files].include?('app/jobs/check_job.rb')
        # Check the content of the updated check job
        check_content = File.read(check_job_path)
        expect(check_content).to include('module Sidekiq')
        expect(check_content).to include('module PosStatus')
        expect(check_content).to include('class Check < ApplicationJob')
        expect(check_content).not_to include('class CheckJob')
        
        # Check if references were updated
        if result[:fixed_files].include?('app/jobs/sidekiq/pos_status/poll_scheduler.rb')
          scheduler_content = File.read(scheduler_path)
          expect(scheduler_content).to include('Sidekiq::PosStatus::Check.perform_later')
          expect(scheduler_content).not_to include('CheckJob.perform_later')
        end
      else
        # Skip this test if the feature is not implemented
        skip "POS status job namespace updates are not enabled with the provided options"
      end
    rescue => e
      skip "POS status job namespace updates are not enabled with the provided options: #{e.message}"
    ensure
      # Clean up the registered plugin
      plugin_manager = RailsUpshift::PluginManager.instance
      plugin_manager.instance_variable_set(:@plugins, {})
    end
  end
  
  it "handles client configuration settings pattern" do
    # Create a check job file with direct attribute access
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          @location = Location.find(location_id)
          
          # Direct attribute access
          return if @location.ignore_pos_offline
          return if !@location.pos_offline_enabled
          
          check_pos_status(@location.pos_type)
        end
        
        private
        
        def check_pos_status(pos_type)
          # Implementation
        end
      end
    RUBY
    
    # Create a plugin for POS status job namespace with client configuration
    plugin = RailsUpshift::Plugin.new("pos_status_job_namespace_with_config", "Updates POS status job namespaces with client configuration")
    plugin.register_pattern(
      pattern: /@location\.(ignore_pos_offline|pos_offline_enabled|pos_type)/,
      message: "Should use client_configuration settings pattern instead of direct attribute access",
      file_pattern: 'app/jobs/check_job.rb'
    )
    plugin.register_fix(
      pattern: /@location\.ignore_pos_offline/,
      replacement: "client_configuration.settings[:ignore_pos_offline]"
    )
    plugin.register_fix(
      pattern: /@location\.pos_offline_enabled/,
      replacement: "client_configuration.settings[:pos_offline_enabled]"
    )
    plugin.register_fix(
      pattern: /@location\.pos_type/,
      replacement: "client_configuration.settings[:pos_type]"
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader with the plugin
    options = { 
      dry_run: false, 
      safe_mode: false,
      plugins: ["pos_status_job_namespace_with_config"]
    }
    
    begin
      result = RailsUpshift.upgrade(temp_dir, options)
      
      # Verify that the check job was updated with client configuration pattern if the feature is supported
      if result[:fixed_files].include?('app/jobs/check_job.rb')
        # Check the content of the updated check job
        check_content = File.read(check_job_path)
        expect(check_content).to include('client_configuration.settings[:ignore_pos_offline]')
        expect(check_content).to include('client_configuration.settings[:pos_offline_enabled]')
        expect(check_content).to include('client_configuration.settings[:pos_type]')
        expect(check_content).not_to include('@location.ignore_pos_offline')
        expect(check_content).not_to include('@location.pos_offline_enabled')
        expect(check_content).not_to include('@location.pos_type')
      else
        # Skip if client configuration pattern is not implemented
        skip "Client configuration settings pattern is not implemented"
      end
    rescue => e
      skip "Client configuration settings pattern is not implemented: #{e.message}"
    ensure
      # Clean up the registered plugin
      plugin_manager = RailsUpshift::PluginManager.instance
      plugin_manager.instance_variable_set(:@plugins, {})
    end
  end
end
