# RailsUpshift

A comprehensive tool to help upgrade Rails applications to newer versions by automatically identifying and fixing common upgrade issues.

## Features

- Analyzes Rails applications for version-specific upgrade issues
- Automatically fixes many common deprecated patterns
- Updates Gemfile dependencies for target Rails version
- Updates configuration files for compatibility
- Provides detailed reports of issues that require manual intervention
- Supports upgrading to Rails 5, 6, and 7
- Fixes codebase-specific patterns like Sidekiq jobs, client configurations, and API modules
- **NEW**: Plugin system for extending with custom patterns

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rails_upshift'
```

And then execute:

```
$ bundle
```

Or install it yourself as:

```
$ gem install rails_upshift
```

## Usage

### Analyzing Your Application

To analyze your Rails application for upgrade issues, run:

```
bundle exec rails_upshift --analyze .
```

This command will scan your current directory for Rails upgrade issues and provide a detailed report.

### Upgrading Your Application

To automatically fix common upgrade issues in your Rails app:

```
bundle exec rails_upshift .
```

To upgrade and target a specific Rails version (e.g., Rails 7.0.0):

```
bundle exec rails_upshift --target 7.0.0 .
```

Add `--dry-run` to preview changes without making them:

```
bundle exec rails_upshift --target 7.0.0 --dry-run .
```

### Options

- `--analyze`, `-a`: Only analyze, don't fix issues
- `--target VERSION`, `-t VERSION`: Target Rails version (e.g., 6.1.0)
- `--dry-run`, `-d`: Don't make any changes, just report what would be done
- `--update-gems`, `-g`: Update Gemfile for target Rails version
- `--update-configs`, `-c`: Update configuration files for target Rails version
- `--update-form-helpers`, `-f`: Update form helpers (form_for to form_with)
- `--update-job-namespaces`, `-j`: Update Sidekiq job namespaces to follow conventions
- `--unsafe`: Allow potentially unsafe fixes
- `--verbose`, `-v`: Show more detailed output
- `--version`: Show version
- `--help`, `-h`: Show help message

## What Gets Fixed

RailsUpshift can automatically fix many common issues when upgrading Rails, including:

### ActiveRecord Changes
- Deprecated dynamic finders (`find_by_*`, `find_or_create_by_*`)
- Deprecated scoped methods
- String conditions in where clauses
- Inefficient query patterns

### View and Helper Changes
- Deprecated URL helpers
- Form helper updates (form_for → form_with)
- JavaScript helper deprecations

### Time Handling
- Time.now → Time.current
- DateTime.now → Time.current
- Date.today → Time.current.to_date

### URL Encoding
- URI.escape → CGI.escape
- URI.unescape → CGI.unescape
- Adding .to_s to CGI.escape for safer handling

### Collection Validation
- Adding .reject(&:blank?).present? for meaningful content validation
- Proper handling of empty collections

### Keyword Arguments
- Adding double splat operator (**) when merging hashes for keyword arguments
- Converting complex mailer methods to use params hash pattern

### Sidekiq Job Namespaces
- Converting to Sidekiq::* namespace pattern
- Transitioning from legacy job naming conventions
- Updating POS status jobs to follow conventions

### Client Configuration
- Storing boolean values as strings ("true"/"false")
- Using string keys instead of symbols
- Adding proper PostgreSQL casting for boolean settings

### API Module Naming
- Renaming API module to Api for Rails autoloading
- Updating API:: references to Api::

### Configuration Updates
- Adding config.load_defaults
- Updating DNS rebinding protection
- Asset pipeline configuration

### Gemfile Updates
- Updating Rails version
- Replacing deprecated gems
- Ensuring proper Ruby version

## Plugin System

RailsUpshift includes a powerful plugin system that allows you to extend the analyzer and upgrader with custom patterns specific to your codebase. This is especially useful for teams with established coding conventions or legacy patterns.

```ruby
# my_custom_plugin.rb
require 'rails_upshift'

RailsUpshift.create_plugin('my_plugin', 'My custom patterns') do |plugin|
  plugin.register_pattern(
    pattern: /custom_method\(.*\)/,
    message: "The custom_method is deprecated - use new_method instead",
    file_pattern: "**/*.rb"
  )
  
  plugin.register_fix(
    pattern: /custom_method\((.*)\)/,
    replacement: 'new_method(\1)'
  )
end
```

See [Plugin Documentation](docs/plugins.md) for more details.

## Version-Specific Guides

For detailed guidance on upgrading between specific Rails versions:

- [Rails 5 to 6 Upgrade Guide](guides/rails_5_to_6_upgrade_guide.md)
- [Rails 6 to 7 Upgrade Guide](guides/rails_6_to_7_upgrade_guide.md)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/rails_upshift.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
