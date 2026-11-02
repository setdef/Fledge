# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0

Gem::Specification.new do |spec|
  spec.name = "fledge_submodule_gem"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A gem with a git submodule, for Fledge's tests of gems from git"
  spec.license = "MIT-0"
  spec.files = Dir["lib/**/*.rb"] + ["vendor/hello/README"]
  spec.require_paths = ["lib"]
end
