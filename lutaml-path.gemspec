# frozen_string_literal: true

require_relative "lib/lutaml/path/version"

Gem::Specification.new do |spec|
  spec.name = "lutaml-path"
  spec.version = Lutaml::Path::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Element path parser supporting OCL-style paths"
  spec.description = "Parser for element paths"

  spec.homepage = "https://github.com/lutaml/lutaml-path"
  spec.license = "BSD-2-Clause"

  spec.bindir = "exe"
  spec.require_paths = ["lib"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the
  # RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|features)/})
    end
  end
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.add_dependency "parslet"
  spec.metadata["rubygems_mfa_required"] = "true"
end
