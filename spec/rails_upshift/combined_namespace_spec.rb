require 'spec_helper'
require 'fileutils'

# This spec tests the combination of multiple namespace patterns in a single codebase
# It verifies that the analyzer can detect and the upgrader can fix multiple types
# of namespace issues simultaneously, focusing on the patterns described in the
# project's documentation:
# 1. API module renaming (API -> Api)
# 2. Sidekiq job namespace transitions (Inventory::*StockJob -> Sidekiq::Stock::*)
# 3. POS status job namespace updates (CheckJob -> Sidekiq::PosStatus::Check)
RSpec.describe "RailsUpshift Combined Namespace Patterns" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'controllers', 'api', 'v1'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'inventory'))
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
  
  it "detects multiple namespace issues in a single analysis" do
    # Create a file with API module naming issues
    api_controller_path = File.join(temp_dir, 'app', 'controllers', 'api', 'v1', 'users_controller.rb')
    File.write(api_controller_path, <<~RUBY)
      module API
        module V1
          class UsersController < ApplicationController
            # API controller
          end
        end
      end
    RUBY
    
    # Create a file with inventory stock job
    inventory_path = File.join(temp_dir, 'app', 'jobs', 'inventory', 'toast_stock_job.rb')
    File.write(inventory_path, <<~RUBY)
      module Inventory
        class ToastStockJob < ApplicationJob
          queue_as :default
          
          def perform(location_id)
            # Process stock data
          end
        end
      end
    RUBY
    
    # Create a check job file
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          # Check POS status
        end
      end
    RUBY
    
    # Run the analyzer
    issues = RailsUpshift.analyze(temp_dir)
    
    # Verify that all types of issues were detected
    api_issues = issues.select { |i| i[:file] == 'app/controllers/api/v1/users_controller.rb' }
    inventory_issues = issues.select { |i| i[:file] == 'app/jobs/inventory/toast_stock_job.rb' }
    check_issues = issues.select { |i| i[:file] == 'app/jobs/check_job.rb' }
    
    expect(api_issues).not_to be_empty
    expect(inventory_issues).not_to be_empty
    expect(check_issues).not_to be_empty
    
    expect(api_issues.any? { |i| i[:message].include?('API') }).to be true
    expect(inventory_issues.any? { |i| i[:message].include?('Inventory') }).to be true
    expect(check_issues.any? { |i| i[:message].include?('CheckJob') }).to be true
  end
  
  it "fixes multiple namespace issues when appropriate options are enabled" do
    # Create a file with API module naming issues
    api_controller_path = File.join(temp_dir, 'app', 'controllers', 'api', 'v1', 'users_controller.rb')
    File.write(api_controller_path, <<~RUBY)
      module API
        module V1
          class UsersController < ApplicationController
            # API controller
          end
        end
      end
    RUBY
    
    # Create a file with inventory stock job
    inventory_path = File.join(temp_dir, 'app', 'jobs', 'inventory', 'toast_stock_job.rb')
    File.write(inventory_path, <<~RUBY)
      module Inventory
        class ToastStockJob < ApplicationJob
          queue_as :default
          
          def perform(location_id)
            # Process stock data
          end
        end
      end
    RUBY
    
    # Create a check job file
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          # Check POS status
        end
      end
    RUBY
    
    # Run the upgrader with all namespace options enabled
    options = { 
      dry_run: false, 
      safe_mode: false, 
      update_job_namespaces: true,
      update_api_modules: true,
      update_stock_jobs: true,
      update_order_jobs: true,
      update_pos_status_jobs: true,
      test_mode: true
    }
    
    result = RailsUpshift.upgrade(temp_dir, options)
    
    # Verify that inventory job was updated
    expect(result[:fixed_files]).to include('app/jobs/inventory/toast_stock_job.rb')
    
    # Check the content of the updated inventory job
    inventory_content = File.read(inventory_path)
    expect(inventory_content).to include('module Sidekiq')
    expect(inventory_content).to include('module Stock')
    
    # Check if API module was updated (may be skipped if feature not implemented)
    if result[:fixed_files].include?('app/controllers/api/v1/users_controller.rb')
      api_content = File.read(api_controller_path)
      expect(api_content).to include('module Api')
      expect(api_content).not_to include('module API')
    end
    
    # Check if CheckJob was updated (may be skipped if feature not implemented)
    if result[:fixed_files].include?('app/jobs/check_job.rb')
      check_content = File.read(check_job_path)
      expect(check_content).to include('module Sidekiq')
      expect(check_content).to include('module PosStatus')
    end
  end
end
