# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Tests how .github/scripts/ruby-archive.sh starts its container
# (doc/contributors/design/runtimes.md, "Fledge's own Ruby builds"). Each
# test runs the script with bash, with a container program on PATH that
# keeps the arguments it is given and exits, so that the build itself,
# which needs a computer of the platform's architecture and an hour,
# does not run.

require_relative "../test_helper"
require "open3"
require "tmpdir"

class RubyArchiveScriptTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, ".github", "scripts", "ruby-archive.sh")

  def setup
    skip "the workflow's script runs on Linux, with bash" if Gem.win_platform?
    @dir = Dir.mktmpdir
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    @log = File.join(@dir, "arguments")
    %w[docker podman].each do |program|
      File.write(File.join(@bin, program), "#!/bin/sh\necho \"#{program} $*\" >> \"$FAKE_CONTAINER_LOG\"\n")
      File.chmod(0o755, File.join(@bin, program))
    end
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # The platform of this computer's architecture, which the script
  # builds on and refuses to emulate.
  def platform
    %w[arm64 aarch64].include?(RbConfig::CONFIG["host_cpu"]) ? "aarch64-linux" : "x86_64-linux"
  end

  def build(**environment)
    env = { "PATH" => "#{@bin}:#{ENV.fetch('PATH')}", "FAKE_CONTAINER_LOG" => @log, "XDG_CACHE_HOME" => File.join(@dir, "cache") }
    out, status = Open3.capture2e(env.merge(environment), "bash", SCRIPT, platform)
    assert status.success?, out
    File.read(@log)
  end

  def test_docker_runs_the_build_and_hands_back_what_it_wrote
    ran = build

    assert_match(/\Adocker run --rm /, ran)
    assert_includes ran, "-e FLEDGE_OWNER=#{Process.uid}:#{Process.gid}"
  end

  # Podman has no daemon and runs as the account, so its container's root
  # is the account: what the build writes in the checkout is the
  # account's already, and a chown to the account's ID, which inside
  # a user namespace is another user's, would take it away.
  def test_podman_runs_the_build_and_leaves_the_ownership_of_what_it_wrote
    ran = build("FLEDGE_CONTAINER" => "podman")

    assert_match(/\Apodman run --rm /, ran)
    refute_includes ran, "FLEDGE_OWNER"
  end

  # Podman resolves a name with no registry through a list of
  # registries, and refuses when it cannot ask which one to use.
  def test_the_image_names_its_registry
    assert_includes build, " docker.io/library/ubuntu:22.04@sha256:"
  end
end
