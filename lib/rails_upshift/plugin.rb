module RailsUpshift
  # Plugin system for RailsUpshift
  # Allows users to extend the analyzer and upgrader with custom patterns
  class Plugin
    attr_reader :name, :description, :patterns, :fixes
    
    def initialize(name, description)
      @name = name
      @description = description
      @patterns = []
      @fixes = {}
    end
    
    # Register a pattern to detect in the analyzer
    # @param pattern [Regexp] the pattern to match
    # @param message [String] the message to display when the pattern is found
    # @param file_pattern [String] the glob pattern to match files
    # @param version_constraint [String] optional version constraint (e.g., '>= 6.0.0')
    def register_pattern(pattern:, message:, file_pattern:, version_constraint: nil)
      @patterns << {
        pattern: pattern,
        message: message,
        file_pattern: file_pattern,
        version_constraint: version_constraint
      }
    end
    
    # Register a fix for a pattern
    # @param pattern [Regexp] the pattern to match
    # @param replacement [String, Proc] the replacement string or a proc that takes the match and returns a string
    # @param safe [Boolean] whether the fix is considered safe
    def register_fix(pattern:, replacement:, safe: true)
      @fixes[pattern.source] = {
        replacement: replacement,
        safe: safe
      }
    end
    
    # Apply the plugin to an analyzer
    # @param analyzer [RailsUpshift::Analyzer] the analyzer to apply the plugin to
    def apply_to_analyzer(analyzer)
      @patterns.each do |pattern_data|
        next if pattern_data[:version_constraint] && 
                !version_matches?(analyzer.target_version, pattern_data[:version_constraint])
        
        analyzer.scan_for_pattern(
          pattern: pattern_data[:pattern],
          message: pattern_data[:message],
          file_pattern: pattern_data[:file_pattern]
        )
      end
    end
    
    # Apply the plugin to an upgrader
    # @param upgrader [RailsUpshift::Upgrader] the upgrader to apply the plugin to
    def apply_to_upgrader(upgrader)
      @fixes.each do |pattern_source, fix_data|
        upgrader.register_fix(
          pattern: Regexp.new(pattern_source),
          replacement: fix_data[:replacement],
          safe: fix_data[:safe]
        )
      end
    end
    
    private
    
    def version_matches?(current_version, constraint)
      operator, version = constraint.split(' ')
      current = Gem::Version.new(current_version)
      target = Gem::Version.new(version)
      
      case operator
      when '>='
        current >= target
      when '>'
        current > target
      when '<='
        current <= target
      when '<'
        current < target
      when '=='
        current == target
      when '~>'
        current >= target && current < Gem::Version.new(version.split('.')[0..1].join('.') + '.999')
      else
        false
      end
    end
  end
  
  # Plugin manager for RailsUpshift
  class PluginManager
    def self.instance
      @instance ||= new
    end
    
    def initialize
      @plugins = {}
    end
    
    # Register a plugin
    # @param plugin [RailsUpshift::Plugin] the plugin to register
    def register(plugin)
      @plugins[plugin.name] = plugin
    end
    
    # Get a plugin by name
    # @param name [String] the name of the plugin
    # @return [RailsUpshift::Plugin, nil] the plugin or nil if not found
    def get(name)
      @plugins[name]
    end
    
    # Get all registered plugins
    # @return [Array<RailsUpshift::Plugin>] all registered plugins
    def all
      @plugins.values
    end
    
    # Apply all plugins to an analyzer
    # @param analyzer [RailsUpshift::Analyzer] the analyzer to apply plugins to
    def apply_to_analyzer(analyzer)
      @plugins.each_value do |plugin|
        plugin.apply_to_analyzer(analyzer)
      end
    end
    
    # Apply all plugins to an upgrader
    # @param upgrader [RailsUpshift::Upgrader] the upgrader to apply plugins to
    def apply_to_upgrader(upgrader)
      @plugins.each_value do |plugin|
        plugin.apply_to_upgrader(upgrader)
      end
    end
  end
end
