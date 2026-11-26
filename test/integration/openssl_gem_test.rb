# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"

# fledge build compiling test/fixtures/openssl_gem, whose ssl_version
# gem links OpenSSL as Puma's does, against the real runtime, and the
# built app saying which OpenSSL the gem was compiled against and runs
# with: the OpenSSL the runtime's own Ruby has, the same headers as
# library, whatever the computer that builds has installed
# (doc/contributors/design/runtimes.md, "What a runtime keeps for
# compiling gems"). The build would refuse the gem if it linked the
# computer's own shared OpenSSL, so a build that passes linked the
# runtime's statically, or none, which the gem's extconf.rb refuses.
#
# It needs the runtime, as test/integration/native_build_test.rb finds
# it, and runs on macOS and Linux. Windows' runtime holds OpenSSL as
# DLLs, which a gem links through MSYS2's import libraries
# (runtimes.md, "The DLLs a compiled gem finds on Windows").
class OpensslGemTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/openssl_gem", __dir__)

  def setup
    @platform = Fledge::Platform.local
    skip "Windows' runtime holds OpenSSL as DLLs, not for compiling against" if @platform.windows?
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    name = Fledge::Runtimes.file_name(@platform)
    archive = File.join(@runtimes, name)
    need("no #{name} in #{@runtimes}; run bundle exec rake runtime") unless File.file?(archive)
    @dir = Dir.mktmpdir
  rescue Fledge::Error => e
    need(e.message)
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def need(message)
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  end

  def test_the_gem_links_the_runtimes_openssl
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out: StringIO.new, err:, env:).call(["-o", File.join(@dir, "dist"), FIXTURE])

    assert_equal 0, status, err.string
    scrubbed = ENV.keys.grep(Fledge::NativeBuild::SCRUBBED).to_h { |name| [name, nil] }
    program = File.join(@dir, "dist", "OpensslGem-#{@platform}", "OpensslGem")
    out, ran = Open3.capture2e({ "PATH" => ENV.fetch("PATH") }.merge(scrubbed), program, unsetenv_others: true)

    assert_predicate ran, :success?, out
    lines = out.lines(chomp: true)
    ruby = lines.find { |line| line.start_with?("Ruby's openssl runs ") }.to_s.delete_prefix("Ruby's openssl runs ")
    refute_empty ruby, out
    assert_includes lines, "ssl_version compiled against #{ruby}", out
    assert_includes lines, "ssl_version runs #{ruby}", out
    assert_includes lines, "ssl_version makes a TLS server context: true", out
  end
end
