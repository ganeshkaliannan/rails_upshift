# RailsUpshift Plugin System

RailsUpshift includes a powerful plugin system that allows you to extend the analyzer and upgrader with custom patterns specific to your codebase. This is especially useful for teams with established coding conventions or legacy patterns that need to be updated during Rails upgrades.

## Creating a Plugin

To create a plugin, you need to:

1. Create a new Ruby file for your plugin
2. Use the `RailsUpshift.create_plugin` method to define your plugin
3. Register patterns to detect with `register_pattern`
4. Register fixes for those patterns with `register_fix`
5. Require your plugin file before running RailsUpshift

Here's a basic example:

```ruby
# my_custom_plugin.rb
require 'rails_upshift'

RailsUpshift.create_plugin('my_plugin', 'My custom patterns for Rails upgrades') do |plugin|
  # Register a pattern to detect
  plugin.register_pattern(
    pattern: /custom_method\(.*\)/,
    message: "The custom_method is deprecated - use new_method instead",
    file_pattern: "**/*.rb"
  )
  
  # Register a fix for the pattern
  plugin.register_fix(
    pattern: /custom_method\((.*)\)/,
    replacement: 'new_method(\1)'
  )
end
```

## Plugin API

### Creating a Plugin

```ruby
RailsUpshift.create_plugin(name, description) do |plugin|
  # Configure your plugin here
end
```

- `name`: A unique identifier for your plugin
- `description`: A human-readable description of what your plugin does

### Registering Patterns

```ruby
plugin.register_pattern(
  pattern: /regex_pattern/,
  message: "Message to display when pattern is found",
  file_pattern: "**/*.rb",
  version_constraint: ">= 6.0.0" # Optional
)
```

- `pattern`: A regular expression to match in the code
- `message`: The message to display when the pattern is found
- `file_pattern`: A glob pattern to match files to search
- `version_constraint`: Optional version constraint for when this pattern applies

### Registering Fixes

```ruby
plugin.register_fix(
  pattern: /regex_pattern/,
  replacement: 'replacement_string',
  safe: true # Optional, defaults to true
)
```

- `pattern`: A regular expression to match in the code
- `replacement`: A string or proc to replace the matched pattern
- `safe`: Whether the fix is considered safe to apply automatically (defaults to true)

When using a proc for replacement:

```ruby
plugin.register_fix(
  pattern: /complex_pattern(.*?)end/m,
  replacement: proc do |match|
    # Process the match and return the replacement
    match.gsub(/old/, 'new')
  end
)
```

## Using Plugins

To use a plugin, require it before running RailsUpshift:

```bash
# From the command line
ruby -r ./my_custom_plugin.rb -S rails_upshift
```

Or in a Ruby script:

```ruby
require 'rails_upshift'
require './my_custom_plugin'

# Now run RailsUpshift
RailsUpshift.upgrade('/path/to/app', options)
```

## Example Plugins

### Job Namespace Conventions

```ruby
RailsUpshift.create_plugin('job_conventions', 'Enforces job naming conventions') do |plugin|
  # Detect old job naming pattern
  plugin.register_pattern(
    pattern: /class\s+\w+Job\s+<\s+ApplicationJob/,
    message: "Jobs should follow the Sidekiq::Module::Name convention",
    file_pattern: "app/jobs/**/*.rb"
  )
  
  # Fix job naming pattern
  plugin.register_fix(
    pattern: /class\s+(\w+)Job\s+<\s+ApplicationJob(.*?)end/m,
    replacement: proc do |match|
      job_name = match.match(/class\s+(\w+)Job/)[1]
      job_body = match.match(/class.*?\n(.*?)end/m)[1]
      
      module_name = job_name.gsub(/([A-Z])/, '_\1').split('_').reject(&:empty?)[0]
      class_name = job_name.sub(/^#{module_name}/, '')
      
      "module Sidekiq\n  module #{module_name.capitalize}\n    class #{class_name} < ApplicationJob#{job_body}    end\n  end\nend"
    end
  )
end
```

### API Naming Conventions

```ruby
RailsUpshift.create_plugin('api_conventions', 'Enforces API naming conventions') do |plugin|
  # Detect API module naming issues
  plugin.register_pattern(
    pattern: /module\s+API\b/,
    message: "Module named 'API' should be renamed to 'Api' for Rails autoloading",
    file_pattern: "app/{controllers,models}/**/*.rb"
  )
  
  # Fix API module naming
  plugin.register_fix(
    pattern: /module\s+API\b/,
    replacement: 'module Api'
  )
  
  # Fix API references
  plugin.register_fix(
    pattern: /API::/,
    replacement: 'Api::'
  )
end
```

## Best Practices

1. **Start Small**: Begin with a few specific patterns that are common in your codebase
2. **Test Thoroughly**: Always test your plugins on a copy of your codebase first
3. **Use Version Constraints**: If your patterns only apply to certain Rails versions, use version constraints
4. **Be Specific**: Use specific file patterns to limit where your patterns are applied
5. **Use Safe Replacements**: Mark complex transformations as `safe: false` if they might need manual review

## Sharing Plugins

You can share plugins with your team by:

1. Creating a shared repository for your plugins
2. Adding them to your project's `.rails_upshift` directory
3. Creating a gem that includes your plugins

This allows your team to maintain consistent coding standards during Rails upgrades.
