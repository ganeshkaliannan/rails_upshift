require 'rails_upshift'

# Create a custom plugin for company-specific patterns
RailsUpshift.create_plugin('sidekiq_conventions', 'Enforces Sidekiq job naming conventions') do |plugin|
  # Register patterns to detect
  plugin.register_pattern(
    pattern: /class\s+\w+::\w+Job\s+<\s+ApplicationJob/,
    message: "Consider using Sidekiq namespace pattern (Sidekiq::*::*) for job classes",
    file_pattern: "app/jobs/**/*.rb"
  )
  
  plugin.register_pattern(
    pattern: /module\s+Inventory\s+.*class\s+\w+StockJob/m,
    message: "Consider transitioning from Inventory::*StockJob to Sidekiq::Stock::* namespace",
    file_pattern: "app/jobs/**/*.rb"
  )
  
  # Register fixes
  plugin.register_fix(
    pattern: /module\s+Inventory\s+.*?class\s+(\w+)StockJob(.*?)end\s+end/m,
    replacement: proc do |match|
      class_name = match.match(/class\s+(\w+)StockJob/)[1]
      class_body = match.match(/class.*?\n(.*?)end\s+end/m)[1]
      
      "module Sidekiq\n  module Stock\n    class #{class_name}#{class_body}  end\n  end\nend"
    end
  )
end

# Create a custom plugin for client configuration patterns
RailsUpshift.create_plugin('client_configuration', 'Enforces client configuration conventions') do |plugin|
  # Register patterns to detect
  plugin.register_pattern(
    pattern: /settings\s*=\s*\{[^}]*=>\s*true|settings\s*=\s*\{[^}]*=>\s*false/,
    message: "Boolean values in client configuration settings should be stored as strings: \"true\" or \"false\"",
    file_pattern: "**/*.rb"
  )
  
  plugin.register_pattern(
    pattern: /settings\s*=\s*\{[^}]*:[a-zA-Z_]+\s*=>/,
    message: "Use string keys (not symbols) in client configuration settings",
    file_pattern: "**/*.rb"
  )
  
  # Register fixes
  plugin.register_fix(
    pattern: /(settings\s*=\s*\{[^}]*:)([a-zA-Z_]+)(\s*=>)/,
    replacement: '\1"\2"\3'
  )
  
  plugin.register_fix(
    pattern: /(settings\s*=\s*\{[^}]*=>\s*)(true|false)(\s*[,}])/,
    replacement: '\1"\2"\3'
  )
end

# Create a custom plugin for API module naming
RailsUpshift.create_plugin('api_module_naming', 'Enforces API module naming conventions') do |plugin|
  # Register patterns to detect
  plugin.register_pattern(
    pattern: /module\s+API\b/,
    message: "Module named 'API' should be renamed to 'Api' for Rails autoloading",
    file_pattern: "app/{controllers,models}/**/*.rb"
  )
  
  plugin.register_pattern(
    pattern: /API::/,
    message: "Reference to 'API::' module should be updated to 'Api::' for Rails autoloading",
    file_pattern: "**/*.rb"
  )
  
  # Register fixes
  plugin.register_fix(
    pattern: /module\s+API\b/,
    replacement: 'module Api'
  )
  
  plugin.register_fix(
    pattern: /API::/,
    replacement: 'Api::'
  )
end

puts "Custom plugins registered successfully!"
puts "Available plugins:"
RailsUpshift::PluginManager.instance.all.each do |plugin|
  puts "- #{plugin.name}: #{plugin.description}"
end
