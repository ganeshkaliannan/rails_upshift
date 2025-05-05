# Rails 6 to 7 Upgrade Guide

This guide provides a comprehensive overview of upgrading from Rails 6.x to Rails 7.0. RailsUpshift can automatically fix many of these issues, but some will require manual intervention.

## Prerequisites

- Ruby 2.7.0 or newer (Rails 7 requires at least Ruby 2.7.0)
- Bundler 2.0 or newer

## Major Changes in Rails 7

### New JavaScript Approach

Rails 7 moves away from Webpacker to a more modular approach with three options:
- Import maps (default, no build required)
- esbuild (lighter alternative to webpack)
- Webpack (still supported via jsbundling-rails)

### CSS Bundling

Rails 7 introduces cssbundling-rails for CSS processing, supporting:
- Tailwind CSS
- PostCSS
- Sass
- Bootstrap, Bulma, or other frameworks

### Hotwire

Rails 7 integrates Hotwire (Turbo and Stimulus) for building modern web applications without much JavaScript.

### ActiveRecord Improvements

- Adds encryption for attributes
- Adds query logging tags
- Adds asynchronous query loading

## Common Upgrade Issues

### 1. JavaScript Changes

**RailsUpshift can automatically fix:**
- Updating JavaScript configuration files
- Removing Webpacker references in favor of import maps or jsbundling-rails

**Manual steps required:**
- Choose your JavaScript strategy:
  ```bash
  # For import maps (simplest approach)
  rails importmap:install
  
  # For esbuild
  rails javascript:install:esbuild
  
  # For webpack
  rails javascript:install:webpack
  
  # For rollup
  rails javascript:install:rollup
  ```

### 2. CSS Changes

**Manual steps required:**
- Choose your CSS strategy:
  ```bash
  # For Tailwind CSS
  rails css:install:tailwind
  
  # For PostCSS
  rails css:install:postcss
  
  # For Sass
  rails css:install:sass
  
  # For Bootstrap
  rails css:install:bootstrap
  ```

### 3. ActiveRecord Changes

**RailsUpshift can automatically fix:**
- Replacing string conditions in `where()` with hash conditions
- Updating inefficient query patterns like `pluck(:id).include?` to `exists?`

**Manual steps required:**
- Review complex queries that might be affected by the new behavior
- Update any custom SQL that might be affected by the new quoting behavior

### 4. Time Handling

**RailsUpshift can automatically fix:**
- Replacing `Time.now` with `Time.current`
- Replacing `DateTime.now` with `Time.current`
- Replacing `Date.today` with `Time.current.to_date`

### 5. Configuration Changes

**RailsUpshift can automatically fix:**
- Adding `config.load_defaults 7.0` to `config/application.rb`
- Updating asset pipeline configuration

**Manual steps required:**
- Review all deprecation warnings after upgrading
- Update your `config/environments/*.rb` files for new options

### 6. Sidekiq Job Namespaces

**RailsUpshift can automatically fix:**
- Converting to standardized job namespace patterns
- Updating legacy job naming conventions

## Step-by-Step Upgrade Process

1. **Update your Ruby version** to at least 2.7.0

2. **Update your Gemfile**:
   ```ruby
   gem 'rails', '~> 7.0.0'
   ```

3. **Run RailsUpshift**:
   ```bash
   rails_upshift --target 7.0.0 --update-gems --update-configs
   ```

4. **Install dependencies**:
   ```bash
   bundle install
   ```

5. **Update configurations**:
   ```bash
   bin/rails app:update
   ```
   This will guide you through updating your configuration files.

6. **Choose your JavaScript approach**:
   ```bash
   # For import maps (simplest approach)
   rails importmap:install
   ```

7. **Choose your CSS approach**:
   ```bash
   # For example, to use Sass
   rails css:install:sass
   ```

8. **Run your tests** to identify any issues:
   ```bash
   bin/rails test
   ```

9. **Fix remaining issues** identified by RailsUpshift or your tests

10. **Deploy and monitor** your application for any unexpected behavior

## Common Errors and Solutions

### JavaScript Loading Errors

**Error**: `Uncaught ReferenceError: require is not defined`

**Solution**: Import maps don't support CommonJS-style requires. Update your JavaScript to use ES modules:
```javascript
// Old way
const Turbo = require("@hotwired/turbo")

// New way
import * as Turbo from "@hotwired/turbo"
```

### Asset Pipeline Errors

**Error**: `Sprockets::Rails::Helper::AssetNotPrecompiled`

**Solution**: Update your asset precompilation list in `config/initializers/assets.rb`:
```ruby
Rails.application.config.assets.precompile += %w( your_asset.js )
```

### ActiveRecord Encryption Errors

**Error**: `ArgumentError: Missing deterministic encryption key`

**Solution**: Set up encryption keys in `config/credentials.yml.enc`:
```bash
rails db:encryption:init
```

## Additional Resources

- [Official Rails 7.0 Release Notes](https://edgeguides.rubyonrails.org/7_0_release_notes.html)
- [Rails 7 Upgrade Checklist](https://www.fastruby.io/blog/rails/upgrades/rails-7-0-upgrade-checklist.html)
- [Hotwire Documentation](https://hotwired.dev/)
- [Import Maps Guide](https://github.com/rails/importmap-rails)
