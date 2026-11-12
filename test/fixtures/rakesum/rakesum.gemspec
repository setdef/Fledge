# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# A gem shaped like digest-crc: its gemspec names a Rakefile, which runs
# an extconf.rb and make in the folder of each of its extensions, and
# leaves each extension there, where the require path ext finds it.
Gem::Specification.new do |spec|
  spec.name = "rakesum"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "Two C extensions a Rakefile builds, for test/integration/mobile_extensions_build_test.rb"
  spec.license = "MIT-0"
  spec.files = [
    "lib/rakesum.rb",
    "ext/rakesum/Rakefile",
    "ext/rakesum/adler/extconf.rb",
    "ext/rakesum/adler/adler_ext.c",
    "ext/rakesum/fletcher/extconf.rb",
    "ext/rakesum/fletcher/fletcher_ext.c",
  ]
  spec.extensions = ["ext/rakesum/Rakefile"]
  spec.require_paths = ["ext", "lib"]
end
