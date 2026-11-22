# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "shellwords"

module Fledge
  class NativeBuild
    # What a gem's build tells bindgen, which rb-sys runs to declare Ruby's
    # C API in Rust, of the flag that sets the width of +rb_len_t+, so
    # that a Rust gem binds the type the runtime's Ruby has.
    #
    # Ruby 4.1's +rb_len_t+ is +int64_t+ when +SIZEOF_RB_LEN_T+ is defined
    # wider than +long+, and +long+ otherwise
    # (<tt>include/ruby/internal/value.h</tt>), and RubyInstaller's head
    # build says so only in RbConfig's +CPPFLAGS+. rb-sys gives bindgen
    # those flags, but reads them from +RBCONFIG_CPPFLAGS+, which the
    # rb_sys gem's Makefile exports beside an empty +RBCONFIG_cppflags+,
    # and Windows keeps one of the two names, the empty one, for cargo's
    # build script. bindgen adds to its arguments what
    # +BINDGEN_EXTRA_CLANG_ARGS+ holds (or that name followed by the Rust
    # target, which it reads first: +get_target_dependent_env_var+, at
    # bindgen 0.72.1), so the flag goes there, after whatever the
    # developer set.
    #
    # Only that flag: every bindgen in the gem's cargo build reads the
    # variable, a crate's bindings of its own C library included, and
    # RbConfig's other flags (+_FILE_OFFSET_BITS+, +_WIN32_WINNT+) change
    # what the system's headers declare there, where the library's C,
    # compiled without them, would disagree. This file is the start of
    # NativeBuild::SCRIPT, which the runtime's Ruby runs.
    module Bindgen
      # The variable bindgen reads extra arguments to clang from.
      NAME = "BINDGEN_EXTRA_CLANG_ARGS"

      # The flag of RbConfig's +CPPFLAGS+ that sets +rb_len_t+'s width.
      FLAG = /\A-DSIZEOF_RB_LEN_T=/

      # The variables of +env+ to change, with their new values, for a Ruby
      # whose +CPPFLAGS+ are +cppflags+: none when they leave +rb_len_t+
      # as +long+, else the plain name and each name for a target that
      # +env+ sets, in any case, as Windows reads names, each with the
      # flag after the value +env+ gives it.
      def self.env(env, cppflags)
        flags = cppflags.shellsplit.grep(FLAG)
        return {} if flags.empty?

        names = env.keys.select { |name| name.upcase == NAME || name.upcase.start_with?("#{NAME}_") }
        names.unshift(NAME) unless names.any? { |name| name.upcase == NAME }
        names.to_h { |name| [name, [env[name], *flags].compact.join(" ")] }
      end
    end
  end
end
