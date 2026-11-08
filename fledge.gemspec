# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/fledge/version"

Gem::Specification.new do |spec|
  spec.name = "fledge"
  spec.version = Fledge::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["kerrick@setdef.com"]

  spec.summary = "Ship a Ruby app to people who don't have Ruby."
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.homepage = "https://github.com/setdef/Fledge"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  # Releases are tags and GitHub Releases (ADR 001), and a person publishes
  # to RubyGems.org by hand. This host keeps a stray gem push from
  # publishing the gem.
  spec.metadata["allowed_push_host"] = "https://fledge.invalid"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/trunk/CHANGELOG.md"

  # Listing paths keeps development files (plans, tasks, tests, tool
  # configuration) out without a deny list that every new file has to
  # remember.
  packaged = %w[
    exe
    lib
    sig
    README.rdoc
    CHANGELOG.md
    LICENSE
    LICENSES
  ]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.bindir = "exe"
  spec.executables = ["fledge"]
  spec.require_paths = ["lib"]
end
