# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "tmpdir"

# Which shared libraries Fledge::MobileExtensions::RakeBuild takes for
# Ruby's ffi, carries, or refuses, from a gem whose Rakefile builds
# nothing, so that every library is one its package holds. No Rake runs:
# the build is a command that leaves the gem as it was, and each
# library's bytes say what it was built for, where
# Fledge::MobileExtensions::BuiltFor would read it with the phone's
# tools (test/integration/mobile_extensions_build_test.rb reads real
# ones).
class MobileRakeBuildTest < Minitest::Test
  # Reads what a test library is built for from its bytes.
  class BuiltFor
    def call(_target, path)
      File.read(path)
    end

    def wanted(target)
      "Android #{target.abi}"
    end

    def desktop?(_target, system)
      system.start_with?("Linux ")
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @root = File.join(@dir, "held")
    FileUtils.mkdir_p(File.join(@root, "ext"))
    File.write(File.join(@root, "ext", "Rakefile"), "task :default\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def target
    Fledge::MobileExtensions::Target.new(name: "x86_64-linux-android", root: @dir, arch_dir: @dir, libdir: @dir, environment: {}, abi: "x86_64")
  end

  # Writes a library at +path+ in the gem, built for +system+.
  def hold(path, system)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), system)
  end

  def build
    gem = Fledge::PathGem.new(name: "held", version: "1.0.0", folder: @root, app_path: "vendor/cache/held", glob: "*.gemspec", inside: true)
    spec = Gem::Specification.new("held", "1.0.0")
    rake = Fledge::MobileExtensions::RakeBuild.new(ruby: "ruby", work: File.join(@dir, "work"), environment: {},
      run: -> (*, **) {}, load_path: [], built_for: BuiltFor.new)
    rake.call(target, gem, spec, @root, "ext/Rakefile", [], 0)
  end

  # A gem may ship its library for ffi already built for the phone, as
  # gems ship their desktops' builds: gem install leaves it, and the gem
  # opens it at that path. Fledge carries it as it carries one the
  # Rakefile built.
  def test_a_library_the_package_holds_built_for_the_target_is_a_library_for_ffi
    hold("ext/x86_64-linux/libheld.so", "Android x86_64")

    libraries = build

    assert_equal [["held", "ext/x86_64-linux/libheld.so", File.realpath(File.join(@root, "ext/x86_64-linux/libheld.so"))]],
      libraries.map { |library| [library.gem, library.file, library.path] }
  end

  # The package's library for the phone's other ABI is the other
  # target's to carry, and macOS's builds are nothing to Android.
  def test_a_library_the_package_holds_for_another_android_abi_or_apple_stays_the_gems_file
    hold("ext/aarch64-linux/libheld.so", "Android arm64-v8a")
    hold("ext/aarch64-darwin/libheld.bundle", "no Android system")

    assert_empty build
  end

  # Ruby's ffi takes Android for linux, so the gem would open a desktop
  # Linux's library on the phone.
  def test_a_library_the_package_holds_for_a_desktops_linux_is_refused
    hold("ext/x86_64-linux/libheld.so", "Linux x86_64")

    error = assert_raises(Fledge::Error) { build }

    assert_match(%r{held 1\.0\.0's Rakefile left ext/x86_64-linux/libheld\.so built for Linux x86_64, not Android x86_64}, error.message)
  end
end
