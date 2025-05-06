# Contributing to Rails Upshift

Thank you for your interest in contributing to Rails Upshift! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Codebase Structure](#codebase-structure)
- [Adding New Patterns](#adding-new-patterns)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Style Guide](#style-guide)

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to [ganesh.kaliannan@gmail.com](mailto:ganesh.kaliannan@gmail.com).

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/rails_upshift.git
   cd rails_upshift
   ```
3. Install dependencies:
   ```bash
   bin/setup
   ```
4. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Workflow

1. Make your changes
2. Run the tests to ensure everything works:
   ```bash
   bundle exec rake spec
   ```
3. Add tests for your changes
4. Update documentation as needed
5. Commit your changes with a descriptive commit message
6. Push to your fork and submit a pull request

## Codebase Structure

The Rails Upshift codebase is organized as follows:

```
lib/
├── rails_upshift/
│   ├── analyzer.rb       # Analyzes Rails code for upgrade issues
│   ├── cli.rb            # Command-line interface
│   ├── plugin.rb         # Plugin system for extending functionality
│   ├── upgrader.rb       # Applies fixes to identified issues
│   └── version.rb        # Gem version
├── rails_upshift.rb      # Main entry point
bin/
├── console               # Interactive console for development
├── rails_upshift         # Executable for the gem
└── setup                 # Setup script for development
spec/
└── ...                   # Test files
```

### Core Components

The gem has two main components:

1. **Analyzer**: Scans your codebase to identify potential issues that need to be fixed when upgrading Rails versions.
2. **Upgrader**: Takes the issues identified by the Analyzer and applies fixes to your codebase.

![Simplified Flow Diagram](simplified_diagram_fixed.md)

## Adding New Patterns

To add a new pattern for detection and fixing:

1. Add a detection method in `analyzer.rb`:

```ruby
def find_new_pattern_issues
  scan_for_pattern(
    pattern: /pattern_to_match/,
    message: "Description of the issue and how to fix it",
    file_pattern: "**/*.rb"  # Adjust file pattern as needed
  )
end
```

2. Add the method call to the `analyze` method.

3. Add a fix case in the `fix_issue` method in `upgrader.rb`:

```ruby
when /pattern_to_match/
  content.gsub!(/pattern_to_match/) do |match|
    # Your replacement logic here
    "replacement_pattern"
  end
```

## Testing

We use RSpec for testing. Please add tests for any new functionality or bug fixes:

```bash
bundle exec rspec
```

### Test Coverage

We aim to maintain high test coverage. Please ensure your changes include appropriate tests:

- Unit tests for individual components
- Integration tests for the CLI and overall functionality
- Regression tests for fixed issues

## Pull Request Process

1. Ensure your code passes all tests
2. Update the README.md with details of changes if appropriate
3. Update the version number in `version.rb` following [SemVer](http://semver.org/)
4. The PR will be merged once it receives approval from maintainers

## Style Guide

We follow the [Ruby Style Guide](https://github.com/rubocop/ruby-style-guide) and use RuboCop to enforce it:

```bash
bundle exec rubocop
```

Key style points:
- Use 2 spaces for indentation
- Keep lines under 100 characters
- Use meaningful variable and method names
- Write descriptive comments for complex logic
- Follow Ruby naming conventions:
  - `snake_case` for methods and variables
  - `CamelCase` for classes and modules
  - `SCREAMING_SNAKE_CASE` for constants

## Specialized Patterns

When contributing to specialized patterns like namespace transitions, follow these guidelines:

### API Module Renaming
- Ensure consistent renaming of `API` to `Api` for Rails autoloading
- Update all references to maintain consistency

### Sidekiq Job Namespace Transitions
- Follow the established pattern: `Sidekiq::*::*`
- For stock jobs: `Inventory::*StockJob` → `Sidekiq::Stock::*`
- For POS status: `CheckJob` → `Sidekiq::PosStatus::Check`
- For order processing: `SidekiqJobs::Orders::*` → `Sidekiq::Orders::*`

### Client Configuration
- Ensure boolean values are stored as strings: `"true"` or `"false"`
- Use string keys (not symbols) in settings hashes
- Add proper PostgreSQL casting for boolean settings in queries

Thank you for contributing to Rails Upshift!
