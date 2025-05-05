require "rails_upshift/version"
require "rails_upshift/analyzer"
require "rails_upshift/upgrader"
require "rails_upshift/cli"
require "rails_upshift/plugin"

module RailsUpshift
  class Error < StandardError; end
  
  def self.analyze(path, target_version = nil)
    analyzer = Analyzer.new(path, target_version)
    
    # Apply plugins to analyzer
    PluginManager.instance.apply_to_analyzer(analyzer)
    
    analyzer.analyze
  end

  def self.upgrade(path, options = {})
    analyzer = Analyzer.new(path, options[:target_version])
    issues = analyzer.analyze
    
    upgrader = Upgrader.new(path, issues, options)
    
    # Apply plugins to upgrader
    PluginManager.instance.apply_to_upgrader(upgrader)
    
    upgrader.upgrade
  end
  
  # Register a plugin
  # @param plugin [RailsUpshift::Plugin] the plugin to register
  def self.register_plugin(plugin)
    PluginManager.instance.register(plugin)
  end
  
  # Create and register a new plugin
  # @param name [String] the name of the plugin
  # @param description [String] a description of the plugin
  # @yield [plugin] the plugin to configure
  # @return [RailsUpshift::Plugin] the created plugin
  def self.create_plugin(name, description)
    plugin = Plugin.new(name, description)
    yield plugin if block_given?
    register_plugin(plugin)
    plugin
  end
end
