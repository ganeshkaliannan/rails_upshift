# Rails 5 to 6 Upgrade Guide

This guide provides a comprehensive overview of upgrading from Rails 5.x to Rails 6.0. RailsUpshift can automatically fix many of these issues, but some will require manual intervention.

## Prerequisites

- Ruby 2.5.0 or newer (Rails 6 requires at least Ruby 2.5.0)
- Bundler 2.0 or newer

## Major Changes in Rails 6

### Zeitwerk Autoloading

Rails 6 introduces Zeitwerk as the new code autoloader, replacing the classic autoloader. Zeitwerk enforces stricter naming conventions:

- Filenames must match the class/module name (e.g., `api_controller.rb` should define `ApiController`, not `APIController`)
- Namespaces must be properly nested (e.g., `app/controllers/api/v1/users_controller.rb` should define `Api::V1::UsersController`)

**RailsUpshift can automatically fix:**
- Renaming `API` module to `Api` for proper autoloading
- Updating references from `API::` to `Api::`

**Manual steps required:**
- Review your application structure to ensure it follows Zeitwerk conventions
- Add any necessary `require` statements for files that don't follow the conventions

### Action Text

Rails 6 introduces Action Text, which provides rich text content editing. If you want to use it:

1. Install the required dependencies:
   ```bash
   rails action_text:install
   ```

2. Add to your model:
   ```ruby
   class Message < ApplicationRecord
     has_rich_text :content
   end
   ```

### Action Mailbox

Rails 6 introduces Action Mailbox for routing incoming emails to controller-like mailboxes. If you want to use it:

1. Install the required dependencies:
   ```bash
   rails action_mailbox:install
   ```

### Multiple Databases Support

Rails 6 adds first-class support for multiple databases:

```ruby
class AnimalsDatabase < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :animals_primary, reading: :animals_replica }
end

class Dog < AnimalsDatabase
  # ...
end
```

### Parallel Testing

Rails 6 adds parallel testing support:

```ruby
# config/environments/test.rb
config.parallelization_threshold = 50
config.parallel_workers = 2
```

## Common Upgrade Issues

### 1. ActiveRecord Changes

**RailsUpshift can automatically fix:**
- Deprecated dynamic finders (`find_by_*`)
- Deprecated `update_attributes` method

**Manual steps required:**
- Review complex queries that might be affected by the new behavior of `where.not`
- Check for any custom SQL that might be affected by the new quoting behavior

### 2. ActiveStorage Changes

**Manual steps required:**
- If using ActiveStorage, add `dependent: :purge_later` to attachments for proper cleanup:
  ```ruby
  has_one_attached :avatar, dependent: :purge_later
  ```

### 3. Webpacker Integration

Rails 6 uses Webpacker as the default JavaScript compiler:

1. Install Webpacker:
   ```bash
   rails webpacker:install
   ```

2. Update your application layout:
   ```erb
   <%= javascript_pack_tag 'application', 'data-turbolinks-track': 'reload' %>
   ```

### 4. Configuration Changes

**RailsUpshift can automatically fix:**
- Adding `config.load_defaults 6.0` to `config/application.rb`
- Updating DNS rebinding protection settings

**Manual steps required:**
- Review all deprecation warnings after upgrading
- Update your `config/environments/*.rb` files for new options

### 5. Time Handling

**RailsUpshift can automatically fix:**
- Replacing `Time.now` with `Time.current`
- Replacing `DateTime.now` with `Time.current`
- Replacing `Date.today` with `Time.current.to_date`

### 6. URL Encoding

**RailsUpshift can automatically fix:**
- Replacing `URI.escape` with `CGI.escape`
- Replacing `URI.unescape` with `CGI.unescape`
- Adding `.to_s` to `CGI.escape` calls for safer handling

## Step-by-Step Upgrade Process

1. **Update your Ruby version** to at least 2.5.0

2. **Update your Gemfile**:
   ```ruby
   gem 'rails', '~> 6.0.0'
   ```

3. **Run RailsUpshift**:
   ```bash
   rails_upshift --target 6.0.0 --update-gems --update-configs
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

6. **Run your tests** to identify any issues:
   ```bash
   bin/rails test
   ```

7. **Fix remaining issues** identified by RailsUpshift or your tests

8. **Deploy and monitor** your application for any unexpected behavior

## Common Errors and Solutions

### Zeitwerk Autoloading Errors

**Error**: `expected file app/models/api/user.rb to define constant Api::User`

**Solution**: Ensure your file structure matches your class/module names. Rename `API` to `Api` throughout your codebase.

### Webpacker Errors

**Error**: `Webpacker::Manifest::MissingEntryError`

**Solution**: Ensure you've installed Webpacker and compiled your assets:
```bash
rails webpacker:install
rails webpacker:compile
```

### ActiveStorage Errors

**Error**: `undefined method 'purge_later'`

**Solution**: Ensure you're using the correct attachment API:
```ruby
# Old way
@user.avatar.purge

# New way
@user.avatar.purge_later
```

## Additional Resources

- [Official Rails 6.0 Release Notes](https://edgeguides.rubyonrails.org/6_0_release_notes.html)
- [Rails 6 Upgrade Checklist](https://www.fastruby.io/blog/rails/upgrades/rails-6-0-upgrade-checklist.html)
- [Zeitwerk Mode Documentation](https://guides.rubyonrails.org/autoloading_and_reloading_constants.html#zeitwerk-mode)
