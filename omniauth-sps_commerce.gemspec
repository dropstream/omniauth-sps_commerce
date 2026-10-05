# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "omniauth-sps_commerce/version"

Gem::Specification.new do |spec|
  spec.name          = "omniauth-sps_commerce"
  spec.version       = Omniauth::SpsCommerce::VERSION
  spec.authors       = ["Karl Falconer"]
  spec.email         = ["karl.falconer@getdropstream.com"]

  spec.summary       = "OmniAuth strategy for SPS Commerce"
  spec.description   = "An OmniAuth OAuth2 strategy that authenticates against SPS Commerce " \
                       "(auth.spscommerce.com) and obtains tokens for the SPS Commerce APIs."
  spec.homepage      = "https://github.com/dropstream/omniauth-sps_commerce"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship only the library itself; development scaffolding stays out of the gem.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{\A(?:spec|bin|pkg|\.github)/}) ||
        f.match(%r{\A(?:\.gitignore|\.rspec|\.ruby-version|\.ruby-gemset|Gemfile|Gemfile\.lock|Rakefile)\z})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "omniauth", "~> 2.0"
  spec.add_dependency "omniauth-oauth2", "~> 1.9"
end
