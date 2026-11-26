# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require_relative "../support/ios"

# Whether a Fiddle::Closure works on an iPhone
# (doc/contributors/research/2026-11-25-pure-ruby-uikit.md, section 1).
# fiddle makes a closure with libffi's +ffi_closure_alloc+ when its
# extconf.rb finds that function, which on Apple's arm64 takes an entry
# of a trampoline table compiled into the signed binary; without it,
# fiddle maps a writable page and makes it executable with +mprotect+,
# and a device ends the process that calls the page for its code
# signature. The Simulator runs such a page, so only a check of what the
# runtime's device slice holds keeps that from coming back unnoticed.
# Reads the iOS runtime that tmp/runtime (or FLEDGE_RUNTIME_DIR) holds;
# without it, or on a computer that is not a Mac, it skips, and fails
# instead where FLEDGE_REQUIRE_IOS is set.
class MobileClosuresTest < Minitest::Test
  include IOSRequired

  # The symbol that decides which of fiddle's two paths a closure takes.
  ALLOCATOR = "_ffi_closure_alloc"

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_the_device_slices_fiddle_makes_closures_with_libffis_trampoline_table
    ios_missing("nm reads a Mach-O on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"
    archive = runtime_archive
    names = Fledge::Archive.names(archive).grep(%r{/ios-arm64/lib/ruby/(?:.+/)?fiddle\.bundle\z})

    refute_empty names, "the device slice of #{File.basename(archive)} holds no fiddle.bundle"
    Fledge::Archive.unpack(archive, into: @dir, only: names)
    names.each do |name|
      assert defines?(File.join(@dir, name), ALLOCATOR), "#{name} does not define #{ALLOCATOR}, so a closure on an iPhone would take fiddle's mprotect path, which iOS kills the process for"
    end
  end

  # The check above passes only for a file that defines the symbol, not
  # for any file.
  def test_the_check_tells_a_file_that_defines_the_allocator_from_one_that_does_not
    ios_missing("nm and a compiler read and make a Mach-O on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"

    assert defines?(object("void ffi_closure_alloc(void) {}"), ALLOCATOR)
    refute defines?(object("void ffi_prep_closure_loc(void) {}"), ALLOCATOR)
    refute defines?(object("void ffi_prep_closure_loc(void);\nvoid f(void) { ffi_prep_closure_loc(); }"), ALLOCATOR)
  end

  # Whether the Mach-O +file+ defines the external +symbol+, not
  # merely refers to it.
  private def defines?(file, symbol)
    out, status = Open3.capture2e("xcrun", "nm", "-U", "-m", file)
    assert_predicate status, :success?, "nm #{file}:\n#{out}"
    out.lines.any? { |line| line.match?(/ external #{Regexp.escape(symbol)}\s*\z/) }
  end

  # An object file compiled from +source+.
  private def object(source)
    c = File.join(@dir, "probe#{@dir.hash.abs}-#{source.hash.abs}.c")
    File.write(c, source)
    o = c.sub(/\.c\z/, ".o")
    out, status = Open3.capture2e("xcrun", "cc", "-c", c, "-o", o)
    assert_predicate status, :success?, "cc #{c}:\n#{out}"
    o
  end

  # The archive of the iOS runtime that tmp/runtime (or
  # FLEDGE_RUNTIME_DIR) holds; skips, or fails where required, without
  # it.
  private def runtime_archive
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    archive = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find("ios")))
    ios_missing("no #{File.basename(archive)} in #{dir}; run bundle exec rake runtime[ios]") unless File.file?(archive)
    archive
  end
end
