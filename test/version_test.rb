# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

class VersionTest < Minitest::Test
  def gemspec
    Gem::Specification.load(File.expand_path("../fledge.gemspec", __dir__))
  end

  def test_version_is_a_semantic_version
    assert_match(/\A\d+\.\d+\.\d+(?:\.pre\.\d+)?\z/, Fledge::VERSION)
  end

  def test_gemspec_publishes_the_library_version
    assert_equal Fledge::VERSION, gemspec.version.to_s
  end

  # Only a person publishes to RubyGems.org
  # (doc/contributors/design/releases.md, "Where releases are"); a push
  # host that cannot resolve makes a stray gem push refuse instead.
  def test_gemspec_cannot_be_pushed_to_rubygems
    assert_equal "https://fledge.invalid", gemspec.metadata.fetch("allowed_push_host")
  end

  # fledge build reads the gemspec of every git or path gem a project
  # locks, in its own process, and a project may lock another fledge
  # than the one running: a framework's, say. That gemspec gives its own
  # version and leaves the running Fledge's alone, which names the
  # runtimes it fetches (Fledge::Runtimes.file_name).
  def test_another_checkouts_gemspec_leaves_the_running_version_alone
    running = Fledge::VERSION
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib", "fledge"))
      FileUtils.cp(File.expand_path("../fledge.gemspec", __dir__), dir)
      FileUtils.cp(File.expand_path("../README.rdoc", __dir__), dir)
      version = File.read(File.expand_path("../lib/fledge/version.rb", __dir__)).sub(running, "9.8.7")
      File.write(File.join(dir, "lib", "fledge", "version.rb"), version)

      spec = Gem::Specification.load(File.join(dir, "fledge.gemspec"))

      assert_equal ["9.8.7", running], [spec&.version.to_s, Fledge::VERSION]
    end
  ensure
    if Fledge::VERSION != running
      Fledge.__send__(:remove_const, :VERSION)
      Fledge.const_set(:VERSION, running)
    end
  end

  def test_gemspec_installs_the_fledge_executable
    spec = gemspec

    assert_equal ["fledge"], spec.executables
    assert_includes spec.files, "exe/fledge"
    assert_includes spec.files, "lib/fledge/cli.rb"
  end
end
