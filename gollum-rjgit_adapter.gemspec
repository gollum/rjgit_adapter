# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rjgit_adapter/version"

Gem::Specification.new do |s|
  s.name        = "gollum-rjgit_adapter"
  s.version     = Gollum::Lib::Git::VERSION
  s.platform    = "java"
  s.authors     = ["Bart Kamphorst, Dawa Ometto"]
  s.email       = ["repotag-dev@googlegroups.com"]
  s.homepage    = "https://github.com/repotag/gollum-lib_rjgit_adapter"
  s.summary     = %q{Adapter for Gollum to use RJGit at the backend.}
  s.description = %q{Adapter for Gollum to use RJGit at the backend.}

  s.add_runtime_dependency "rjgit", "~> 4.1"
  s.add_development_dependency "rspec", "3.4.0"

  s.files         = Dir['lib/**/*.rb'] + ["README.md", "Gemfile"]
  s.require_paths = ["lib"]

  # = MANIFEST =
  s.files = %w(
    Gemfile
    LICENSE
    README.md
    Rakefile
    gollum-rjgit_adapter.gemspec
    lib/rjgit_adapter.rb
    lib/rjgit_adapter/git_layer_rjgit.rb
    lib/rjgit_adapter/version.rb
  )
  # = MANIFEST =
end
