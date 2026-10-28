# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

class RuntimeBuilder
  # The edits a mobile runtime makes to Ruby's own source before it builds
  # it (ADR 011, section 3). Each replaces lines of Ruby 4.0.9's files
  # that it names, and raises when they are not there, so that a new Ruby
  # whose files moved on fails the build at the edit to look at again,
  # rather than building a Ruby that is quietly different.
  module RubySource
    # The file each edit changes, relative to Ruby's source.
    FILES = {
      psych_extconf: "ext/psych/extconf.rb",
      vm_dump: "vm_dump.c",
      configure: "configure",
      ruby_c: "ruby.c",
    }.freeze

    # Applies the edits named in +edits+ (keys of FILES) to the source
    # tree +source+.
    def self.apply(source, edits)
      edits.each do |edit|
        path = File.join(source, FILES.fetch(edit))
        File.write(path, public_send(edit, File.read(path)))
      end
    end

    # psych's extconf.rb prefers pkg-config's yaml-0.1, which is the
    # build machine's libyaml (Homebrew's, on a Mac), over the libyaml
    # the build names with --with-libyaml-dir; xord/cruby's Rakefile
    # (lines 312 to 317, at 11d62c4) makes the same edit.
    def self.psych_extconf(text)
      replace(text, /^elsif pkg_config\(['"]yaml-[\d.]+['"]\)$/, "elsif false", "psych's extconf.rb asks pkg-config for yaml-0.1")
    end

    # vm_dump.c starts the command in RUBY_ON_BUG with system() when Ruby
    # crashes; iOS has no system(), and configure is told so
    # (ac_cv_func_system=no), as in xord/cruby's Rakefile (lines 299 to
    # 310).
    def self.vm_dump(text)
      replace(text, /^(\s*)int r = system\(buf\);\n/,
        "#if defined(HAVE_SYSTEM)\n\\1int r = system(buf);\n#else\n\\1int r = -1;\n#endif\n", "vm_dump.c calls system(buf)")
    end

    # configure appends -android to a target system that already names
    # Android (configure.ac, line 581 at 4.0.9), so a --host of
    # aarch64-linux-android gives a RUBY_PLATFORM of
    # aarch64-linux-android-android. Termux guards the line
    # (termux-packages, packages/ruby/android-sdk-level.patch); this guards
    # it in the generated configure, which needs no autoreconf.
    def self.configure(text)
      replace(text, /^(\s*)target_os=\$\{target_os\}-android$/,
        "\\1case $target_os in *android*) ;; *) target_os=${target_os}-android ;; esac", "configure appends -android")
    end

    # Built with --enable-load-relative, Ruby derives its prefix from the
    # path of the file that holds libruby (ruby.c, runtime_libruby_path,
    # lines 591 to 664 at 4.0.9). On Android that file sits in a folder
    # of native libraries alone, and an iOS app may keep Ruby's library
    # anywhere in its bundle, so ruby_embed_libruby_path lets the embedder
    # name the path Ruby would otherwise read from dladdr.
    def self.ruby_c(text)
      edited = replace(text, /^(#elif defined\(HAVE_DLADDR\)\n    Dl_info dli;\n    VALUE fname, path;\n    const void\* addr = .*\n)\n/,
        "\\1\n    extern const char *ruby_embed_libruby_path;\n" \
          "    if (ruby_embed_libruby_path) return rb_str_new_cstr(ruby_embed_libruby_path);\n\n",
        "ruby.c finds libruby with dladdr")
      "#{edited}\nconst char *ruby_embed_libruby_path;\n"
    end

    # Writes sys/vnode.h into the folder +stub+, which a build puts first
    # on its include path: the iOS SDK lacks it, and dir.c includes it on
    # Apple systems for the vnode types and file system tags it uses.
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT
    # SPDX-SnippetCopyrightText: 2014 xord.org
    # SPDX-SnippetComment: The stub sys/vnode.h from xord/cruby's Rakefile,
    #   lines 553 to 560, at 11d62c4.
    #++
    VNODE = <<~H
      #ifndef DUMMY_VNODE_H_INCLUDED
      #define DUMMY_VNODE_H_INCLUDED
      enum {VREG = 1, VDIR = 2, VLNK = 5, VT_HFS = 16, VT_CIFS = 23};
      #endif
    H
    #--
    # SPDX-SnippetEnd
    #++

    def self.write_vnode_stub(stub)
      FileUtils.mkdir_p(File.join(stub, "sys"))
      File.write(File.join(stub, "sys", "vnode.h"), VNODE)
    end

    private_class_method def self.replace(text, pattern, replacement, what)
      raise "Ruby's source has changed: an edit expects #{what}, and it does not" unless text.match?(pattern)

      text.sub(pattern, replacement)
    end
  end
end
