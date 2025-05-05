require 'spec_helper'
require 'fileutils'
require 'tempfile'

RSpec.describe RailsUpshift::Analyzer do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'models'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'controllers'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'jobs', 'sidekiq', 'stock'))
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'services', 'orders'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
    File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 5.2.0'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  describe '#analyze' do
    it 'detects deprecated methods' do
      # Create a file with deprecated methods
      File.write(File.join(temp_dir, 'app', 'models', 'user.rb'), <<~RUBY)
        class User < ApplicationRecord
          def self.find_user(id)
            find_by_id(id)
          end
          
          def update_user_attributes(attrs)
            update_attributes(attrs)
          end
        end
      RUBY
      
      analyzer = described_class.new(temp_dir)
      issues = analyzer.analyze
      
      expect(issues).to include(
        hash_including(
          file: "app/models/user.rb",
          message: include("Deprecated method 'update_attributes'")
        )
      )
      
      expect(issues).to include(
        hash_including(
          file: "app/models/user.rb",
          message: include("Dynamic finders (find_by_*) are deprecated")
        )
      )
    end
    
    it 'detects time-related issues' do
      # Create a file with time-related issues
      File.write(File.join(temp_dir, 'app', 'models', 'event.rb'), <<~RUBY)
        class Event < ApplicationRecord
          def self.today_events
            where(date: Date.today)
          end
          
          def current_time
            Time.now
          end
        end
      RUBY
      
      analyzer = described_class.new(temp_dir)
      issues = analyzer.analyze
      
      expect(issues).to include(
        hash_including(
          file: "app/models/event.rb",
          message: include("Use Time.current instead of Time.now")
        )
      )
      
      expect(issues).to include(
        hash_including(
          file: "app/models/event.rb",
          message: include("Consider using Time.current.to_date instead of Date.today")
        )
      )
    end
    
    it 'detects Sidekiq namespace issues' do
      # Create a file with Sidekiq namespace issues
      File.write(File.join(temp_dir, 'app', 'jobs', 'inventory', 'toast_stock_job.rb'), <<~RUBY)
        module Inventory
          class ToastStockJob < ApplicationJob
            def perform(location_id)
              # Do something
            end
          end
        end
      RUBY
      
      analyzer = described_class.new(temp_dir)
      issues = analyzer.analyze
      
      expect(issues).to include(
        hash_including(
          file: "app/jobs/inventory/toast_stock_job.rb",
          message: include("Consider transitioning from Inventory::*StockJob to Sidekiq::Stock::*")
        )
      )
    end
    
    it 'detects API module naming issues' do
      # Create a file with API module naming issues
      File.write(File.join(temp_dir, 'app', 'controllers', 'api_controller.rb'), <<~RUBY)
        module API
          class BaseController < ApplicationController
            # Base controller for API
          end
        end
      RUBY
      
      analyzer = described_class.new(temp_dir)
      issues = analyzer.analyze
      
      expect(issues).to include(
        hash_including(
          file: "app/controllers/api_controller.rb",
          message: include("Module named 'API' should be renamed to 'Api'")
        )
      )
    end
  end
  
  describe '#detect_target_version' do
    it 'detects the target version from Gemfile' do
      # Create a Gemfile with a specific Rails version
      File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 6.1.0'")
      
      analyzer = described_class.new(temp_dir)
      expect(analyzer.target_version).to eq('6.1.0')
    end
    
    it 'defaults to latest if no version found' do
      # Create an empty Gemfile
      File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'")
      
      analyzer = described_class.new(temp_dir)
      expect(analyzer.target_version).to eq('7.0.0')
    end
  end
end
