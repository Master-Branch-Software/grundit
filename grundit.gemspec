Gem::Specification.new do |spec|
  spec.name          = "grundit"
  spec.version       = "0.1.0"
  spec.authors       = ["MasterBranch Software, LLC"]
  spec.email         = ["ray@masterbranchsoftware.com"]
  spec.summary       = "Pundit-compatible, GraphQL-centric authorization for Rails."
  spec.description   = "A lightweight authorization framework for graphql-ruby applications. " \
                       "Provides policy-based auth(), auth_index(), and a field extension " \
                       "that enforces authorization on every resolver."
  spec.homepage      = "https://github.com/Master-Branch-Software/grundit"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.0"
  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_dependency "graphql", ">= 2.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
end
