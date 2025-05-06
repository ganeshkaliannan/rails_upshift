module RailsUpshift
  class Upgrader
    attr_reader :path, :issues, :options, :fixed_files
    
    def initialize(path, issues, options = {})
      @path = path
      @issues = issues
      @options = options
      @fixed_files = []
      @custom_fixes = {}
      @target_version = options[:target_version]
      @analyzer = Analyzer.new(path, @target_version)
    end
    
    def upgrade
      return { issues: @issues, fixed_files: [] } if @options[:dry_run]
      
      # Group issues by file for more efficient processing
      issues_by_file = @issues.group_by { |issue| issue[:file] }
      
      issues_by_file.each do |file, file_issues|
        next if skip_file?(file)
        
        full_path = File.join(@path, file)
        next unless File.exist?(full_path)
        
        content = File.read(full_path)
        original_content = content.dup
        
        file_issues.each do |issue|
          next if skip_issue?(issue)
          
          if fix_issue(issue, content)
            puts "Fixed issue in #{file}: #{issue[:message]}" if @options[:verbose]
          end
        end
        
        if content != original_content
          File.write(full_path, content)
          @fixed_files << file
        end
      end
      
      # Special handling for specific update options
      update_gemfile if @options[:update_gems]
      update_config_files if @options[:update_configs]
      if @options[:update_job_namespaces]
        update_job_namespaces
      end
      
      # Always update migration versions for Rails 5.2.0 or higher
      if @target_version && Gem::Version.new(@target_version) >= Gem::Version.new("5.2.0")
        update_migration_versions
      end
      
      { issues: @issues, fixed_files: @fixed_files }
    end
    
    # Register a custom fix for a pattern
    # @param pattern [Regexp] the pattern to match
    # @param replacement [String, Proc] the replacement string or a proc that takes the match and returns a string
    # @param safe [Boolean] whether the fix is considered safe
    def register_fix(pattern:, replacement:, safe: true)
      @custom_fixes[pattern.source] = {
        replacement: replacement,
        safe: safe
      }
    end
    
    private
    
    def skip_file?(file)
      # Skip files that shouldn't be automatically modified
      return true if file =~ /\b(schema\.rb|migrate|db\/data|vendor\/|node_modules\/)/
      false
    end
    
    def skip_issue?(issue)
      # Skip issues that require manual intervention or are unsafe in safe mode
      return true if @options[:safe_mode] && unsafe_pattern?(issue[:pattern])
      false
    end
    
    def unsafe_pattern?(pattern)
      # Patterns that are considered unsafe to automatically fix
      unsafe_patterns = [
        'default_scope',
        'update_all',
        'config\.hosts',
        'config\.load_defaults'
      ]
      
      unsafe_patterns.any? { |unsafe| pattern.include?(unsafe) }
    end
    
    def fix_issue(issue, content)
      pattern = issue[:pattern]
      
      # Check if there's a custom fix registered for this pattern
      if @custom_fixes.key?(pattern)
        fix = @custom_fixes[pattern]
        return false if @options[:safe_mode] && !fix[:safe]
        
        if fix[:replacement].is_a?(Proc)
          content.gsub!(Regexp.new(pattern, Regexp::MULTILINE)) do |match|
            fix[:replacement].call(match)
          end
        else
          content.gsub!(Regexp.new(pattern, Regexp::MULTILINE), fix[:replacement])
        end
        return true
      end
      
      # Built-in fixes for common patterns
      case pattern
      when /\.update_attributes[!\(]/
        content.gsub!(/\.update_attributes(\(|\!)/, '.update\1')
      when /\.success\?/
        content.gsub!(/\.success\?/, '.successful?')
      when /\.find_by_([a-zA-Z_]+)\b/
        content.gsub!(/\.find_by_([a-zA-Z_]+)\b/) do |match|
          attribute = $1
          ".find_by(#{attribute}: #{attribute == 'id' ? '' : attribute})"
        end
      when /\.find_or_initialize_by_([a-zA-Z_]+)\b/
        content.gsub!(/\.find_or_initialize_by_([a-zA-Z_]+)\b/) do |match|
          attribute = $1
          ".find_or_initialize_by(#{attribute}: #{attribute == 'id' ? '' : attribute})"
        end
      when /\.find_or_create_by_([a-zA-Z_]+)\b/
        content.gsub!(/\.find_or_create_by_([a-zA-Z_]+)\b/) do |match|
          attribute = $1
          ".find_or_create_by(#{attribute}: #{attribute == 'id' ? '' : attribute})"
        end
      when /\.scoped\b/
        content.gsub!(/\.scoped\b/, '.all')
      when /\.where\(["']([^=]+)=["']/
        content.gsub!(/\.where\(["']([^=]+)\s*=\s*["']([^)]+)["']\)/) do |match|
          column = $1
          value = $2
          ".where(#{column}: #{value})"
        end
      when /Time\.now/
        content.gsub!(/Time\.now/, 'Time.current')
      when /DateTime\.now/
        content.gsub!(/DateTime\.now/, 'Time.current')
      when /Date\.today/
        content.gsub!(/Date\.today/, 'Time.current.to_date')
      when /URI\.escape/
        content.gsub!(/URI\.escape\(([^)]+)\)/, 'CGI.escape(\1.to_s)')
      when /URI\.unescape/
        content.gsub!(/URI\.unescape\(([^)]+)\)/, 'CGI.unescape(\1.to_s)')
      when /CGI\.escape\(([^)]+)\)/
        unless content.include?('ruby')
          content.gsub!(/CGI\.escape\(([^)]+\.to_s)\)/, 'CGI.escape(\1.to_s)')
        end
      when /\.present\?\s*$/
        content.gsub!(/(\w+)\.present\?\s*$/) do |match|
          var_name = $1
          # Check if this variable is likely an array/collection
          if content =~ /#{var_name}\s*<<|#{var_name}\.each|#{var_name}\.map|#{var_name}\[/
            "#{var_name}.reject(&:blank?).present?"
          else
            match
          end
        end
      when /\.merge\([^)]+\)\)(?!\s*\*\*)/
        content.gsub!(/\.merge\(([^)]+)\)\)/, '.merge(\1) **)')
      when /module\s+API\b/
        content.gsub!(/module\s+API\b/, 'module Api')
      when /API::/
        content.gsub!(/API::/, 'Api::')
      when /\.pluck\(:id\)\.include\?/
        content.gsub!(/\.pluck\(:id\)\.include\?\((.+?)\)/, '.exists?(\1)')
      when /\.where\(["']([^=]+)=["']/
        content.gsub!(/\.where\(["']([^=]+)\s*=\s*["']([^)]+)["']\)/) do |match|
          column = $1
          value = $2
          ".where(#{column}: #{value})"
        end
      when /settings\s*=\s*\{[^}]*=>\s*true|settings\s*=\s*\{[^}]*=>\s*false/
        content.gsub!(/(settings\s*=\s*\{[^}]*=>\s*)(true|false)(\s*[,}])/, '\1"\2"\3')
      when /settings\s*=\s*\{[^}]*:[a-zA-Z_]+\s*=>/
        content.gsub!(/(settings\s*=\s*\{[^}]*:)([a-zA-Z_]+)(\s*=>)/, '\1"\2"\3')
      when /failure_reason\s*=>\s*['"][^'"]*['"]/
        if content =~ /failure_reason\s*=>\s*["']Out of stock["']/i
          content.gsub!(/failure_reason\s*=>\s*["']Out of stock["']/i, 'failure_reason: "OUT_OF_ITEM"')
        elsif content =~ /failure_reason\s*=>\s*["']Store closed["']/i
          content.gsub!(/failure_reason\s*=>\s*["']Store closed["']/i, 'failure_reason: "STORE_CLOSED"')
        elsif content =~ /failure_reason\s*=>\s*["']Too busy["']/i
          content.gsub!(/failure_reason\s*=>\s*["']Too busy["']/i, 'failure_reason: "STORE_BUSY"')
        elsif content =~ /failure_reason\s*=>\s*["']Rejected["']/i
          content.gsub!(/failure_reason\s*=>\s*["']Rejected["']/i, 'failure_reason: "MERCHANT_REJECTED"')
        end
      when /module\s+Inventory\s+.*class\s+\w+StockJob/m
        if @options[:update_job_namespaces]
          content.gsub!(/module\s+Inventory\s+.*?class\s+(\w+)StockJob(.*?)end\s+end/m) do
            class_name = $1
            class_body = $2
            
            "module Sidekiq\n  module Stock\n    class #{class_name}#{class_body}  end\n  end\nend"
          end
        end
      when /class\s+CheckJob\s+<\s+ApplicationJob/
        if @options[:update_job_namespaces]
          content.gsub!(/class\s+CheckJob\s+<\s+ApplicationJob(.*?)end/m) do
            class_body = $1
            
            "module Sidekiq\n  module PosStatus\n    class Check < ApplicationJob#{class_body}    end\n  end\nend"
          end
        end
      when /class\s+\w+::\w+Job\s+<\s+ApplicationJob/
        if @options[:update_job_namespaces]
          content.gsub!(/class\s+(\w+)::(\w+)Job\s+<\s+ApplicationJob(.*?)end/m) do
            module_name = $1
            job_name = $2
            class_body = $3
            
            "module Sidekiq\n  module #{module_name}\n    class #{job_name} < ApplicationJob#{class_body}    end\n  end\nend"
          end
        end
      when /where\(\s*["'](settings\s*->>\s*['"][a-zA-Z_]+)["']\)\s*=\s*['"]?(true|false)['"]?\)/
        content.gsub!(/where\(\s*["'](settings\s*->>\s*['"][a-zA-Z_]+)["']\)\s*=\s*['"]?(true|false)['"]?\)/) do |match|
          setting_expr = $1
          bool_value = $2
          "where((#{setting_expr})::boolean IS #{bool_value})"
        end
      else
        return false
      end
      
      true
    end
    
    def update_gemfile
      gemfile_path = File.join(@path, 'Gemfile')
      return unless File.exist?(gemfile_path)
      
      content = File.read(gemfile_path)
      original_content = content.dup
      
      target_version = @target_version
      
      # Detect Ruby version in use
      ruby_version = content.match(/ruby\s+['"](\d+\.\d+\.\d+)['"]/)&.captures&.first || "2.5.0"
      
      # Update gem versions based on target Rails version
      if Gem::Version.new(target_version) >= Gem::Version.new("7.0.0")
        # Rails 7 updates
        content.gsub!(/gem\s+['"]rails['"],\s+['"].*?['"]/, "gem 'rails', '~> 7.0.0'")
        content.gsub!(/gem\s+['"]sass-rails['"],\s+['"].*?['"]/, "gem 'cssbundling-rails'")
        content.gsub!(/gem\s+['"]uglifier['"],\s+['"].*?['"]/, "gem 'jsbundling-rails'")
        content.gsub!(/gem\s+['"]coffee-rails['"],\s+['"].*?['"]/, "# gem 'coffee-rails' # Removed in Rails 7")
        
        # Handle incompatible gems for Rails 7
        handle_incompatible_gems(content, "7.0.0", ruby_version)
        
        # Ensure proper Ruby version
        unless content.include?('ruby')
          content = "ruby '3.0.0'\n" + content
        end
      elsif Gem::Version.new(target_version) >= Gem::Version.new("6.0.0")
        # Rails 6 updates
        content.gsub!(/gem\s+['"]rails['"],\s+['"].*?['"]/, "gem 'rails', '~> 6.1.0'")
        
        # Handle incompatible gems for Rails 6
        handle_incompatible_gems(content, "6.0.0", ruby_version)
        
        # Ensure proper Ruby version
        unless content.include?('ruby')
          content = "ruby '2.7.0'\n" + content
        end
      elsif Gem::Version.new(target_version) >= Gem::Version.new("5.0.0")
        # Rails 5 updates
        content.gsub!(/gem\s+['"]rails['"],\s+['"].*?['"]/, "gem 'rails', '~> 5.2.0'")
        
        # Remove incompatible gems
        content.gsub!(/gem\s+['"]protected_attributes['"].*$/, "# gem 'protected_attributes' # Removed in Rails 5")
        content.gsub!(/gem\s+['"]activerecord-deprecated_finders['"].*$/, "# gem 'activerecord-deprecated_finders' # Removed in Rails 5")
        
        # Add bootsnap gem for Rails 5.2.0 if not already present
        unless content.include?('bootsnap')
          # Add bootsnap gem at the end of the file
          content << "\n# Added by rails_upshift for Rails 5.2.0\ngem 'bootsnap', '>= 1.1.0', require: false\n"
        end
        
        # Handle incompatible gems for Rails 5
        handle_incompatible_gems(content, "5.0.0", ruby_version)
        
        # Ensure proper Ruby version
        unless content.include?('ruby')
          content = "ruby '2.5.0'\n" + content
        end
      end
      
      if content != original_content
        File.write(gemfile_path, content)
        @fixed_files << 'Gemfile'
      end
    end
    
    # Handle incompatible gems for different Rails versions
    def handle_incompatible_gems(content, rails_version, ruby_version)
      # Common incompatible gems for all Rails versions
      incompatible_gems = {
        "7.0.0" => [
          { pattern: /gem\s+['"]coffee-rails['"].*$/, replacement: "# gem 'coffee-rails' # Incompatible with Rails 7.x" },
          { pattern: /gem\s+['"]jquery-rails['"].*$/, replacement: "# gem 'jquery-rails' # Consider using importmap-rails in Rails 7" }
        ],
        "6.0.0" => [
          { pattern: /gem\s+['"]coffee-rails['"].*$/, replacement: "# gem 'coffee-rails' # Consider using webpacker in Rails 6" }
        ],
        "5.0.0" => [
          { pattern: /gem\s+['"]grape_on_rails_routes['"].*$/, replacement: "# gem 'grape_on_rails_routes' # Incompatible with Rails 5.x" },
          { pattern: /gem\s+['"]protected_attributes['"].*$/, replacement: "# gem 'protected_attributes' # Removed in Rails 5" },
          { pattern: /gem\s+['"]activerecord-deprecated_finders['"].*$/, replacement: "# gem 'activerecord-deprecated_finders' # Removed in Rails 5" },
          { pattern: /gem\s+['"]rspec-rails['"],?\s*['"]?[^'"]*['"]?/, replacement: "gem 'rspec-rails', '~> 4.0' # Updated for Rails 5.x compatibility" }
        ]
      }
      
      # Ruby version specific gem requirements
      ruby_specific_gems = {
        "2.6" => [
          { pattern: /gem\s+['"]nokogiri['"].*$/, replacement: "gem 'nokogiri', '~> 1.13.10' # Pinned for Ruby 2.6.x compatibility" }
        ],
        "2.5" => [
          { pattern: /gem\s+['"]nokogiri['"].*$/, replacement: "gem 'nokogiri', '~> 1.12.5' # Pinned for Ruby 2.5.x compatibility" }
        ]
      }
      
      # Apply incompatible gem replacements for the target Rails version
      incompatible_gems.each do |version, replacements|
        if Gem::Version.new(rails_version) >= Gem::Version.new(version)
          replacements.each do |replacement|
            content.gsub!(replacement[:pattern], replacement[:replacement])
          end
        end
      end
      
      # Apply Ruby version specific gem requirements
      ruby_specific_gems.each do |version_prefix, replacements|
        if ruby_version.start_with?(version_prefix)
          replacements.each do |replacement|
            content.gsub!(replacement[:pattern], replacement[:replacement])
          end
        end
      end
    end
    
    def update_config_files
      return unless @options[:update_configs]
      
      # Update boot.rb for Rails 5.2+ to use bootsnap
      boot_rb_path = File.join(@path, 'config', 'boot.rb')
      if File.exist?(boot_rb_path) && Gem::Version.new(@target_version) >= Gem::Version.new("5.2.0")
        boot_content = File.read(boot_rb_path)
        
        # Add bootsnap setup if not already present
        unless boot_content.include?('bootsnap/setup')
          boot_content.gsub!(/require 'bundler\/setup'.*$/, "require 'bundler/setup' # Set up gems listed in the Gemfile.\nrequire 'bootsnap/setup' # Speed up boot time by caching expensive operations.")
          File.write(boot_rb_path, boot_content)
          @fixed_files << boot_rb_path.sub(@path + '/', '')
        end
      end
      
      # Update application.rb
      application_rb_path = File.join(@path, 'config', 'application.rb')
      if File.exist?(application_rb_path)
        content = File.read(application_rb_path)
        original_content = content.dup
        
        # Add config.load_defaults if missing
        if !content.include?('config.load_defaults')
          load_defaults_line = "    config.load_defaults #{@target_version.split('.')[0..1].join('.')}\n"
          content.gsub!(/(\s+class Application < Rails::Application\s+)/) do |match|
            "#{$1}#{load_defaults_line}"
          end
        elsif content =~ /config\.load_defaults\s+[\d\.]+/
          # Update existing config.load_defaults
          content.gsub!(/config\.load_defaults\s+[\d\.]+/, "config.load_defaults #{@target_version.split('.')[0..1].join('.')}")
        end
        
        if content != original_content
          File.write(application_rb_path, content)
          @fixed_files << 'config/application.rb'
        end
      end
      
      # Update development.rb for Rails 6+
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        development_rb_path = File.join(@path, 'config', 'environments', 'development.rb')
        if File.exist?(development_rb_path)
          content = File.read(development_rb_path)
          original_content = content.dup
          
          # Add config.hosts if missing
          if !content.include?('config.hosts')
            hosts_line = "  # Whitelist all hosts in development\n  config.hosts.clear\n"
            content.gsub!(/(\s+config\.action_mailer.*?\n)/) do |match|
              "#{$1}\n#{hosts_line}"
            end
          end
          
          if content != original_content
            File.write(development_rb_path, content)
            @fixed_files << 'config/environments/development.rb'
          end
        end
      end
      
      # Update production.rb for Rails 7+
      if Gem::Version.new(@target_version) >= Gem::Version.new("7.0.0")
        production_rb_path = File.join(@path, 'config', 'environments', 'production.rb')
        if File.exist?(production_rb_path)
          content = File.read(production_rb_path)
          original_content = content.dup
          
          # Update JS compressor
          if content.include?('config.assets.js_compressor = :uglifier')
            content.gsub!(/config\.assets\.js_compressor = :uglifier/, "# config.assets.js_compressor = :terser")
          end
          
          if content != original_content
            File.write(production_rb_path, content)
            @fixed_files << 'config/environments/production.rb'
          end
        end
      end
      
      # Update migration version in existing migration files
      update_migration_versions if @options[:update_migrations] || (@options[:update_configs] && !@options.key?(:update_migrations))
    end
    
    # Update migration version in existing migration files
    def update_migration_versions
      migrations_path = File.join(@path, 'db', 'migrate')
      return unless Dir.exist?(migrations_path)
      
      puts "Updating migration versions in #{migrations_path}" if @options[:verbose]
      
      target_version_short = @target_version.split('.')[0..1].join('.')
      target_version_obj = Gem::Version.new(@target_version)
      
      Dir.glob(File.join(migrations_path, '*.rb')).each do |file|
        puts "Processing migration file: #{file}" if @options[:verbose]
        
        content = File.read(file)
        original_content = content.dup
        
        # Check if this is a Rails 4.x style migration (without version)
        if content =~ /class\s+\w+\s+<\s+ActiveRecord::Migration\b(?!\[)/
          puts "Found Rails 4.x style migration in #{file}" if @options[:verbose]
          
          # Update to Rails 5+ style with version
          content.gsub!(/class\s+(\w+)\s+<\s+ActiveRecord::Migration\b(?!\[)/) do
            "class #{$1} < ActiveRecord::Migration[#{target_version_short}]"
          end
          
          # Apply Rails version-specific updates
          content = apply_rails_version_specific_updates(content, target_version_obj)
          
        elsif content =~ /class\s+\w+\s+<\s+ActiveRecord::Migration\[(\d+\.\d+)\]/
          puts "Found versioned migration in #{file}" if @options[:verbose]
          current_version = $1
          current_version_obj = Gem::Version.new(current_version)
          
          # Already has a version, update it if needed
          content.gsub!(/class\s+(\w+)\s+<\s+ActiveRecord::Migration\[\d+\.\d+\]/) do
            "class #{$1} < ActiveRecord::Migration[#{target_version_short}]"
          end
          
          # Apply Rails version-specific updates based on the version difference
          content = apply_rails_version_specific_updates(content, target_version_obj, current_version_obj)
        end
        
        if content != original_content
          puts "Updating migration file: #{file}" if @options[:verbose]
          File.write(file, content)
          @fixed_files << file.sub(@path + '/', '')
        end
      end
      
      puts "Updated migration versions to Rails #{target_version_short}" if @options[:verbose]
    end
    
    # Apply Rails version-specific updates to migration content
    def apply_rails_version_specific_updates(content, target_version, current_version = nil)
      # For all Rails 5.0+ migrations
      if target_version >= Gem::Version.new("5.0.0")
        # Update timestamps with precision option if upgrading from Rails 4 or early Rails 5
        if !current_version || current_version < Gem::Version.new("5.2.0")
          content.gsub!(/t\.timestamps(?!\s*\(|\s*precision:)/, "t.timestamps precision: 6")
        end
        
        # Update references with foreign_key option if not present
        content.gsub!(/t\.references\s+:(\w+)(?!.*foreign_key)(?=\s*$|\s*,)/) do
          "t.references :#{$1}, foreign_key: true"
        end
        
        # Update references with index option if not present
        content.gsub!(/t\.references\s+:(\w+)(?!.*index)(?=\s*$|\s*,)/) do
          # If it already has foreign_key, just add index
          if $&.include?("foreign_key")
            "#{$&}, index: true"
          else
            "t.references :#{$1}, index: true"
          end
        end
        
        # Update belongs_to with foreign_key option if not present
        content.gsub!(/t\.belongs_to\s+:(\w+)(?!.*foreign_key)(?=\s*$|\s*,)/) do
          "t.belongs_to :#{$1}, foreign_key: true"
        end
        
        # Update belongs_to with index option if not present
        content.gsub!(/t\.belongs_to\s+:(\w+)(?!.*index)(?=\s*$|\s*,)/) do
          # If it already has foreign_key, just add index
          if $&.include?("foreign_key")
            "#{$&}, index: true"
          else
            "t.belongs_to :#{$1}, index: true"
          end
        end
        
        # Update json columns to jsonb for PostgreSQL
        content.gsub!(/t\.json\s+:(\w+)(?=\s*$|\s*,)/) do
          "t.jsonb :#{$1}, default: {}"
        end
      end
      
      # For Rails 7.0+ migrations
      if target_version >= Gem::Version.new("7.0.0")
        # Add check_constraint method for NOT NULL constraints
        if content.include?("null: false") && !content.include?("check_constraint")
          content.gsub!(/create_table\s+:(\w+)(?!.*do)/) do
            "create_table :#{$1} do |t|"
          end
          
          # Add if_not_exists option to create_table
          content.gsub!(/create_table\s+:(\w+)(?!.*if_not_exists)/) do
            "create_table :#{$1}, if_not_exists: true"
          end
        end
      end
      
      content
    end
    
    def update_job_namespaces
      # --- Automated fix: Module naming conventions for Rails autoloading ---
      update_api_module_naming if @options[:update_api_module] || @options[:update_job_namespaces]
      
      # --- Automated fix: Job namespace transitions ---
      update_inventory_stock_jobs if @options[:update_stock_jobs] || @options[:update_job_namespaces]
      update_order_jobs if @options[:update_order_jobs] || @options[:update_job_namespaces]
      update_pos_status_jobs if @options[:update_pos_status_jobs] || @options[:update_job_namespaces]
      
      # If no specific option is provided, update all job namespaces
      if @options[:update_job_namespaces]
        update_api_module_naming
        update_inventory_stock_jobs
        update_order_jobs
        update_pos_status_jobs
      end
    end
    
    private
    
    def update_api_module_naming
      # First, handle controllers
      Dir.glob(File.join(@path, "app/controllers/api/**/*.rb")).each do |file|
        content = File.read(file)
        original_content = content.dup
        
        # Replace module API with module Api
        content.gsub!(/module\s+API\b/, 'module Api')
        
        # Replace API:: references with Api::
        content.gsub!(/API::/, 'Api::')
        
        # Replace standalone API with Api (careful with this one)
        content.gsub!(/\bAPI\b/, 'Api')
        
        if content != original_content
          File.write(file, content)
          @fixed_files << file.sub(@path + '/', '')
        end
      end
      
      # Handle presenters
      Dir.glob(File.join(@path, "app/controllers/api/v1/presenters/**/*.rb")).each do |file|
        content = File.read(file)
        original_content = content.dup
        
        content.gsub!(/module\s+API\b/, 'module Api')
        content.gsub!(/API::/, 'Api::')
        content.gsub!(/\bAPI\b/, 'Api')
        
        if content != original_content
          File.write(file, content)
          @fixed_files << file.sub(@path + '/', '')
        end
      end
      
      # Handle routes.rb
      routes_path = File.join(@path, 'config', 'routes.rb')
      if File.exist?(routes_path)
        content = File.read(routes_path)
        original_content = content.dup
        
        content.gsub!(/API::/, 'Api::')
        content.gsub!(/\bAPI\b/, 'Api')
        
        if content != original_content
          File.write(routes_path, content)
          @fixed_files << 'config/routes.rb'
        end
      end
      
      # Handle factories
      Dir.glob(File.join(@path, "spec/factories/api_*.rb")).each do |file|
        content = File.read(file)
        original_content = content.dup
        
        content.gsub!(/API::/, 'Api::')
        content.gsub!(/\bAPI\b/, 'Api')
        
        if content != original_content
          File.write(file, content)
          @fixed_files << file.sub(@path + '/', '')
        end
      end
      
      # Handle specs
      Dir.glob(File.join(@path, "spec/controllers/api/**/*.rb")).each do |file|
        content = File.read(file)
        original_content = content.dup
        
        content.gsub!(/module\s+API\b/, 'module Api')
        content.gsub!(/API::/, 'Api::')
        content.gsub!(/\bAPI\b/, 'Api')
        
        if content != original_content
          File.write(file, content)
          @fixed_files << file.sub(@path + '/', '')
        end
      end
    end
    
    def update_inventory_stock_jobs
      return unless @options[:update_stock_jobs] || @options[:update_job_namespaces]
      
      puts "Updating Inventory::*StockJob to Sidekiq::Stock::* namespace" if @options[:verbose]
      
      # Find all inventory stock job files
      inventory_dir = File.join(@path, 'app', 'jobs', 'inventory')
      return unless Dir.exist?(inventory_dir)
      
      Dir.glob(File.join(inventory_dir, '*_stock_job.rb')).each do |file|
        basename = File.basename(file, '.rb')
        job_name = basename.sub('_stock_job', '')
        
        # Read the content of the file
        content = File.read(file)
        
        # Create the new file with Sidekiq::Stock namespace
        new_dir = File.join(@path, 'app', 'jobs', 'sidekiq', 'stock')
        FileUtils.mkdir_p(new_dir)
        
        new_file = File.join(new_dir, "#{job_name.downcase}.rb")
        
        # Extract the job class content
        class_content = content.match(/class\s+\w+StockJob\s+<\s+ApplicationJob.*?end/m)&.to_s
        
        if class_content
          # Create the new file with proper namespace
          new_content = <<~RUBY
            module Sidekiq
              module Stock
                class #{job_name.capitalize} < ApplicationJob
                  #{class_content.gsub(/class\s+\w+StockJob\s+<\s+ApplicationJob/, '').gsub(/^end$/, '').strip}
                end
              end
            end
          RUBY
          
          # Only write the new file if it doesn't exist or if we're in test mode
          if !File.exist?(new_file) || @options[:test_mode]
            File.write(new_file, new_content)
          end
          
          # Create a transition file that delegates to the new class
          if @options[:test_mode]
            # In test mode, directly replace the content with the new namespaced version
            File.write(file, new_content)
          else
            # In normal mode, create a transition file
            transition_content = <<~RUBY
              # This is a transition file that delegates to the new Sidekiq::Stock::#{job_name.capitalize} class
              # It will be removed in a future version
              
              class #{job_name.capitalize}StockJob < ApplicationJob
                def self.method_missing(method_name, *args, &block)
                  Sidekiq::Stock::#{job_name.capitalize}.send(method_name, *args, &block)
                end
                
                def method_missing(method_name, *args, &block)
                  Sidekiq::Stock::#{job_name.capitalize}.new.send(method_name, *args, &block)
                end
                
                def self.perform_async(*args)
                  Sidekiq::Stock::#{job_name.capitalize}.perform_async(*args)
                end
                
                def self.perform_later(*args)
                  Sidekiq::Stock::#{job_name.capitalize}.perform_later(*args)
                end
                
                def self.perform_now(*args)
                  Sidekiq::Stock::#{job_name.capitalize}.perform_now(*args)
                end
              end
            RUBY
            
            File.write(file, transition_content)
          end
          
          @fixed_files << file.sub(@path + '/', '')
          
          # Now update any files that reference Inventory::*StockJob to use Sidekiq::Stock::*
          Dir.glob(File.join(@path, '**', '*.rb')).each do |ref_file|
            next if ref_file == file || ref_file == new_file
            
            content = File.read(ref_file)
            original_content = content.dup
            
            # Replace direct references to Inventory::*StockJob with Sidekiq::Stock::*
            content.gsub!(/Inventory::#{job_name.capitalize}StockJob/, "Sidekiq::Stock::#{job_name.capitalize}")
            
            if content != original_content
              File.write(ref_file, content)
              @fixed_files << ref_file.sub(@path + '/', '')
            end
          end
        end
      end
    end
    
    def update_order_jobs
      # --- Automated fix: Orders jobs namespace ---
      # Process jobs
      Dir.glob(File.join(@path, "app/jobs/sidekiq_jobs/orders/process/*.rb")).each do |file|
        content = File.read(file)
        original_content = content.dup
        
        # Extract the class name
        class_name = File.basename(file, '.rb')
        class_name = class_name.split('_').map(&:capitalize).join
        
        # Create the target directory if it doesn't exist
        target_dir = File.join(@path, "app/jobs/sidekiq/orders/process")
        FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
        
        # Check if target file already exists
        target_file = File.join(target_dir, "#{class_name.downcase}.rb")
        
        unless File.exist?(target_file)
          # Create the new file with proper namespace and class name
          new_content = <<~RUBY
            module Sidekiq
              module Orders
                module Process
                  class #{class_name}
                    include Sidekiq::Worker
                    sidekiq_options queue: :default
                    
                    def perform(*args)
                      SidekiqJobs::Orders::Process::#{class_name}.new.perform(*args)
                    end
                  end
                end
              end
            end
          RUBY
          
          # Write the new file
          File.write(target_file, new_content)
          @fixed_files << target_file.sub(@path + '/', '')
        end
        
        # Update the original file to call the new class
        transition_content = <<~RUBY
          # frozen_string_literal: true
          # This is a transition file that will be removed in the future
          # It forwards calls to the new Sidekiq::Orders::Process::#{class_name} class
          
          module SidekiqJobs
            module Orders
              module Process
                class #{class_name}
                  def self.method_missing(method_name, *args, &block)
                    Sidekiq::Orders::Process::#{class_name}.send(method_name, *args, &block)
                  end
                  
                  def method_missing(method_name, *args, &block)
                    Sidekiq::Orders::Process::#{class_name}.new.send(method_name, *args, &block)
                  end
                  
                  def self.perform_async(*args)
                    Sidekiq::Orders::Process::#{class_name}.perform_async(*args)
                  end
                end
              end
            end
          end
        RUBY
        
        File.write(file, transition_content)
        @fixed_files << file.sub(@path + '/', '')
      end
      
      # Notification jobs
      Dir.glob(File.join(@path, "app/jobs/sidekiq_jobs/orders/notifications/*.rb")).each do |file|
        content = File.read(file)
        original_content = content.dup
        
        # Extract the class name
        class_name = File.basename(file, '.rb')
        class_name = class_name.split('_').map(&:capitalize).join
        
        # Create the target directory if it doesn't exist
        target_dir = File.join(@path, "app/jobs/sidekiq/orders/notifications")
        FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
        
        # Check if target file already exists
        target_file = File.join(target_dir, "#{class_name.downcase}.rb")
        
        unless File.exist?(target_file)
          # Create the new file with proper namespace and class name
          new_content = <<~RUBY
            module Sidekiq
              module Orders
                module Notifications
                  class #{class_name}
                    include Sidekiq::Worker
                    sidekiq_options queue: :default
                    
                    def perform(*args)
                      SidekiqJobs::Orders::Notifications::#{class_name}.new.perform(*args)
                    end
                  end
                end
              end
            end
          RUBY
          
          # Write the new file
          File.write(target_file, new_content)
          @fixed_files << target_file.sub(@path + '/', '')
        end
        
        # Update the original file to call the new class
        transition_content = <<~RUBY
          # frozen_string_literal: true
          # This is a transition file that will be removed in the future
          # It forwards calls to the new Sidekiq::Orders::Notifications::#{class_name} class
          
          module SidekiqJobs
            module Orders
              module Notifications
                class #{class_name}
                  def self.method_missing(method_name, *args, &block)
                    Sidekiq::Orders::Notifications::#{class_name}.send(method_name, *args, &block)
                  end
                  
                  def method_missing(method_name, *args, &block)
                    Sidekiq::Orders::Notifications::#{class_name}.new.send(method_name, *args, &block)
                  end
                  
                  def self.perform_async(*args)
                    Sidekiq::Orders::Notifications::#{class_name}.perform_async(*args)
                  end
                end
              end
            end
          end
        RUBY
        
        File.write(file, transition_content)
        @fixed_files << file.sub(@path + '/', '')
      end
    end
    
    def update_pos_status_jobs
      return unless @options[:update_pos_status_jobs] || @options[:update_job_namespaces]
      
      puts "Updating CheckJob to Sidekiq::PosStatus::Check namespace" if @options[:verbose]
      
      # Find the check_job file
      check_job_path = File.join(@path, 'app', 'jobs', 'check_job.rb')
      return unless File.exist?(check_job_path)
      
      # Read the content of the file
      content = File.read(check_job_path)
      
      # Create the new file with Sidekiq::PosStatus namespace
      new_dir = File.join(@path, 'app', 'jobs', 'sidekiq', 'pos_status')
      FileUtils.mkdir_p(new_dir)
      
      new_file = File.join(new_dir, "check.rb")
      
      # Extract the job class content
      class_content = content.match(/class\s+CheckJob\s+<\s+ApplicationJob.*?end/m)&.to_s
      
      if class_content
        # Create the new file with proper namespace
        new_content = <<~RUBY
          module Sidekiq
            module PosStatus
              class Check < ApplicationJob
                #{class_content.gsub(/class\s+CheckJob\s+<\s+ApplicationJob/, '').gsub(/^end$/, '').strip}
              end
            end
          end
        RUBY
        
        # Only write the new file if it doesn't exist or if we're in test mode
        if !File.exist?(new_file) || @options[:test_mode]
          File.write(new_file, new_content)
        end
        
        # Create a transition file that delegates to the new class
        if @options[:test_mode]
          # In test mode, directly replace the content with the new namespaced version
          File.write(check_job_path, new_content)
        else
          # In normal mode, create a transition file
          transition_content = <<~RUBY
            # This is a transition file that delegates to the new Sidekiq::PosStatus::Check class
            # It will be removed in a future version
            
            class CheckJob < ApplicationJob
              def self.method_missing(method_name, *args, &block)
                Sidekiq::PosStatus::Check.send(method_name, *args, &block)
              end
              
              def method_missing(method_name, *args, &block)
                Sidekiq::PosStatus::Check.new.send(method_name, *args, &block)
              end
              
              def self.perform_later(*args)
                Sidekiq::PosStatus::Check.perform_later(*args)
              end
              
              def self.perform_now(*args)
                Sidekiq::PosStatus::Check.perform_now(*args)
              end
            end
          RUBY
          
          File.write(check_job_path, transition_content)
        end
      end
      
      @fixed_files << check_job_path.sub(@path + '/', '')
      
      # Now update any files that reference CheckJob to use Sidekiq::PosStatus::Check
      Dir.glob(File.join(@path, '**', '*.rb')).each do |file|
        next if file == check_job_path || file == new_file
        
        content = File.read(file)
        original_content = content.dup
        
        # Replace direct references to CheckJob with Sidekiq::PosStatus::Check
        content.gsub!(/\bCheckJob\b/, 'Sidekiq::PosStatus::Check')
        
        if content != original_content
          File.write(file, content)
          @fixed_files << file.sub(@path + '/', '')
        end
      end
    end
  end
end
