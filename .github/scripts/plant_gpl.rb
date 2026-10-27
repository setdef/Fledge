# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileComment: Adapted from the "Fail the audit with a GPL library and
#   a GPL gem slipped in" step of .github/workflows/ci.yml on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
#++

# Slips two pieces of GPL code into an unpacked runtime, for CI to prove
# that the license audit still refuses them (ci.yml, Licenses):
#
#   ruby .github/scripts/plant_gpl.rb PLATFORM TREE
#
# The first is a compiled Ruby extension in the platform's own format (a
# Mach-O bundle, an ELF shared object, or a PE DLL, as test/support/
# binaries.rb writes them) where Ruby keeps its extensions, carrying the
# GPL's words. The second is a gem whose specification declares
# GPL-3.0-only. It prints the extension's path within TREE, which the
# audit must name.
require "fileutils"
require "rubygems"
require "yaml"
require_relative "../../test/support/binaries"

platform, tree = ARGV
abort "usage: plant_gpl.rb PLATFORM TREE" unless platform && tree && File.directory?(tree)

facts = YAML.safe_load_file(File.expand_path("../../runtime/licenses.yml", __dir__)).fetch("platforms").fetch(platform)
prefix = File.directory?(File.join(tree, "ruby", "lib", "ruby")) ? "ruby/" : ""
notice = "Licensed under the GNU General Public License, version 3"
binary = case facts.fetch("os")
when "darwin" then Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], payload: notice)
when "windows" then Binaries.pe(needed: %w[KERNEL32.dll], payload: notice)
else Binaries.elf(needed: %w[libc.so.6], payload: notice)
end
extension = "#{prefix}lib/ruby/4.0.0/#{facts.fetch('arch')}/gpl_thing.#{facts.fetch('so')}"
File.binwrite(File.join(tree, extension), binary)

gems = File.join(tree, prefix, "lib", "ruby", "gems", "4.0.0")
spec = Gem::Specification.new do |gem|
  gem.name = "copyleft"
  gem.version = "1.0.0"
  gem.summary = "GPL code that must not ship"
  gem.authors = ["Fledge's CI"]
  gem.licenses = ["GPL-3.0-only"]
end
File.write(File.join(gems, "specifications", "copyleft-1.0.0.gemspec"), spec.to_ruby)
FileUtils.mkdir_p(File.join(gems, "gems", "copyleft-1.0.0"))
File.write(File.join(gems, "gems", "copyleft-1.0.0", "copyleft.rb"), "# #{notice}\n")

puts extension
