lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rails_upshift/version"

Gem::Specification.new do |spec|
  spec.name          = "rails_upshift"
  spec.version       = RailsUpshift::VERSION
  spec.authors       = ["Ganesh Kaliannan"]
  spec.email         = ["ganesh.kaliannan@gmail.com"]

  spec.summary       = %q{A comprehensive tool to upgrade Rails applications}
  spec.description   = %q{RailsUpshift helps upgrade Rails applications to newer versions by automatically identifying and fixing common upgrade issues, including codebase-specific patterns like Sidekiq jobs, client configurations, and API modules.}
  spec.homepage      = "https://github.com/ganeshkaliannan/rails_upshift"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/yourusername/rails_upshift"
    spec.metadata["changelog_uri"] = "https://github.com/yourusername/rails_upshift/blob/main/CHANGELOG.md"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = ["rails_upshift"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  
  spec.add_dependency "colorize", "~> 0.8"
end
