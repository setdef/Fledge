# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "socket"
require "tmpdir"

# examples/roda_server, Jot, a server on 127.0.0.1, built by fledge build
# from a real runtime for this computer and delivered by
# .github/scripts/deliver-server.sh, which CI's Delivery runs on fresh
# computers too, beside the same checks of bundle exec ruby main.rb on
# this computer's Ruby. Building it downloads its gems from RubyGems.org.
# Windows' delivery is CI's, with deliver-server.ps1.
#
# The runtime comes from FLEDGE_RUNTIME_DIR, or from tmp/runtime, where
# rake runtime writes it. Without one the test skips, unless
# FLEDGE_REQUIRE_RUNTIME is set, as CI sets it on every platform with a
# runtime.
class RodaServerTest < Minitest::Test
  EXAMPLE = File.expand_path("../../examples/roda_server", __dir__)
  DELIVER = File.expand_path("../../.github/scripts/deliver-server.sh", __dir__)
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  def setup
    platform = Fledge::Platform.local
    skip "deliver-server.ps1 delivers Jot on Windows in CI" if platform.windows?
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(platform)))

    message = "no #{Fledge::Runtimes.file_name(platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  end

  def test_the_built_server_answers_keeps_notes_and_stops_as_bundle_exec_does
    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build", "-o", dir, EXAMPLE)
      assert_predicate status, :success?, err

      gemfile = { "BUNDLE_GEMFILE" => File.join(EXAMPLE, "Gemfile"), "PORT" => free_port.to_s }
      Bundler.with_unbundled_env do
        installed, status = Open3.capture2e(gemfile, RbConfig.ruby, "-S", "bundle", "install", "--quiet")
        assert_predicate status, :success?, installed

        reference = ["--reference", RbConfig.ruby, "-rbundler/setup", File.join(EXAMPLE, "main.rb")]
        [[out.lines.first.to_s.chomp], reference].each do |arguments|
          report, status = Open3.capture2e(gemfile, DELIVER, *arguments)
          assert_predicate status, :success?, report
          assert_includes report, "ok (taken): a second start said the port is in use and exited with 69"
        end
      end
    end
  end

  # A port nothing on this computer listens on now, so the test never
  # meets a Jot a developer is running at 8765.
  private def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end
end
