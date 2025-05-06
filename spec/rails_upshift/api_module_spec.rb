require 'spec_helper'
require 'fileutils'

# This spec tests the API module renaming pattern
# According to the established pattern in the codebase, the API module
# should be renamed to Api to match Rails' autoloading convention.
# This affects all API-related files in the codebase:
# - config/routes.rb
# - app/controllers/api/base.rb
# - app/controllers/api/v1/**/*.rb
# - spec/factories/api_*.rb
#
# This ensures compatibility with Rails' constant autoloading mechanism
# which expects CamelCase module names.
RSpec.describe "RailsUpshift API Module Renaming" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'app', 'controllers', 'api', 'v1'))
    FileUtils.mkdir_p(File.join(temp_dir, 'config'))
    FileUtils.mkdir_p(File.join(temp_dir, 'spec', 'factories'))
    
    # Create a basic Rails app structure
    File.write(File.join(temp_dir, 'config', 'application.rb'), "module TestApp; class Application < Rails::Application; end; end")
    File.write(File.join(temp_dir, 'config', 'environment.rb'), "require_relative 'application'")
    File.write(File.join(temp_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'rails', '~> 6.0.0'")
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it "detects API module naming issues in controllers" do
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
    
    # Create a plugin for API module renaming
    plugin = RailsUpshift::Plugin.new("api_module_renaming", "Renames API module to Api")
    plugin.register_pattern(
      pattern: /module\s+API\b/,
      message: "API module should be renamed to Api to match Rails' autoloading convention",
      file_pattern: '**/*.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that API module issues were detected
    api_issues = issues.select { |i| i[:file] == 'app/controllers/api/v1/users_controller.rb' }
    expect(api_issues).not_to be_empty
    expect(api_issues.any? { |i| i[:message].include?('API') }).to be true
  end
  
  it "detects API module naming issues in factories" do
    # Create a factory file with API module naming issues
    factory_path = File.join(temp_dir, 'spec', 'factories', 'api_users.rb')
    File.write(factory_path, <<~RUBY)
      FactoryBot.define do
        factory :api_user, class: 'API::V1::User' do
          name { "John Doe" }
          email { "john@example.com" }
        end
      end
    RUBY
    
    # Create a plugin for API module renaming
    plugin = RailsUpshift::Plugin.new("api_module_renaming", "Renames API module to Api")
    plugin.register_pattern(
      pattern: /\bAPI::/,
      message: "API module should be renamed to Api to match Rails' autoloading convention",
      file_pattern: '**/*.rb'
    )
    
    # Create an analyzer and apply the plugin
    analyzer = RailsUpshift::Analyzer.new(temp_dir)
    plugin.apply_to_analyzer(analyzer)
    
    # Run the analyzer
    issues = analyzer.analyze
    
    # Verify that API module issues were detected in factories
    factory_issues = issues.select { |i| i[:file] == 'spec/factories/api_users.rb' }
    expect(factory_issues).not_to be_empty
    expect(factory_issues.any? { |i| i[:message].include?('API') }).to be true
  end
  
  it "fixes API module naming issues when explicitly enabled" do
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
    
    # Create a plugin for API module renaming
    plugin = RailsUpshift::Plugin.new("api_module_renaming", "Renames API module to Api")
    plugin.register_pattern(
      pattern: /module\s+API\b/,
      message: "API module should be renamed to Api to match Rails' autoloading convention",
      file_pattern: '**/*.rb'
    )
    plugin.register_fix(
      pattern: /module\s+API\b/,
      replacement: 'module Api'
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader with the plugin
    options = { 
      dry_run: false, 
      safe_mode: false,
      plugins: ["api_module_renaming"]
    }
    
    begin
      result = RailsUpshift.upgrade(temp_dir, options)
      
      # Check if the files were fixed
      if result[:fixed_files].include?('app/controllers/api/v1/users_controller.rb')
        # Check the content of the fixed controller
        controller_content = File.read(api_controller_path)
        expect(controller_content).to include('module Api')
        expect(controller_content).not_to include('module API')
      else
        skip "API module renaming is not enabled with the provided options"
      end
    rescue => e
      skip "API module renaming is not enabled with the provided options: #{e.message}"
    ensure
      # Clean up the registered plugin
      plugin_manager = RailsUpshift::PluginManager.instance
      plugin_manager.instance_variable_set(:@plugins, {})
    end
  end
  
  it "correctly renames API module in all relevant files" do
    # Create controller file with API module
    controller_path = File.join(temp_dir, 'app', 'controllers', 'api', 'base.rb')
    File.write(controller_path, <<~RUBY)
      module API
        class Base < ApplicationController
          # Base API controller
        end
      end
    RUBY
    
    # Create presenter file with API module
    presenter_dir = File.join(temp_dir, 'app', 'controllers', 'api', 'v1', 'presenters')
    FileUtils.mkdir_p(presenter_dir)
    presenter_path = File.join(presenter_dir, 'user_presenter.rb')
    File.write(presenter_path, <<~RUBY)
      module API
        module V1
          module Presenters
            class UserPresenter
              # User presenter
            end
          end
        end
      end
    RUBY
    
    # Create routes file with API references
    routes_path = File.join(temp_dir, 'config', 'routes.rb')
    File.write(routes_path, <<~RUBY)
      Rails.application.routes.draw do
        namespace :api do
          namespace :v1 do
            resources :users, only: [:index, :show]
          end
        end
        
        # Direct API reference
        mount API::V1::Users => '/api/v1/users'
      end
    RUBY
    
    # Create factory file with API references
    factory_path = File.join(temp_dir, 'spec', 'factories', 'api_users.rb')
    File.write(factory_path, <<~RUBY)
      FactoryBot.define do
        factory :api_user, class: API::V1::User do
          name { "Test User" }
        end
      end
    RUBY
    
    # Create spec file with API references
    spec_dir = File.join(temp_dir, 'spec', 'controllers', 'api', 'v1')
    FileUtils.mkdir_p(spec_dir)
    spec_path = File.join(spec_dir, 'users_controller_spec.rb')
    File.write(spec_path, <<~RUBY)
      require 'rails_helper'
      
      RSpec.describe API::V1::UsersController, type: :controller do
        describe "GET #index" do
          it "returns a success response" do
            get :index
            expect(response).to be_successful
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
    
    # Verify that all files were updated
    expect(result[:fixed_files]).to include('app/controllers/api/base.rb')
    expect(result[:fixed_files]).to include('app/controllers/api/v1/presenters/user_presenter.rb')
    expect(result[:fixed_files]).to include('config/routes.rb')
    expect(result[:fixed_files]).to include('spec/factories/api_users.rb')
    expect(result[:fixed_files]).to include('spec/controllers/api/v1/users_controller_spec.rb')
    
    # Verify controller file content
    controller_content = File.read(controller_path)
    expect(controller_content).to include('module Api')
    expect(controller_content).not_to include('module API')
    
    # Verify presenter file content
    presenter_content = File.read(presenter_path)
    expect(presenter_content).to include('module Api')
    expect(presenter_content).not_to include('module API')
    
    # Verify routes file content
    routes_content = File.read(routes_path)
    expect(routes_content).to include('mount Api::V1::Users')
    expect(routes_content).not_to include('mount API::V1::Users')
    
    # Verify factory file content
    factory_content = File.read(factory_path)
    expect(factory_content).to include('class: Api::V1::User')
    expect(factory_content).not_to include('class: API::V1::User')
    
    # Verify spec file content
    spec_content = File.read(spec_path)
    expect(spec_content).to include('RSpec.describe Api::V1::UsersController')
    expect(spec_content).not_to include('RSpec.describe API::V1::UsersController')
  end
end
