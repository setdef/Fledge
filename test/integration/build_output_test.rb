# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gems"
require "open3"
require "rbconfig"
require "tmpdir"

# What fledge build prints to standard output when the project's Gemfile
# and gemspec print: the paths of what it wrote, and nothing else
# (doc/contributors/design/public-interface.md, "The command's
# conventions"). The evaluation runs in fledge build's own process, as
# bundle install's does (doc/contributors/design/gems.md, "Reading the
# Gemfile and lockfile").
class BuildOutputTest < Minitest::Test
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  def test_what_a_gemfile_and_a_gemspec_print_does_not_reach_standard_output
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)
      FileUtils.mkdir_p(File.join(dir, ".git"))
      root = FakeProject.write(dir, gemfile: "puts \"gemfile says hi\"\nsystem(\"echo gemfile child\")\n")
      gemspec = File.join(root, "my_app.gemspec")
      File.write(gemspec, "puts \"gemspec says hi\"\n#{File.read(gemspec)}")
      runtimes = File.join(dir, "runtimes")
      FileUtils.mkdir_p(runtimes)
      FakeRuntime.write(runtimes, Fledge::Platform.local)
      env = { "FLEDGE_RUNTIME_DIR" => runtimes, "FLEDGE_RUNTIME_DIR_UNCHECKED" => "1", "NO_COLOR" => "1" }

      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", LIB, EXE, "build", "--out", File.join(dir, "dist"), root)

      assert_predicate status, :success?, err
      archive = File.join(dir, "dist", "MyApp-#{Fledge::Platform.local.name}#{Fledge::Platform.local.windows? ? '.zip' : '.tar.gz'}")
      assert_equal "#{archive}\n", out.gsub("\r\n", "\n")
      ["gemfile says hi", "gemfile child", "gemspec says hi"].each { |line| assert_includes err.gsub("\r\n", "\n").lines.map(&:chomp), line }
    end
  end
end
