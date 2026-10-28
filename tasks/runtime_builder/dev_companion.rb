# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

class RuntimeBuilder
  # A runtime's build-only companion (ADR 006): what compiling a gem's
  # extension against the runtime's Ruby needs and no app holds, Ruby's
  # headers and the library to link against, with their notices.
  module DevCompanion
    # What a runtime's build-only companion explains about itself, before
    # the text of Ruby's license (DEV-NOTICES.txt).
    DEV_NOTICE = <<~TEXT
      THE RUNTIME'S BUILD-ONLY FILES

      This archive unpacks over the Fledge runtime of the same name. It holds
      what that runtime prunes because no running app reads it, and what
      compiling a gem's C or Rust extension against the runtime's own Ruby
      needs: Ruby's C headers, and Ruby's library to link against, which is
      static libruby on macOS and Linux (whose extension builds link test
      programs against it) and the import library of Ruby's DLL on Windows
      (ADR 006). fledge build uses them to compile gems on the platform it
      builds for, and never copies them into an app.

      They are Ruby's, under Ruby's license (Ruby OR BSD-2-Clause), and
      static libruby holds the Rust standard library too, compiled into
      YJIT (MIT OR Apache-2.0). Their texts follow.
    TEXT

    # Copies, from the Ruby tree +tree+ (rv-ruby's prefix, or RubyInstaller's
    # tree), what the build-only companion holds into +dev+, laid out as the
    # runtime lays out Ruby (in ruby\ on Windows): include/, and the library
    # extension builds link against, which is lib/*.dll.a on Windows, the
    # import library of Ruby's DLL, and lib/libruby*-static.a elsewhere. A
    # static Ruby's extensions themselves link no libruby (mkmf leaves
    # LIBRUBYARG empty unless Ruby is shared), but mkmf links the test
    # programs of have_func and the rest against LIBRUBYARG_STATIC, so an
    # extconf.rb that checks for a function (nokogiri's) fails without it.
    # No other static library comes along: rv-ruby's lib/libcrypt.a is
    # libxcrypt, which is LGPL. Then DEV-NOTICES.txt, with Ruby's license
    # and, beside a static libruby, Rust's.
    def self.copy(tree, dev, windows:)
      ruby = windows ? File.join(dev, "ruby") : dev
      FileUtils.mkdir_p(File.join(ruby, "lib"))
      FileUtils.cp_r(File.join(tree, "include"), File.join(ruby, "include"))
      FileUtils.cp(Dir.glob(File.join(tree, "lib", windows ? "*.dll.a" : "libruby*-static.a")), File.join(ruby, "lib"))
      notices = [%w[ruby COPYING], %w[ruby BSDL], *(windows ? [] : [%w[rust COPYRIGHT], %w[rust LICENSE-MIT], %w[rust LICENSE-APACHE]])]
      licenses = notices.map { |folder, name| File.read(File.join(ROOT, "runtime", "notices", folder, name)) }
      File.write(File.join(dev, "DEV-NOTICES.txt"), [DEV_NOTICE, *licenses].join("\n#{'=' * 72}\n\n"))
    end
  end
end
