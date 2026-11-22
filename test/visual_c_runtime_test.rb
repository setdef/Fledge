# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "tmpdir"
require_relative "test_helper"
require_relative "support/binaries"

# The Visual C++ runtime an app carries (Fledge::VisualCRuntime): copied
# from a folder that stands for the building computer's System32, which
# holds stand-ins the fixtures build, never Microsoft's own files.
class VisualCRuntimeTest < Minitest::Test
  def setup
    TestReaders.need(self, :pe)
    @system32 = Dir.mktmpdir("fledge-system32")
    @msvcp = Binaries.pe(needed: %w[VCRUNTIME140.dll VCRUNTIME140_1.dll KERNEL32.dll api-ms-win-crt-runtime-l1-1-0.dll])
    @vcruntime = Binaries.pe(needed: %w[KERNEL32.dll])
    File.binwrite(File.join(@system32, "msvcp140.dll"), @msvcp)
    File.binwrite(File.join(@system32, "vcruntime140.dll"), @vcruntime)
  end

  def teardown
    FileUtils.rm_rf(@system32)
  end

  def runtime(names)
    Fledge::VisualCRuntime.new(names, folder: @system32, readers: TestReaders.all)
  end

  # A gem's DLL that needs only msvcp140.dll still needs what msvcp140.dll
  # needs of the runtime, so the app carries those too, each by the name
  # the folder gives it, in the folder Ruby's DLLs are searched in.
  def test_carries_each_dll_and_the_runtime_dlls_it_needs
    File.binwrite(File.join(@system32, "vcruntime140_1.dll"), @vcruntime)
    carried = runtime(["MSVCP140.dll"])
    assert_empty carried.problems
    entries = carried.entries("ruby/bin/ruby_builtin_dlls")
    assert_equal %w[msvcp140.dll vcruntime140.dll vcruntime140_1.dll].map { |name| "ruby/bin/ruby_builtin_dlls/#{name}" }, entries.map(&:path)
    assert_equal [@msvcp, @vcruntime, @vcruntime], entries.map(&:content)
  end

  # A DLL the folder lacks is a problem that says where it was looked
  # for and how it gets there.
  def test_names_a_dll_the_building_computer_lacks
    problems = runtime(["MSVCP140.dll"]).problems
    assert_equal [
      "VCRUNTIME140_1.dll, of Microsoft's Visual C++ runtime, which windows: { visual_c_runtime: local } copies into the app from " \
        "#{@system32}, is not there. Install Microsoft's Visual C++ Redistributable on this computer, which puts it there.",
    ], problems
  end

  def test_carries_nothing_when_nothing_needs_it
    assert_empty runtime([]).entries("ruby/bin/ruby_builtin_dlls")
  end
end
