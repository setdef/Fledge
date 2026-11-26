# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "socket"
require "tmpdir"

# examples/file_drop, Drop, a file drop that Sinatra and Puma serve to
# the network, built by fledge build from a real runtime for this
# computer, which compiles Puma and nio4r, and delivered by
# .github/scripts/deliver-server.sh, which CI's Delivery runs on fresh
# computers too, beside the same checks of bundle exec ruby main.rb on
# this computer's Ruby. Building it downloads its gems from RubyGems.org.
# Windows' delivery is CI's, with deliver-server.ps1.
#
# The runtime comes from FLEDGE_RUNTIME_DIR, or from tmp/runtime, where
# rake runtime writes it. Without one the test skips, unless
# FLEDGE_REQUIRE_RUNTIME is set, as CI sets it on every platform with a
# runtime.
class FileDropTest < Minitest::Test
  EXAMPLE = File.expand_path("../../examples/file_drop", __dir__)
  DELIVER = File.expand_path("../../.github/scripts/deliver-server.sh", __dir__)
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  def setup
    platform = Fledge::Platform.local
    skip "deliver-server.ps1 delivers Drop on Windows in CI" if platform.windows?
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(platform)))

    message = "no #{Fledge::Runtimes.file_name(platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  end

  def test_the_built_file_drop_takes_a_file_and_gives_it_back_as_bundle_exec_does
    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build", "-o", dir, EXAMPLE)
      assert_predicate status, :success?, err

      # BUNDLER_VERSION is unset because a gate that sets it runs whichever
      # Bundler its Ruby has, which turns off Bundler's switch to the one
      # Drop's Gemfile.lock names (Bundler::SelfManager#autoswitching_applies?),
      # and bundle install then writes that Bundler into the committed
      # lockfile: CI's full run rewrote BUNDLED WITH from 4.0.20 to Ruby
      # 4.1.0-preview1's 4.1.0.beta2, and ExamplesLockfilesTest, which ran
      # after this test, failed (lectern_test.rb has the same).
      gemfile = { "BUNDLE_GEMFILE" => File.join(EXAMPLE, "Gemfile"), "BUNDLER_VERSION" => nil, "PORT" => free_port.to_s }
      Bundler.with_unbundled_env do
        installed, status = Open3.capture2e(gemfile, RbConfig.ruby, "-S", "bundle", "install", "--quiet")
        assert_predicate status, :success?, installed

        reference = ["--reference", RbConfig.ruby, "-rbundler/setup", File.join(EXAMPLE, "main.rb")]
        [[out.lines.first.to_s.chomp], reference].each do |arguments|
          report, status = Open3.capture2e(gemfile, DELIVER, *arguments)
          assert_predicate status, :success?, report
          assert_includes report, "ok: a second client found the file listed and fetched it byte for byte"
        end
      end
    end
  end

  # A port nothing on this computer listens on now, so the test never
  # meets a Drop a developer is running at 4567.
  private def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end
end
