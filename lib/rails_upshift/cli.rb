require 'optparse'
require 'colorize'

module RailsUpshift
  class CLI
    attr_reader :options, :path

    def initialize(args)
      @args = args
      @options = {
        dry_run: false,
        safe_mode: true,
        verbose: false,
        update_gems: false,
        update_configs: false,
        update_form_helpers: false,
        update_job_namespaces: false
      }
      @path = Dir.pwd
      parse_options
    end

    def run
      if @options[:help]
        puts @parser
        return 0
      end

      if @options[:version]
        puts "RailsUpshift version #{RailsUpshift::VERSION}"
        return 0
      end

      unless File.directory?(@path)
        puts "Error: #{@path} is not a valid directory".red
        return 1
      end

      unless rails_app?
        puts "Error: #{@path} does not appear to be a Rails application".red
        return 1
      end

      if @options[:analyze_only]
        analyze
      else
        upgrade
      end

      return 0
    end

    private

    def parse_options
      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: rails_upshift [options] [path]"

        opts.on("-a", "--analyze", "Only analyze, don't fix issues") do
          @options[:analyze_only] = true
        end

        opts.on("-d", "--dry-run", "Don't make any changes, just report what would be done") do
          @options[:dry_run] = true
        end

        opts.on("--unsafe", "Allow potentially unsafe fixes") do
          @options[:safe_mode] = false
        end

        opts.on("-v", "--verbose", "Show more detailed output") do
          @options[:verbose] = true
        end

        opts.on("-t", "--target VERSION", "Target Rails version (e.g., 6.1.0)") do |version|
          @options[:target_version] = version
        end

        opts.on("-g", "--update-gems", "Update Gemfile for target Rails version") do
          @options[:update_gems] = true
        end

        opts.on("-c", "--update-configs", "Update configuration files for target Rails version") do
          @options[:update_configs] = true
        end

        opts.on("-f", "--update-form-helpers", "Update form helpers (form_for to form_with)") do
          @options[:update_form_helpers] = true
        end

        opts.on("-j", "--update-job-namespaces", "Update Sidekiq job namespaces to follow conventions") do
          @options[:update_job_namespaces] = true
        end

        opts.on("--version", "Show version") do
          @options[:version] = true
        end

        opts.on("-h", "--help", "Show this help message") do
          @options[:help] = true
        end
      end

      begin
        @parser.parse!(@args)
        @path = @args.shift || Dir.pwd
      rescue OptionParser::InvalidOption => e
        puts "Error: #{e.message}".red
        puts @parser
        exit 1
      end
    end

    def rails_app?
      # Check if this looks like a Rails app
      File.exist?(File.join(@path, 'config', 'application.rb')) &&
        File.exist?(File.join(@path, 'config', 'environment.rb'))
    end

    def analyze
      puts "Analyzing Rails application in #{@path}...".yellow
      target_version = @options[:target_version] ? "for Rails #{@options[:target_version]}" : ""
      puts "Target version: #{target_version}".yellow if target_version.length > 0
      
      issues = RailsUpshift.analyze(@path)
      
      if issues.empty?
        puts "No issues found! Your Rails app looks good.".green
      else
        puts "\nFound #{issues.size} potential issues:".yellow
        
        # Group issues by category
        categories = {
          'ActiveRecord' => [],
          'ActiveStorage' => [],
          'ActiveJob' => [],
          'Time' => [],
          'URL' => [],
          'Gemfile' => [],
          'Configuration' => [],
          'Sidekiq' => [],
          'Client Configuration' => [],
          'API Module' => [],
          'DoorDash' => [],
          'Other' => []
        }
        
        issues.each do |issue|
          case issue[:message]
          when /ActiveRecord|find_by|scoped|where/
            categories['ActiveRecord'] << issue
          when /ActiveStorage|attached/
            categories['ActiveStorage'] << issue
          when /ActiveJob|perform_later/
            categories['ActiveJob'] << issue
          when /Time\.now|DateTime\.now|Date\.today/
            categories['Time'] << issue
          when /URI\.escape|CGI\.escape/
            categories['URL'] << issue
          when /Gemfile/
            categories['Gemfile'] << issue
          when /config\./
            categories['Configuration'] << issue
          when /Sidekiq|namespace|Inventory::|CheckJob/
            categories['Sidekiq'] << issue
          when /client configuration|settings|boolean values/i
            categories['Client Configuration'] << issue
          when /API::|module.*API/
            categories['API Module'] << issue
          when /DoorDash|doordash|webhook/i
            categories['DoorDash'] << issue
          else
            categories['Other'] << issue
          end
        end
        
        # Display issues by category
        categories.each do |category, category_issues|
          next if category_issues.empty?
          
          puts "\n#{category} Issues:".cyan
          category_issues.group_by { |i| i[:file] }.each do |file, file_issues|
            puts "  #{file}:".cyan
            file_issues.each do |issue|
              puts "    - #{issue[:message]}".yellow
            end
          end
        end
        
        puts "\nRun without --analyze flag to automatically fix these issues.".green
        puts "Use --update-gems to update your Gemfile for the target Rails version.".green
        puts "Use --update-configs to update your configuration files.".green
        puts "Use --update-job-namespaces to update Sidekiq job namespaces.".green
      end
    end

    def upgrade
      puts "Upgrading Rails application in #{@path}...".yellow
      target_version = @options[:target_version] ? "to Rails #{@options[:target_version]}" : ""
      puts "Target version: #{target_version}".yellow if target_version.length > 0
      puts "Dry run mode, no changes will be made.".blue if @options[:dry_run]
      
      result = RailsUpshift.upgrade(@path, @options)
      
      if result[:issues].empty?
        puts "No issues found! Your Rails app looks good.".green
      else
        puts "\nFound #{result[:issues].size} potential issues.".yellow
        
        if result[:fixed_files].empty?
          puts "No files were automatically fixed.".yellow
        else
          puts "Automatically fixed #{result[:fixed_files].size} files:".green
          
          # Group fixed files by type
          fixed_by_type = {
            'Ruby Files' => result[:fixed_files].select { |f| f.end_with?('.rb') && !f.start_with?('config/') && !f.include?('/jobs/') && f != 'Gemfile' },
            'View Templates' => result[:fixed_files].select { |f| f.end_with?('.erb', '.haml', '.slim') },
            'Configuration' => result[:fixed_files].select { |f| f.start_with?('config/') },
            'Job Files' => result[:fixed_files].select { |f| f.include?('/jobs/') },
            'Gemfile' => result[:fixed_files].select { |f| f == 'Gemfile' }
          }
          
          fixed_by_type.each do |type, files|
            next if files.empty?
            
            puts "  #{type}:".green
            files.each do |file|
              puts "    - #{file}".green
            end
          end
        end
        
        remaining = result[:issues].size - result[:fixed_files].size
        if remaining > 0
          puts "\n#{remaining} issues may require manual intervention:".yellow
          
          # Group remaining issues by category
          remaining_issues = result[:issues].reject { |i| result[:fixed_files].include?(i[:file]) }
          categories = {
            'ActiveRecord' => [],
            'ActiveStorage' => [],
            'ActiveJob' => [],
            'Time' => [],
            'URL' => [],
            'Gemfile' => [],
            'Configuration' => [],
            'Sidekiq' => [],
            'Client Configuration' => [],
            'API Module' => [],
            'DoorDash' => [],
            'Other' => []
          }
          
          remaining_issues.each do |issue|
            case issue[:message]
            when /ActiveRecord|find_by|scoped|where/
              categories['ActiveRecord'] << issue
            when /ActiveStorage|attached/
              categories['ActiveStorage'] << issue
            when /ActiveJob|perform_later/
              categories['ActiveJob'] << issue
            when /Time\.now|DateTime\.now|Date\.today/
              categories['Time'] << issue
            when /URI\.escape|CGI\.escape/
              categories['URL'] << issue
            when /Gemfile/
              categories['Gemfile'] << issue
            when /config\./
              categories['Configuration'] << issue
            when /Sidekiq|namespace|Inventory::|CheckJob/
              categories['Sidekiq'] << issue
            when /client configuration|settings|boolean values/i
              categories['Client Configuration'] << issue
            when /API::|module.*API/
              categories['API Module'] << issue
            when /DoorDash|doordash|webhook/i
              categories['DoorDash'] << issue
            else
              categories['Other'] << issue
            end
          end
          
          # Display remaining issues by category
          categories.each do |category, category_issues|
            next if category_issues.empty?
            
            puts "\n  #{category} Issues:".yellow
            category_issues.group_by { |i| i[:file] }.each do |file, file_issues|
              puts "    #{file}:".yellow
              file_issues.each do |issue|
                puts "      - #{issue[:message]}".yellow
              end
            end
          end
        end
        
        puts "\nNext steps:".green
        puts "  1. Run tests to verify the changes work correctly".green
        puts "  2. Review manual intervention issues".green
        puts "  3. Update your Gemfile dependencies if needed".green
        puts "  4. Run 'bundle install' to install updated dependencies".green
        puts "  5. Run 'bin/rails app:update' to update Rails configuration files".green
      end
    end
  end
end
