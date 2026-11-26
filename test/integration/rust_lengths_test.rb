# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"

# fledge build compiling test/fixtures/rust_lengths, a Rust gem on rb-sys
# alone, against the real runtime's own Ruby, and the built app saying
# its bindings give rb_len_t the runtime's Ruby's width: 8 bytes on every
# platform Fledge builds for, so that rb_ary_entry finds 3 at -1 of
# [1, 2, 3] and rb_range_beg_len leaves the canaries beside its lengths
# whole (doc/contributors/design/gems.md, "Rust gems on Windows and
# rb_len_t"). On Windows bindings of 4 bytes say 4, nil, and overwritten.
# It exits with the status its argument names, as every app Delivery
# runs does (.github/scripts/deliver.sh, "exit status 3 reaches the
# caller").
#
# It needs the runtime, as test/integration/native_build_test.rb finds
# it, and the cargo of the Rust mise.toml pins, with a libclang for
# bindgen (mise.toml's on Linux, and on Windows LIBCLANG_PATH, which
# mise.rust.toml's LLVM sets under MISE_ENV=rust, as ci.yml's Build job
# sets it from the runner's). Without them it skips, unless
# FLEDGE_REQUIRE_RUST is set: CI's Test jobs install only Ruby, and a
# runner's own Rust is neither pinned nor set up for bindgen, so CI's
# Build and Delivery jobs prove the fixture there.
class RustLengthsTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/rust_lengths", __dir__)

  # The Rust mise.toml pins.
  RUST = File.read(File.expand_path("../../mise.toml", __dir__))[/^rust = \{ version = "([^"]+)"/, 1]

  EXPECTED = "RustLengths binds rb_len_t in 8 bytes, finds 3 at -1 of [1, 2, 3], " \
    "and takes 2 and 3 of 10 for 2..4 with its canaries whole"

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    name = Fledge::Runtimes.file_name(@platform)
    need("no #{name} in #{@runtimes}; run bundle exec rake runtime", "FLEDGE_REQUIRE_RUNTIME") unless File.file?(File.join(@runtimes, name))
    need("no cargo #{RUST} on PATH, the Rust mise.toml pins", "FLEDGE_REQUIRE_RUST") unless cargo?
    if Gem.win_platform? && !ENV["LIBCLANG_PATH"]
      need("no LIBCLANG_PATH, which names the libclang bindgen loads on Windows", "FLEDGE_REQUIRE_RUST")
    end
    @dir = Dir.mktmpdir
  rescue Fledge::Error => e
    need(e.message, "FLEDGE_REQUIRE_RUNTIME")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def need(message, variable)
    flunk message if ENV[variable]
    skip message
  end

  def cargo?
    out, status = Open3.capture2e("cargo", "--version")
    status.success? && out.start_with?("cargo #{RUST} ")
  rescue SystemCallError
    false
  end

  def test_the_bindings_give_rb_len_t_the_runtimes_width
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out: StringIO.new, err:, env:).call(["-o", File.join(@dir, "dist"), FIXTURE])

    assert_equal 0, status, err.string
    folder = File.join(@dir, "dist", "rust_lengths-#{@platform}")
    scrubbed = ENV.keys.grep(Fledge::NativeBuild::SCRUBBED).to_h { |name| [name, nil] }
    out, ran = Open3.capture2e({ "PATH" => ENV.fetch("PATH") }.merge(scrubbed), File.join(folder, @platform.executable("rust_lengths")), "3",
      unsetenv_others: !Gem.win_platform?)

    assert_equal 3, ran.exitstatus, out
    assert_equal EXPECTED, out.strip
  end
end
