# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"

class RuntimeBuilder
  # The edits a mobile runtime makes to Ruby's own source before it builds
  # it (doc/contributors/design/phone-runtimes.md, "Scripted edits to
  # Ruby's source"). Each replaces lines of Ruby 4.1.0-preview1's files
  # that it names, and raises when they are not there, so that a new Ruby
  # whose files moved on fails the build at the edit to look at again,
  # rather than building a Ruby that is quietly different.
  module RubySource
    # The file each edit changes, relative to Ruby's source.
    FILES = {
      psych_extconf: "ext/psych/extconf.rb",
      vm_dump: "vm_dump.c",
      configure: "configure",
      configure_macos_minimum: "configure",
      ruby_c: "ruby.c",
      load_c: "load.c",
    }.freeze

    # Applies the edits named in +edits+ (keys of FILES) to the source
    # tree +source+.
    def self.apply(source, edits)
      edits.each { |edit| edit(source, edit) }
    end

    # Applies the one edit +edit+ (a key of FILES), given the arguments
    # after the file's text, to the source tree +source+.
    def self.edit(source, edit, *)
      path = File.join(source, FILES.fetch(edit))
      File.write(path, public_send(edit, File.read(path), *))
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
    # Android (configure.ac, line 617 at 4.1.0-preview1), so a --host of
    # aarch64-linux-android gives a RUBY_PLATFORM of
    # aarch64-linux-android-android. Termux guards the line
    # (termux-packages, packages/ruby/android-sdk-level.patch); this guards
    # it in the generated configure, which needs no autoreconf.
    def self.configure(text)
      replace(text, /^(\s*)target_os=\$\{target_os\}-android$/,
        "\\1case $target_os in *android*) ;; *) target_os=${target_os}-android ;; esac", "configure appends -android")
    end

    # configure refuses a darwin target whose MAC_OS_X_VERSION_MIN_REQUIRED
    # is below 10.6 (configure.ac, lines 439 to 451 at 4.1.0-preview1, from
    # ruby/ruby 3e96f16643, "Require Mac OS X 10.6 or later"). An iOS
    # target is darwin too, and the iOS SDK's AvailabilityMacros.h, given
    # no macOS deployment target by clang
    # (__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__), sets the macro to
    # 10.5 (lines 96 to 111), so configure stops with "Unsupported OS X
    # version is required". This keeps the check for a macOS target only,
    # in the generated configure, which needs no autoreconf.
    def self.configure_macos_minimum(text)
      replace(text, /^(\s*)#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6$/,
        "\\1#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6",
        "configure requires Mac OS X 10.6")
    end

    # Built with --enable-load-relative, Ruby derives its prefix from the
    # path of the file that holds libruby (ruby.c, runtime_libruby_path,
    # lines 594 to 663 at 4.1.0-preview1). On Android that file sits in a folder
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

    # The gate before load.c's lookup of statically linked extensions
    # (search_required, lines 1199 to 1218 at 4.1.0-preview1), which a
    # require that finds no file reaches. +extensions+ is the full name of
    # the bundled gem each linked extension belongs to, by the feature
    # its gem requires it as (bigdecimal.so). A desktop Ruby finds a
    # gem's shared object only in the gem's own folders, which RubyGems
    # adds to $LOAD_PATH as it activates the gem (Gem::BasicSpecification#full_require_paths,
    # lib/rubygems/basic_specification.rb, lines 184 to 195): the gem's
    # extension folder, named for the gem's full name, among them. So
    # the gate lets the lookup find a gem's linked extension only while
    # a folder of that name is on $LOAD_PATH. Without it, a plain
    # require "bigdecimal" finds the linked bigdecimal.so before RubyGems
    # activates the gem, whose lib/bigdecimal.rb then never loads
    # (lib/rubygems/core_ext/kernel_require.rb, lines 79 to 81 and 138 to
    # 148: RubyGems tries Ruby's own require first, and activates a gem
    # only when that fails).
    def self.load_c(text, extensions)
      raise ArgumentError, "the gate needs a gem's extension to guard" if extensions.empty?

      table = extensions.sort.map { |feature, full| "    {#{feature.dump}, #{full.dump}},\n" }.join
      gated = replace(text, /^(            if \(st_lookup\(&vm->static_ext_inits, \(st_data_t\)ftptr, NULL\))\) \{\n/,
        "\\1 && fledge_gem_extension_reachable_p(box, ftptr)) {\n", "search_required looks up a linked extension")
      replace(gated, /^static int\nsearch_required\(/, "#{format(GATE, table:)}\nstatic int\nsearch_required(",
        "load.c defines search_required")
    end

    # The gate's C, before search_required; %<table>s is each gem's
    # extension feature with its gem's full name.
    GATE = <<~C
      /* Fledge: each bundled gem's extension this Ruby links in, by the
         feature it is registered as, with the full name of its gem. */
      static const char *const fledge_gem_extensions[][2] = {
      %<table>s};

      /* Whether the linked extension +feature+ may be found: always, but for
         a gem's, which only while a folder named for its gem is on
         $LOAD_PATH, as RubyGems puts the gem's extension folder there when
         it activates the gem. */
      static int
      fledge_gem_extension_reachable_p(const rb_box_t *box, const char *feature)
      {
          for (size_t i = 0; i < sizeof(fledge_gem_extensions) / sizeof(fledge_gem_extensions[0]); i++) {
              if (strcmp(feature, fledge_gem_extensions[i][0]) != 0) continue;
              const char *gem = fledge_gem_extensions[i][1];
              long length = (long)strlen(gem);
              VALUE load_path = get_expanded_load_path((rb_box_t *)box);
              for (long j = 0; j < RARRAY_LEN(load_path); j++) {
                  VALUE folder = RARRAY_AREF(load_path, j);
                  const char *name = RSTRING_PTR(folder);
                  long size = RSTRING_LEN(folder);
                  if (size > length && name[size - length - 1] == '/' && memcmp(name + size - length, gem, length) == 0) return 1;
              }
              return 0;
          }
          return 1;
      }
    C

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
