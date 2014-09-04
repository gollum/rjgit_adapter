# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "gollum-lib_rjgit_adapter/version"

Gem::Specification.new do |s|
  s.name        = "gollum-lib_rjgit_adapter"
  s.version     = Gollum::Lib::Git::VERSION
  s.platform    = Gem::Platform::JRUBY
  s.authors     = ["Bart Kamphorst, Dawa Ometto"]
  s.email       = ["repotag-dev@googlegroups.com"]
  s.homepage    = "https://github.com/repotag/gollum-lib_rjgit_adapter"
  s.summary     = %q{Adapter for Gollum to use RJGit at the backend.}
  s.description = %q{Adapter for Gollum to use RJGit at the backend.}

  s.add_runtime_dependency "rjgit"
  s.add_development_dependency "rspec", "2.13.0"

  s.files         = Dir['lib/**/*.rb'] + ["README.md", "Gemfile"]
  s.require_paths = ["lib"]
end

