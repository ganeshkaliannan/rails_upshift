module RailsUpshift
  class Analyzer
    attr_reader :path, :issues, :target_version

    def initialize(path, target_version = nil)
      @path = path
      @target_version = target_version || detect_target_version
      @issues = []
    end

    def analyze
      find_deprecated_methods
      find_deprecated_constants
      find_http_authentication_concerns
      find_unsafe_json_parsing
      find_deprecated_url_helpers
      find_active_record_issues
      find_active_storage_issues
      find_active_job_issues
      find_time_related_issues
      find_url_encoding_issues
      find_collection_validation_issues
      find_keyword_args_issues
      find_module_naming_issues
      find_gemfile_issues
      find_config_issues
      find_sidekiq_namespace_issues
      find_client_configuration_issues
      find_api_module_issues
      # DoorDash checks removed
      
      @issues
    end

    def scan_for_pattern(pattern:, message:, file_pattern:)
      Dir.glob(File.join(@path, file_pattern)).each do |file|
        next if File.directory?(file)
        
        begin
          content = File.read(file)
          if content.match?(pattern)
            relative_path = file.sub("#{@path}/", '')
            @issues << {
              file: relative_path,
              message: message,
              pattern: pattern.source
            }
          end
        rescue => e
          puts "Error scanning file #{file}: #{e.message}"
        end
      end
    end

    private

    def detect_target_version
      # Try to detect target Rails version from Gemfile or gemspec
      gemfile_path = File.join(@path, 'Gemfile')
      if File.exist?(gemfile_path)
        content = File.read(gemfile_path)
        if content =~ /gem\s+['"]rails['"],\s+['"]~>\s+([\d\.]+)['"]/
          return $1
        elsif content =~ /gem\s+['"]rails['"],\s+['"]>=\s+([\d\.]+)['"]/
          return $1
        end
      end
      
      # Default to latest if we can't detect
      "7.0.0"
    end

    def find_deprecated_methods
      # Scan for deprecated methods like update_attributes, success?, etc.
      scan_for_pattern(
        pattern: /\.update_attributes[!\(]/,
        message: "Deprecated method 'update_attributes' - use 'update' instead",
        file_pattern: "**/*.rb"
      )
      
      scan_for_pattern(
        pattern: /\.success\?/,
        message: "Deprecated method 'success?' - use 'successful?' instead",
        file_pattern: "**/*.rb"
      )
      
      # Rails 5+ deprecated finder methods
      scan_for_pattern(
        pattern: /\.find_or_initialize_by_([a-zA-Z_]+)\b/,
        message: "Deprecated finder method 'find_or_initialize_by_*' - use 'find_or_initialize_by(attribute: value)' instead",
        file_pattern: "**/*.rb"
      )
      
      scan_for_pattern(
        pattern: /\.find_or_create_by_([a-zA-Z_]+)\b/,
        message: "Deprecated finder method 'find_or_create_by_*' - use 'find_or_create_by(attribute: value)' instead",
        file_pattern: "**/*.rb"
      )
      
      # Rails 6+ deprecated methods
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        scan_for_pattern(
          pattern: /\.page\(params\[:page\]\)/,
          message: "Potential pagination issue - ensure proper escaping with 'params.fetch(:page, 1)' for safety",
          file_pattern: "**/*.rb"
        )
      end
      
      # Rails 7+ deprecated methods
      if Gem::Version.new(@target_version) >= Gem::Version.new("7.0.0")
        scan_for_pattern(
          pattern: /\.pluck\(:id\)\.include\?/,
          message: "Inefficient query pattern - consider using 'exists?' instead of 'pluck(:id).include?'",
          file_pattern: "**/*.rb"
        )
      end
    end

    def find_deprecated_constants
      # Scan for deprecated constants like MimeType, HttpAuthentication::Basic, etc.
      scan_for_pattern(
        pattern: /Mime::SET|Mime::Type/,
        message: "Deprecated constant 'Mime::SET/Mime::Type' - use 'Mime::LOOKUP' or 'Mime.fetch' instead",
        file_pattern: "**/*.rb"
      )
      
      # Rails 5+ deprecated constants
      scan_for_pattern(
        pattern: /ActionDispatch::ParamsParser/,
        message: "Deprecated constant 'ActionDispatch::ParamsParser' - this middleware was removed",
        file_pattern: "**/*.rb"
      )
      
      # Rails 6+ deprecated constants
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        scan_for_pattern(
          pattern: /ActionView::TestCase::Behavior/,
          message: "Deprecated constant 'ActionView::TestCase::Behavior' - use 'ActionView::TestCase' directly",
          file_pattern: "**/*.rb"
        )
      end
    end

    def find_http_authentication_concerns
      # Scan for HTTP authentication concerns
      scan_for_pattern(
        pattern: /ActionController::HttpAuthentication::(Basic|Digest|Token)/,
        message: "HTTP Authentication module usage may need updates",
        file_pattern: "**/*.rb"
      )
    end

    def find_unsafe_json_parsing
      # Scan for unsafe JSON parsing methods
      scan_for_pattern(
        pattern: /JSON\.parse\([^,]+\)/,
        message: "Consider using 'JSON.parse(json, symbolize_names: true)' for safer parsing",
        file_pattern: "**/*.rb"
      )
    end

    def find_deprecated_url_helpers
      # Scan for deprecated URL helpers
      scan_for_pattern(
        pattern: /\b(url_for|link_to|redirect_to|form_for|form_tag)\b.*:back\b/,
        message: "Deprecated ':back' argument - use 'redirect_back' or 'link_back' instead",
        file_pattern: "**/*.{rb,erb,haml,slim}"
      )
      
      # Rails 5+ deprecated form helpers
      scan_for_pattern(
        pattern: /\bform_tag\b|\bform_for\b/,
        message: "Deprecated form helpers - consider using 'form_with' instead",
        file_pattern: "**/*.{rb,erb,haml,slim}"
      )
      
      # Rails 6+ deprecated URL helpers
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        scan_for_pattern(
          pattern: /\bbutton_to_function\b|\blink_to_function\b/,
          message: "Deprecated JavaScript helpers - use unobtrusive JavaScript instead",
          file_pattern: "**/*.{rb,erb,haml,slim}"
        )
      end
    end

    def find_active_record_issues
      # Scan for ActiveRecord issues
      scan_for_pattern(
        pattern: /\.find_by_[a-zA-Z_]+\b/,
        message: "Dynamic finders (find_by_*) are deprecated - use 'find_by(column: value)' instead",
        file_pattern: "**/*.rb"
      )
      
      scan_for_pattern(
        pattern: /\.scoped\b/,
        message: "Deprecated 'scoped' method - use 'all' instead",
        file_pattern: "**/*.rb"
      )
      
      # Rails 5+ ActiveRecord changes
      scan_for_pattern(
        pattern: /default_scope\s+[^{]*\bwhere\b/,
        message: "default_scope with where conditions can cause issues - consider refactoring",
        file_pattern: "**/*.rb"
      )
      
      # Rails 6+ ActiveRecord changes
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        scan_for_pattern(
          pattern: /\.update_all\([^)]*created_at|\.update_all\([^)]*updated_at/,
          message: "update_all bypasses callbacks and validations - ensure this is intended",
          file_pattern: "**/*.rb"
        )
      end
      
      # Rails 7+ ActiveRecord changes
      if Gem::Version.new(@target_version) >= Gem::Version.new("7.0.0")
        scan_for_pattern(
          pattern: /\.where\(["']([^=]+)=["']/,
          message: "String conditions in where() are deprecated - use hash conditions instead",
          file_pattern: "**/*.rb"
        )
      end
    end

    def find_active_storage_issues
      # Scan for ActiveStorage issues
      scan_for_pattern(
        pattern: /has_one_attached|has_many_attached/,
        message: "ActiveStorage attachment - ensure dependent: :purge_later is set for proper cleanup",
        file_pattern: "**/*.rb"
      )
      
      # Rails 6+ ActiveStorage changes
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        scan_for_pattern(
          pattern: /include\s+ActiveStorage::Blob::Analyzable/,
          message: "ActiveStorage::Blob::Analyzable was renamed to ActiveStorage::Blob::Analyzable",
          file_pattern: "**/*.rb"
        )
      end
    end

    def find_active_job_issues
      # Scan for ActiveJob issues
      scan_for_pattern(
        pattern: /rescue_from\s+ActiveJob::DeserializationError/,
        message: "Consider handling ActiveJob::DeserializationError for better error handling",
        file_pattern: "**/*.rb"
      )
      
      # Rails 6+ ActiveJob changes
      if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        scan_for_pattern(
          pattern: /\.perform_later\b(?!.*wait)/,
          message: "Consider using wait options with perform_later for better job scheduling",
          file_pattern: "**/*.rb"
        )
      end
    end

    def find_time_related_issues
      # Scan for Time.now usage instead of Time.current
      scan_for_pattern(
        pattern: /Time\.now/,
        message: "Use Time.current instead of Time.now for proper timezone handling",
        file_pattern: "**/*.rb"
      )
      
      scan_for_pattern(
        pattern: /DateTime\.now/,
        message: "Use Time.current instead of DateTime.now for proper timezone handling",
        file_pattern: "**/*.rb"
      )
      
      scan_for_pattern(
        pattern: /Date\.today/,
        message: "Consider using Time.current.to_date instead of Date.today for timezone consistency",
        file_pattern: "**/*.rb"
      )
    end

    def find_url_encoding_issues
      # Scan for deprecated URI.escape usage
      scan_for_pattern(
        pattern: /URI\.escape|URI\.unescape/,
        message: "Deprecated URI.escape/unescape - use CGI.escape/unescape instead",
        file_pattern: "**/*.rb"
      )
      
      # Check for missing to_s in CGI.escape
      scan_for_pattern(
        pattern: /CGI\.escape\(([^)]+)\)/,
        message: "Ensure CGI.escape includes .to_s to handle non-string inputs safely",
        file_pattern: "**/*.rb"
      )
    end

    def find_collection_validation_issues
      # Scan for potential collection validation issues
      scan_for_pattern(
        pattern: /\.present\?\s*$/,
        message: "Collection presence check might need .reject(&:blank?).present? for meaningful content validation",
        file_pattern: "**/*.rb"
      )
    end

    def find_keyword_args_issues
      # Scan for potential keyword arguments issues
      scan_for_pattern(
        pattern: /\.merge\([^)]+\)\)(?!\s*\*\*)/,
        message: "Consider using double splat operator (**) when merging hashes for keyword arguments",
        file_pattern: "**/*.rb"
      )
      
      # Check for mailer methods with multiple arguments
      scan_for_pattern(
        pattern: /def\s+\w+\(([^)]{40,})\)/,
        message: "Consider using params hash pattern for mailer methods with multiple parameters",
        file_pattern: "app/mailers/**/*.rb"
      )
    end

    def find_module_naming_issues
      # Scan for module naming that might cause autoloading issues
      scan_for_pattern(
        pattern: /module\s+API\b/,
        message: "Module named 'API' might cause Rails autoloading issues - consider 'Api' instead",
        file_pattern: "**/*.rb"
      )
    end

    def find_gemfile_issues
      gemfile_path = File.join(@path, 'Gemfile')
      return unless File.exist?(gemfile_path)
      
      content = File.read(gemfile_path)
      
      # Check for outdated gems or version constraints
      outdated_gems = {
        'protected_attributes' => "The protected_attributes gem is not compatible with Rails 5+",
        'activerecord-deprecated_finders' => "The activerecord-deprecated_finders gem is not compatible with Rails 5+",
        'rails-controller-testing' => "Ensure rails-controller-testing is properly configured for Rails 5+",
        'coffee-rails' => "The coffee-rails gem is deprecated in Rails 6+",
        'sass-rails' => "Consider using cssbundling-rails in Rails 7+",
        'uglifier' => "Consider using jsbundling-rails in Rails 7+"
      }
      
      outdated_gems.each do |gem_name, message|
        if content =~ /gem\s+['"]#{gem_name}['"]/
          @issues << {
            file: 'Gemfile',
            message: message,
            pattern: gem_name
          }
        end
      end
      
      # Check for proper versioning
      if Gem::Version.new(@target_version) >= Gem::Version.new("7.0.0")
        unless content =~ /ruby\s+['"][23]\./
          @issues << {
            file: 'Gemfile',
            message: "Rails 7 requires Ruby 2.7.0 or newer - specify ruby version in Gemfile",
            pattern: 'ruby version'
          }
        end
      elsif Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
        unless content =~ /ruby\s+['"][23]\./
          @issues << {
            file: 'Gemfile',
            message: "Rails 6 requires Ruby 2.5.0 or newer - specify ruby version in Gemfile",
            pattern: 'ruby version'
          }
        end
      end
    end

    def find_config_issues
      # Check for configuration files that need updates
      config_files = [
        'config/application.rb',
        'config/environments/development.rb',
        'config/environments/production.rb',
        'config/environments/test.rb',
        'config/initializers/new_framework_defaults.rb'
      ]
      
      config_files.each do |config_file|
        full_path = File.join(@path, config_file)
        next unless File.exist?(full_path)
        
        content = File.read(full_path)
        
        # Rails 5+ configuration changes
        if config_file == 'config/application.rb' && !content.include?('config.load_defaults')
          @issues << {
            file: config_file,
            message: "Missing config.load_defaults - add this to set new framework defaults",
            pattern: 'config.load_defaults'
          }
        end
        
        # Rails 6+ configuration changes
        if Gem::Version.new(@target_version) >= Gem::Version.new("6.0.0")
          if config_file == 'config/environments/development.rb' && !content.include?('config.hosts')
            @issues << {
              file: config_file,
              message: "Missing config.hosts configuration - Rails 6+ uses DNS rebinding protection",
              pattern: 'config.hosts'
            }
          end
        end
        
        # Rails 7+ configuration changes
        if Gem::Version.new(@target_version) >= Gem::Version.new("7.0.0")
          if config_file == 'config/environments/production.rb' && content.include?('config.assets.js_compressor = :uglifier')
            @issues << {
              file: config_file,
              message: "Uglifier is not recommended in Rails 7+ - consider using jsbundling-rails",
              pattern: 'config.assets.js_compressor = :uglifier'
            }
          end
        end
      end
    end
    
    def find_sidekiq_namespace_issues
      # Check for Sidekiq job namespace patterns
      scan_for_pattern(
        pattern: /class\s+\w+::\w+Job\s+<\s+ApplicationJob/,
        message: "Consider using Sidekiq namespace pattern (Sidekiq::*::*) for job classes",
        file_pattern: "app/jobs/**/*.rb"
      )
      
      # Check for old Inventory namespace pattern
      scan_for_pattern(
        pattern: /module\s+Inventory\s+.*class\s+\w+StockJob/m,
        message: "Consider transitioning from Inventory::*StockJob to Sidekiq::Stock::* namespace",
        file_pattern: "app/jobs/**/*.rb"
      )
      
      # Check for POS status job namespace
      scan_for_pattern(
        pattern: /class\s+CheckJob\s+<\s+ApplicationJob/,
        message: "Consider using Sidekiq::PosStatus::Check namespace instead of CheckJob",
        file_pattern: "app/jobs/**/*.rb"
      )
    end
    
    def find_client_configuration_issues
      # Check for client configuration settings stored as strings
      scan_for_pattern(
        pattern: /settings\s*=\s*\{[^}]*=>\s*true|settings\s*=\s*\{[^}]*=>\s*false/,
        message: "Boolean values in client configuration settings should be stored as strings: \"true\" or \"false\"",
        file_pattern: "**/*.rb"
      )
      
      # Check for symbol keys in settings
      scan_for_pattern(
        pattern: /settings\s*=\s*\{[^}]*:[a-zA-Z_]+\s*=>/,
        message: "Use string keys (not symbols) in client configuration settings",
        file_pattern: "**/*.rb"
      )
      
      # Check for proper boolean casting in queries
      scan_for_pattern(
        pattern: /where\(["']settings\s*->>\s*['"][^)]*\)/,
        message: "Consider using PostgreSQL cast for boolean settings: (settings ->> 'key')::boolean",
        file_pattern: "**/*.rb"
      )
    end
    
    def find_api_module_issues
      # Check for API module naming
      scan_for_pattern(
        pattern: /module\s+API\b/,
        message: "Module named 'API' should be renamed to 'Api' for Rails autoloading",
        file_pattern: "app/{controllers,models}/**/*.rb"
      )
      
      # Check for API references
      scan_for_pattern(
        pattern: /API::/,
        message: "Reference to 'API::' module should be updated to 'Api::' for Rails autoloading",
        file_pattern: "**/*.rb"
      )
    end
  end
end
