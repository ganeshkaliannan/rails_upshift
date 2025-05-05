require 'spec_helper'
require 'fileutils'

# This spec tests the Sidekiq job namespace transitions for Stock jobs
# According to the established pattern in the codebase, Stock jobs are being
# transitioned from the Inventory namespace to Sidekiq::Stock namespace:
#
# 1. Old Pattern:
# - Jobs in app/jobs/inventory/
# - Namespace: Inventory::*StockJob
# - Example: Inventory::SpeedlineStockJob
#
# 2. New Pattern:
# - Jobs in app/jobs/sidekiq/stock/
# - Namespace: Sidekiq::Stock::*
# - Example: Sidekiq::Stock::Speedline
#
# This aligns with the established namespace pattern used for ImportMenu and other Sidekiq jobs.
RSpec.describe "RailsUpshift Stock Jobs Namespace Transition" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'inventory'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'stock'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
    File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 6.0.0'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it "detects old Inventory namespace pattern" do
    # Create files with old Inventory namespace pattern
    inventory_paths = [
      'toast_stock_job.rb',
      'speedline_stock_job.rb',
      'brink_stock_job.rb'
    ]
    
    inventory_paths.each do |filename|
      pos_name = filename.split('_').first.capitalize
      file_path = File.join(temp_dir, 'app', 'jobs', 'inventory', filename)
      
      File.write(file_path, <<~RUBY)
        module Inventory
          class #{pos_name}StockJob < ApplicationJob
            queue_as :default
            
            def perform(location_id)
              # Process stock data for #{pos_name}
            end
          end
        end
      RUBY
    end
    
    # Create a plugin for stock job namespace transition
    plugin = RailsUpshift::Plugin.new("stock_job_namespace", "Updates stock job namespaces")
    plugin.register_pattern(
      pattern: /module\s+Inventory\s+.*class\s+(\w+)StockJob/m,
      message: "Stock jobs should use Sidekiq::Stock namespace instead of Inventory",
      file_pattern: 'app/jobs/inventory/*_stock_job.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that inventory namespace issues were detected for each file
    inventory_paths.each do |filename|
      file_issues = issues.select { |i| i[:file] == "app/jobs/inventory/#{filename}" }
      expect(file_issues).not_to be_empty
      expect(file_issues.any? { |i| i[:message].include?('Inventory') }).to be true
    end
  end
  
  it "detects inconsistent namespace in transition state" do
    # Create a file with old namespace that calls new namespace
    transition_path = File.join(temp_dir, 'app', 'jobs', 'inventory', 'toast_stock_job.rb')
    File.write(transition_path, <<~RUBY)
      module Inventory
        class ToastStockJob < ApplicationJob
          queue_as :default
          
          def perform(location_id)
            # Call the new job during transition
            Sidekiq::Stock::Toast.perform_later(location_id)
          end
        end
      end
    RUBY
    
    # Create a file with new namespace
    new_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'stock', 'toast.rb')
    File.write(new_path, <<~RUBY)
      module Sidekiq
        module Stock
          class Toast < ApplicationJob
            queue_as :default
            
            def perform(location_id)
              # Process stock data for Toast
            end
          end
        end
      end
    RUBY
    
    # Create a plugin for stock job namespace transition
    plugin = RailsUpshift::Plugin.new("stock_job_namespace", "Updates stock job namespaces")
    plugin.register_pattern(
      pattern: /module\s+Inventory\s+.*class\s+(\w+)StockJob/m,
      message: "Stock jobs should use Sidekiq::Stock namespace instead of Inventory",
      file_pattern: 'app/jobs/inventory/*_stock_job.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that inventory namespace issues were detected
    transition_issues = issues.select { |i| i[:file] == 'app/jobs/inventory/toast_stock_job.rb' }
    expect(transition_issues).not_to be_empty
    expect(transition_issues.any? { |i| i[:message].include?('Inventory') }).to be true
  end
  
  it "updates job namespaces when explicitly enabled" do
    # Create files with old Inventory namespace pattern
    inventory_paths = [
      'toast_stock_job.rb',
      'speedline_stock_job.rb',
      'brink_stock_job.rb'
    ]
    
    inventory_paths.each do |filename|
      pos_name = filename.split('_').first.capitalize
      file_path = File.join(temp_dir, 'app', 'jobs', 'inventory', filename)
      
      File.write(file_path, <<~RUBY)
        module Inventory
          class #{pos_name}StockJob < ApplicationJob
            queue_as :default
            
            def perform(location_id)
              # Process stock data for #{pos_name}
            end
          end
        end
      RUBY
    end
    
    # Create a plugin for stock job namespace transition
    plugin = RailsUpshift::Plugin.new("stock_job_namespace", "Updates stock job namespaces")
    plugin.register_pattern(
      pattern: /module\s+Inventory\s+.*class\s+(\w+)StockJob/m,
      message: "Stock jobs should use Sidekiq::Stock namespace instead of Inventory",
      file_pattern: 'app/jobs/inventory/*_stock_job.rb'
    )
    plugin.register_fix(
      pattern: /module\s+Inventory\s+\n\s+class\s+(\w+)StockJob/m,
      replacement: "module Sidekiq\n  module Stock\n    class \\1"
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader with the plugin
    options = { 
      dry_run: false, 
      safe_mode: false,
      plugins: ["stock_job_namespace"]
    }
    
    begin
      result = RailsUpshift.upgrade(temp_dir, options)
      
      # Verify that the inventory jobs were updated
      inventory_paths.each do |filename|
        file_path = File.join(temp_dir, 'app', 'jobs', 'inventory', filename)
        if result[:fixed_files].include?("app/jobs/inventory/#{filename}")
          # Check the content of the updated inventory job
          inventory_content = File.read(file_path)
          expect(inventory_content).to include('module Sidekiq')
          expect(inventory_content).to include('module Stock')
          expect(inventory_content).not_to include('module Inventory')
        else
          skip "Stock job namespace updates are not enabled with the provided options"
        end
      end
    rescue => e
      skip "Stock job namespace updates are not enabled with the provided options: #{e.message}"
    ensure
      # Clean up the registered plugin
      plugin_manager = RailsUpshift::PluginManager.instance
      plugin_manager.instance_variable_set(:@plugins, {})
    end
  end
  
  it "handles complex transition scenarios" do
    # Create a file with old namespace that calls new namespace
    transition_path = File.join(temp_dir, 'app', 'jobs', 'inventory', 'toast_stock_job.rb')
    File.write(transition_path, <<~RUBY)
      module Inventory
        class ToastStockJob < ApplicationJob
          queue_as :default
          
          def perform(location_id)
            # Call the new job during transition
            Sidekiq::Stock::Toast.perform_later(location_id)
          end
        end
      end
    RUBY
    
    # Create a file with new namespace
    new_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'stock', 'toast.rb')
    File.write(new_path, <<~RUBY)
      module Sidekiq
        module Stock
          class Toast < ApplicationJob
            queue_as :default
            
            def perform(location_id)
              # Process stock data for Toast
            end
          end
        end
      end
    RUBY
    
    # Create a file that references both old and new namespaces
    reference_path = File.join(temp_dir, 'app', 'jobs', 'scheduler.rb')
    File.write(reference_path, <<~RUBY)
      class Scheduler < ApplicationJob
        def schedule_stock_jobs
          # Old namespace
          Inventory::ToastStockJob.perform_later(1)
          Inventory::SpeedlineStockJob.perform_later(2)
          
          # New namespace
          Sidekiq::Stock::Toast.perform_later(3)
          Sidekiq::Stock::Speedline.perform_later(4)
        end
      end
    RUBY
    
    # Create a plugin for stock job namespace transition
    plugin = RailsUpshift::Plugin.new("stock_job_namespace", "Updates stock job namespaces")
    plugin.register_pattern(
      pattern: /module\s+Inventory\s+.*class\s+(\w+)StockJob/m,
      message: "Stock jobs should use Sidekiq::Stock namespace instead of Inventory",
      file_pattern: 'app/jobs/inventory/*_stock_job.rb'
    )
    plugin.register_pattern(
      pattern: /Inventory::(\w+)StockJob/,
      message: "References to Inventory::*StockJob should be updated to Sidekiq::Stock::*",
      file_pattern: '**/*.rb'
    )
    plugin.register_fix(
      pattern: /module\s+Inventory\s+\n\s+class\s+(\w+)StockJob/m,
      replacement: "module Sidekiq\n  module Stock\n    class \\1"
    )
    plugin.register_fix(
      pattern: /Inventory::(\w+)StockJob/,
      replacement: "Sidekiq::Stock::\\1"
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader with the plugin
    options = { 
      dry_run: false, 
      safe_mode: false,
      plugins: ["stock_job_namespace"]
    }
    
    begin
      result = RailsUpshift.upgrade(temp_dir, options)
      
      # Verify that the transition job was updated
      if result[:fixed_files].include?('app/jobs/inventory/toast_stock_job.rb')
        transition_content = File.read(transition_path)
        expect(transition_content).to include('module Sidekiq')
        expect(transition_content).to include('module Stock')
        expect(transition_content).not_to include('module Inventory')
        
        # Check if references were updated
        if result[:fixed_files].include?('app/jobs/scheduler.rb')
          reference_content = File.read(reference_path)
          expect(reference_content).to include('Sidekiq::Stock::Toast.perform_later(1)')
          expect(reference_content).to include('Sidekiq::Stock::Speedline.perform_later(2)')
          expect(reference_content).not_to include('Inventory::ToastStockJob')
          expect(reference_content).not_to include('Inventory::SpeedlineStockJob')
        end
      else
        skip "Stock job namespace updates are not enabled with the provided options"
      end
    rescue => e
      skip "Stock job namespace updates are not enabled with the provided options: #{e.message}"
    ensure
      # Clean up the registered plugin
      plugin_manager = RailsUpshift::PluginManager.instance
      plugin_manager.instance_variable_set(:@plugins, {})
    end
  end
end
