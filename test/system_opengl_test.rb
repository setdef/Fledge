# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../.github/scripts/read-system-opengl"
require_relative "../tasks/windows_dlls"

# .github/scripts/read-system-opengl.rb, which CI runs on Windows 11 for
# ARM64 to keep true what lib/fledge/linkage/windows.yml says of it.
class SystemOpenGLTest < Minitest::Test
  ARM64X = "IMAGE_FILE_MACHINE_ARM64X"

  def test_both_dlls_as_arm64_or_arm64x_pass
    assert_empty SystemOpenGL.failures("opengl32.dll" => ARM64X, "glu32.dll" => "IMAGE_FILE_MACHINE_ARM64")
  end

  def test_a_missing_dll_fails
    assert_equal ["glu32.dll is not in System32"], SystemOpenGL.failures("opengl32.dll" => ARM64X)
  end

  def test_a_dll_for_another_processor_fails
    failures = SystemOpenGL.failures("opengl32.dll" => ARM64X, "glu32.dll" => "IMAGE_FILE_MACHINE_AMD64")
    assert_equal ['glu32.dll declares "IMAGE_FILE_MACHINE_AMD64", not ARM64 or ARM64X'], failures
  end

  def test_a_dll_llvm_readobj_could_not_read_fails
    refute_empty SystemOpenGL.failures("opengl32.dll" => ARM64X, "glu32.dll" => "llvm-readobj failed")
  end

  def test_the_machine_is_read_from_llvm_readobjs_file_headers
    output = "File: opengl32.dll\nFormat: COFF-ARM64X\nArch: aarch64\nImageFileHeader {\n  Machine: IMAGE_FILE_MACHINE_ARM64X (0xA64E)\n"
    assert_equal ARM64X, SystemOpenGL.machine(output)
    assert_nil SystemOpenGL.machine("Format: unknown\n")
  end

  # The check holds exactly the names windows.yml adds for ARM64.
  def test_the_dlls_it_checks_are_the_ones_the_generator_adds
    assert_equal WindowsDlls::ADDITIONS.fetch("windows-arm64").keys.sort, SystemOpenGL::DLLS.sort
  end
end
