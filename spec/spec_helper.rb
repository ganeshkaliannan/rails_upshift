require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_group 'Lib', 'lib'
end

require "rails_upshift"
require "fileutils"
require "tempfile"
require "stringio"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  
  # Clean up any temporary directories created during tests
  config.after(:suite) do
    Dir.glob(File.join(Dir.tmpdir, "rails_upshift_test_*")).each do |dir|
      FileUtils.rm_rf(dir) if Dir.exist?(dir)
    end
  end
end
