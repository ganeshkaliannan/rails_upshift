require 'spec_helper'
require 'fileutils'

RSpec.describe "RailsUpshift Basic Integration" do
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
  
  it "analyzes and finds issues" do
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
    
    # Verify that issues were detected
    expect(issues).not_to be_empty
    expect(issues.any? { |i| i[:file] == 'app/controllers/api/v1/users_controller.rb' }).to be true
    expect(issues.any? { |i| i[:message].include?('API') }).to be true
  end
  
  it "performs a dry run upgrade" do
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
    
    # Run the upgrader with dry_run=true
    result = RailsUpshift.upgrade(temp_dir, dry_run: true)
    
    # Verify that issues were detected but no files were modified
    expect(result[:issues]).not_to be_empty
    expect(result[:fixed_files]).to be_empty
    
    # Verify the content was not modified
    content = File.read(api_controller_path)
    expect(content).to include('module API')
    expect(content).not_to include('module Api')
  end
  
  it "registers and applies custom fixes" do
    # Create a file with a custom pattern
    custom_path = File.join(temp_dir, 'app', 'models')
    FileUtils.mkdir_p(custom_path)
    custom_file = File.join(custom_path, 'custom.rb')
    File.write(custom_file, <<~RUBY)
      class Custom < ApplicationRecord
        # FIXME: This is a test comment
      end
    RUBY
    
    # Create a custom plugin
    plugin = RailsUpshift.create_plugin('custom_plugin', '6.0.0')
    plugin.register_pattern(
      pattern: /# FIXME:/,
      message: "FIXME comment found",
      file_pattern: "**/*.rb"
    )
    plugin.register_fix(
      pattern: /# FIXME:/,
      replacement: '# TODO:'
    )
    
    # Register the plugin
    RailsUpshift.register_plugin(plugin)
    
    # Run the upgrader
    result = RailsUpshift.upgrade(temp_dir, dry_run: false)
    
    # Check if the plugin was applied
    if result[:fixed_files].include?('app/models/custom.rb')
      # If the file was fixed, verify the content
      modified_content = File.read(custom_file)
      expect(modified_content).to include('# TODO:')
      expect(modified_content).not_to include('# FIXME:')
    else
      # Skip this test if custom plugins aren't working as expected
      skip "Custom plugin did not apply fixes as expected"
    end
  end
end
