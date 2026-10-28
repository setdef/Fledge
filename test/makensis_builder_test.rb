# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/makensis_builder"

# What tasks/makensis_builder.rb builds, without building it: CI's
# makensis jobs build it on every platform, compile an installer with
# each, and the build job's NSIS installer comes from one (ci.yml).
class MakensisBuilderTest < Minitest::Test
  def test_the_archive_is_the_one_fledge_build_downloads
    builder = MakensisBuilder.new(host: Fledge::Platform.find("aarch64-linux"))

    assert_equal "fledge-makensis-#{Fledge::VERSION}-aarch64-linux", builder.top
    assert_equal "#{builder.top}.tar.gz", Fledge::Runtimes.makensis_file_name(Fledge::Platform.find("aarch64-linux"))
  end

  # NSIS's "Building on POSIX": the compiler alone, finding its data by
  # NSISDIR, as Fledge points it at the Windows runtime's NSIS.
  def test_scons_builds_the_compiler_alone_for_each_computer
    prefix = "/tmp/out"
    linux = MakensisBuilder.scons_flags(Fledge::Platform.find("x86_64-linux"), version: "3.13", prefix:)
    mac = MakensisBuilder.scons_flags(Fledge::Platform.find("arm64-darwin"), version: "3.13", prefix:)

    common = %w[SKIPSTUBS=all SKIPPLUGINS=all SKIPUTILS=all SKIPMISC=all NSIS_CONFIG_CONST_DATA_PATH=no VERSION=3.13 PREFIX=/tmp/out]
    assert_equal [*common, "APPEND_LINKFLAGS=-static-libstdc++ -static-libgcc", "install-compiler"], linux
    assert_equal [*common, "APPEND_CCFLAGS=-mmacosx-version-min=14.0", "APPEND_LINKFLAGS=-mmacosx-version-min=14.0", "install-compiler"], mac
  end

  def test_nsis_is_pinned_by_sha256
    nsis = YAML.safe_load_file(File.expand_path("../runtime/sources.yml", __dir__)).fetch("nsis")

    %w[binary source scons].each { |part| assert_match(/\A\h{64}\z/, nsis.fetch(part).fetch("sha256"), part) }
    assert_equal "3.13", nsis.fetch("version")
  end
end
