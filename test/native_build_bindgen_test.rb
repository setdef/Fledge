# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# What a gem's build tells bindgen of Ruby's preprocessor flags, so that a
# Rust gem's bindings declare rb_len_t as the runtime's Ruby has it
# (doc/contributors/design/gems.md, "Rust gems on Windows and
# rb_len_t"); no Ruby is started.
class NativeBuildBindgenTest < Minitest::Test
  # RbConfig::CONFIG["CPPFLAGS"] of the x64 Windows runtime, RubyInstaller's
  # head build, as read there.
  WINDOWS = " -DSIZEOF_RB_LEN_T=8 -D_WIN32_WINNT=0x0600 -D__MINGW_USE_VC2005_COMPAT -D_FILE_OFFSET_BITS=64 "

  def env(from, cppflags = WINDOWS)
    Fledge::NativeBuild::Bindgen.env(from, cppflags)
  end

  def test_bindgen_learns_the_width_of_rb_len_t
    assert_equal({ "BINDGEN_EXTRA_CLANG_ARGS" => "-DSIZEOF_RB_LEN_T=8" }, env({ "PATH" => "/bin" }))
  end

  # The variable reaches every bindgen in the gem's cargo build, not
  # only rb-sys's, and the other flags set what the C library's own
  # headers declare (off_t's width, which Windows API a header offers).
  def test_no_flag_but_rubys_own_reaches_bindgen
    refute_match(/_FILE_OFFSET_BITS|_WIN32_WINNT|MINGW/, env({}).fetch("BINDGEN_EXTRA_CLANG_ARGS"))
  end

  def test_the_developers_own_arguments_come_first
    found = env({ "BINDGEN_EXTRA_CLANG_ARGS" => "--target=x86_64-pc-windows-gnu --sysroot=C:/msys64/ucrt64" })

    assert_equal({ "BINDGEN_EXTRA_CLANG_ARGS" => "--target=x86_64-pc-windows-gnu --sysroot=C:/msys64/ucrt64 -DSIZEOF_RB_LEN_T=8" }, found)
  end

  # bindgen reads BINDGEN_EXTRA_CLANG_ARGS_<TARGET>, or the same with the
  # target's dashes as underscores, before the plain name, and only the
  # first it finds (get_target_dependent_env_var, bindgen 0.72.1).
  def test_a_variable_for_the_target_gets_the_flag_too
    found = env({ "BINDGEN_EXTRA_CLANG_ARGS_x86_64-pc-windows-gnu" => "--sysroot=C:/a", "BINDGEN_EXTRA_CLANG_ARGS_aarch64_pc_windows_gnullvm" => "--sysroot=C:/b" })

    assert_equal({
      "BINDGEN_EXTRA_CLANG_ARGS" => "-DSIZEOF_RB_LEN_T=8",
      "BINDGEN_EXTRA_CLANG_ARGS_x86_64-pc-windows-gnu" => "--sysroot=C:/a -DSIZEOF_RB_LEN_T=8",
      "BINDGEN_EXTRA_CLANG_ARGS_aarch64_pc_windows_gnullvm" => "--sysroot=C:/b -DSIZEOF_RB_LEN_T=8",
    }, found)
  end

  # Windows reads environment names in any case, so a value set as
  # bindgen_extra_clang_args is the one bindgen would read.
  def test_a_name_in_another_case_keeps_its_value
    assert_equal({ "bindgen_extra_clang_args" => "--sysroot=C:/a -DSIZEOF_RB_LEN_T=8" }, env({ "bindgen_extra_clang_args" => "--sysroot=C:/a" }))
  end

  # The macOS and Linux runtimes' CPPFLAGS, where rb_len_t is long.
  def test_nothing_changes_for_a_ruby_whose_flags_leave_rb_len_t_long
    assert_empty env({ "BINDGEN_EXTRA_CLANG_ARGS" => "--sysroot=/x" }, "  -D_FORTIFY_SOURCE=2 -D_FILE_OFFSET_BITS=64 ")
  end

  def test_the_build_script_tells_bindgen_before_it_installs_a_gem
    script = Fledge::NativeBuild::SCRIPT

    assert_operator script.index("ENV.update(Fledge::NativeBuild::Bindgen.env(ENV.to_h, RbConfig::CONFIG.fetch(\"CPPFLAGS\", \"\")))"), :<,
      script.index("Gem::Installer.at")
  end
end
