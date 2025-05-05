require 'spec_helper'
require 'fileutils'

RSpec.describe RailsUpshift::Upgrader do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  let(:issues) { [] }
  let(:options) { { dry_run: false, safe_mode: true } }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'models'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'controllers'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'inventory'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'services', 'orders'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  describe '#upgrade' do
    it 'fixes deprecated methods' do
      # Create a file with deprecated methods
      file_path = File.join(temp_dir, 'app', 'models', 'user.rb')
      File.write(file_path, <<~RUBY)
        class User < ApplicationRecord
          def update_user_attributes(attrs)
            update_attributes(attrs)
          end
        end
      RUBY
      
      issues << {
        file: 'app/models/user.rb',
        message: "Deprecated method 'update_attributes' - use 'update' instead",
        pattern: '\.update_attributes[!\(]'
      }
      
      upgrader = described_class.new(temp_dir, issues, options)
      result = upgrader.upgrade
      
      expect(result[:fixed_files]).to include('app/models/user.rb')
      expect(File.read(file_path)).to include('update(attrs)')
      expect(File.read(file_path)).not_to include('update_attributes(attrs)')
    end
    
    it 'fixes time-related issues' do
      # Create a file with time-related issues
      file_path = File.join(temp_dir, 'app', 'models', 'event.rb')
      File.write(file_path, <<~RUBY)
        class Event < ApplicationRecord
          def self.today_events
            where(date: Date.today)
          end
          
          def current_time
            Time.now
          end
        end
      RUBY
      
      issues << {
        file: 'app/models/event.rb',
        message: "Use Time.current instead of Time.now for proper timezone handling",
        pattern: 'Time\.now'
      }
      
      issues << {
        file: 'app/models/event.rb',
        message: "Consider using Time.current.to_date instead of Date.today for timezone consistency",
        pattern: 'Date\.today'
      }
      
      upgrader = described_class.new(temp_dir, issues, options)
      result = upgrader.upgrade
      
      expect(result[:fixed_files]).to include('app/models/event.rb')
      expect(File.read(file_path)).to include('Time.current')
      expect(File.read(file_path)).to include('Time.current.to_date')
      expect(File.read(file_path)).not_to include('Time.now')
      expect(File.read(file_path)).not_to include('Date.today')
    end
    
    it 'fixes Sidekiq namespace issues' do
      # Create a file with Sidekiq namespace issues
      file_path = File.join(temp_dir, 'app', 'jobs', 'inventory', 'toast_stock_job.rb')
      File.write(file_path, <<~RUBY)
        module Inventory
          class ToastStockJob < ApplicationJob
            def perform(location_id)
              # Do something
            end
          end
        end
      RUBY
      
      issues << {
        file: 'app/jobs/inventory/toast_stock_job.rb',
        message: "Consider transitioning from Inventory::*StockJob to Sidekiq::Stock::* namespace",
        pattern: 'module\s+Inventory\s+.*class\s+\w+StockJob'
      }
      
      options[:update_job_namespaces] = true
      upgrader = described_class.new(temp_dir, issues, options)
      result = upgrader.upgrade
      
      expect(result[:fixed_files]).to include('app/jobs/inventory/toast_stock_job.rb')
      
      # Check if the file was properly updated with the new namespace
      content = File.read(file_path)
      expect(content).to include('module Sidekiq')
      expect(content).to include('module Stock')
      expect(content).to include('class Toast < ApplicationJob')
      expect(content).not_to include('module Inventory')
      expect(content).not_to include('class ToastStockJob')
    end
    
    it 'fixes API module naming issues' do
      # Create a file with API module naming issues
      file_path = File.join(temp_dir, 'app', 'controllers', 'api_controller.rb')
      File.write(file_path, <<~RUBY)
        module API
          class BaseController < ApplicationController
            # Base controller for API
          end
        end
      RUBY
      
      issues << {
        file: 'app/controllers/api_controller.rb',
        message: "Module named 'API' should be renamed to 'Api' for Rails autoloading",
        pattern: 'module\s+API\b'
      }
      
      upgrader = described_class.new(temp_dir, issues, options)
      result = upgrader.upgrade
      
      expect(result[:fixed_files]).to include('app/controllers/api_controller.rb')
      
      # Check if the file was properly updated with the new module name
      content = File.read(file_path)
      expect(content).to include('module Api')
      expect(content).not_to include('module API')
    end
    
    it 'respects dry run mode' do
      # Create a file with deprecated methods
      file_path = File.join(temp_dir, 'app', 'models', 'user.rb')
      original_content = <<~RUBY
        class User < ApplicationRecord
          def update_user_attributes(attrs)
            update_attributes(attrs)
          end
        end
      RUBY
      
      File.write(file_path, original_content)
      
      issues << {
        file: 'app/models/user.rb',
        message: "Deprecated method 'update_attributes' - use 'update' instead",
        pattern: '\.update_attributes[!\(]'
      }
      
      options[:dry_run] = true
      upgrader = described_class.new(temp_dir, issues, options)
      result = upgrader.upgrade
      
      # In dry run mode, we should report the file but not actually change it
      expect(result[:issues]).to include(hash_including(file: 'app/models/user.rb'))
      expect(File.read(file_path)).to eq(original_content)
    end
  end
end
