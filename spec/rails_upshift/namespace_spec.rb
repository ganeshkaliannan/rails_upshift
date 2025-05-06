require 'spec_helper'
require 'fileutils'

# This spec tests the namespace patterns that are important in the Rails Upshift project.
# It focuses on three key namespace patterns identified in the codebase:
#
# 1. API Module Renaming:
#    - The API module has been renamed to Api to match Rails' autoloading convention
#    - This affects all API-related files in the codebase
#    - The module name should consistently be 'Api' rather than 'API'
#
# 2. Sidekiq Job Namespaces:
#    - Import Menu Jobs use the Sidekiq::ImportMenu namespace
#    - Stock Jobs use the Sidekiq::Stock namespace
#    - There's a transition from Inventory::*StockJob to Sidekiq::Stock::*
#
# 3. POS Status Jobs:
#    - CheckJob should follow the namespace pattern: Sidekiq::PosStatus::Check
#    - This aligns with other Sidekiq jobs in the codebase
#
# These tests verify that Rails Upshift correctly detects and fixes these namespace issues.
RSpec.describe "RailsUpshift Namespace Patterns" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'controllers', 'api', 'v1'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'inventory'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
    File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 6.0.0'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it "detects API module naming issues" do
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
    
    # Run the analyzer
    issues = RailsUpshift.analyze(temp_dir)
    
    # Verify that API module issues were detected
    api_issues = issues.select { |i| i[:file] == 'app/controllers/api/v1/users_controller.rb' }
    expect(api_issues).not_to be_empty
    expect(api_issues.any? { |i| i[:message].include?('API') }).to be true
  end
  
  it "detects Inventory namespace issues" do
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
    
    # Run the analyzer
    issues = RailsUpshift.analyze(temp_dir)
    
    # Verify that inventory namespace issues were detected
    inventory_issues = issues.select { |i| i[:file] == 'app/jobs/inventory/toast_stock_job.rb' }
    expect(inventory_issues).not_to be_empty
    expect(inventory_issues.any? { |i| i[:message].include?('Inventory') }).to be true
  end
  
  it "detects CheckJob namespace issues" do
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
    
    # Verify that CheckJob namespace issues were detected
    check_issues = issues.select { |i| i[:file] == 'app/jobs/check_job.rb' }
    expect(check_issues).not_to be_empty
    expect(check_issues.any? { |i| i[:message].include?('CheckJob') }).to be true
  end
  
  it "updates job namespaces when explicitly enabled" do
    # Create a sample job file
    check_job_path = File.join(temp_dir, 'app', 'jobs', 'check_job.rb')
    FileUtils.mkdir_p(File.dirname(check_job_path))
    File.write(check_job_path, <<~RUBY)
      class CheckJob < ApplicationJob
        queue_as :default
        
        def perform(location_id)
          # Check POS status
        end
      end
    RUBY
    
    # Enable update_pos_status_jobs option
    options = { 
      update_pos_status_jobs: true,
      test_mode: true,
      dry_run: false
    }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], options)
    result = upgrader.upgrade
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('app/jobs/check_job.rb')
    
    # Check if new file was created
    new_file_path = File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'pos_status', 'check.rb')
    expect(File.exist?(new_file_path)).to be true
    
    # Check content of new file
    new_content = File.read(new_file_path)
    expect(new_content).to include('module Sidekiq')
    expect(new_content).to include('module PosStatus')
    expect(new_content).to include('class Check < ApplicationJob')
    
    # Check content of old file (should be updated with transition implementation)
    check_content = File.read(check_job_path)
    if options[:test_mode]
      # In test mode, we directly replace the content
      expect(check_content).to include('module Sidekiq')
      expect(check_content).to include('module PosStatus')
      expect(check_content).to include('class Check < ApplicationJob')
    else
      # In normal mode, we create a transition file
      expect(check_content).to include('# This is a transition file')
      expect(check_content).to include('Sidekiq::PosStatus::Check')
    end
  end
end
