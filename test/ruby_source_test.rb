# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "rbconfig"
require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The edits the mobile runtimes make to Ruby 4.1.0-preview1's source
# (doc/contributors/design/phone-runtimes.md, "Scripted edits to Ruby's
# source"), each against the lines of Ruby's own files it changes, and
# each failing loudly when a new Ruby no longer has those lines, so that
# moving the Ruby pin shows which edit to look at again.
class RubySourceTest < Minitest::Test
  Edits = RuntimeBuilder::RubySource

  def test_psych_stops_asking_pkg_config_for_the_build_machines_libyaml
    text = "  # default to pre-installed libyaml\nelsif pkg_config('yaml-0.1')\n  # found with pkg-config\n"

    assert_equal "  # default to pre-installed libyaml\nelsif false\n  # found with pkg-config\n", Edits.psych_extconf(text)
    assert_raises(RuntimeError) { Edits.psych_extconf("elsif have_library('yaml')\n") }
  end

  def test_the_crash_report_runs_no_command_where_there_is_no_system
    text = "        int r = system(buf);\n        if (r == -1) {\n"

    edited = Edits.vm_dump(text)
    assert_includes edited, "#if defined(HAVE_SYSTEM)\n        int r = system(buf);\n#else\n        int r = -1;\n#endif\n"
    assert_raises(RuntimeError) { Edits.vm_dump("int status = system(buf);\n") }
  end

  def test_configure_names_android_once
    text = "\ttarget_os=${target_os}-android\n"

    assert_equal "\tcase $target_os in *android*) ;; *) target_os=${target_os}-android ;; esac\n", Edits.configure(text)
    assert_raises(RuntimeError) { Edits.configure("target_os=${target_os}\n") }
  end

  # The check configure makes for a macOS deployment target of 10.6 or
  # later (generated from configure.ac, lines 439 to 451, at 4.1.0-preview1,
  # tab-indented as autoconf writes it). The iOS SDK's AvailabilityMacros.h
  # sets the macro to 10.5, so the edit makes the check apply only where
  # clang names a macOS deployment target.
  def test_configure_keeps_its_macos_minimum_check_for_a_macos_target_only
    check = "#include <AvailabilityMacros.h>\n\t#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6\n\t#error pre OS X 10.6\n" \
      "\t[!<===== pre OS X 10.6 =====>]\n\t#endif\n"

    assert_equal "#include <AvailabilityMacros.h>\n\t#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && " \
      "MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6\n\t#error pre OS X 10.6\n\t[!<===== pre OS X 10.6 =====>]\n\t#endif\n",
      Edits.configure_macos_minimum(check)
    assert_raises(RuntimeError) { Edits.configure_macos_minimum(check.sub("< __MAC_10_6", "< __MAC_10_7")) }
  end

  # An embedder names the file Ruby would derive its prefix from, as the
  # binary that holds libruby, since on Android that binary is in a folder
  # of native libraries alone, and an iOS app may keep Ruby's library
  # anywhere in its bundle.
  def test_ruby_lets_its_embedder_name_where_libruby_is
    text = "#elif defined(HAVE_DLADDR)\n    Dl_info dli;\n    VALUE fname, path;\n    const void* addr = (void *)(VALUE)expand_include_path;\n\n" \
      "    if (!dladdr((void *)addr, &dli)) {\n"

    edited = Edits.ruby_c(text)
    assert_includes edited, "    const void* addr = (void *)(VALUE)expand_include_path;\n\n" \
      "    extern const char *ruby_embed_libruby_path;\n    if (ruby_embed_libruby_path) return rb_str_new_cstr(ruby_embed_libruby_path);\n"
    assert_match(/\nconst char \*ruby_embed_libruby_path;\n\z/, edited)
    assert_raises(RuntimeError) { Edits.ruby_c("#elif defined(HAVE_DLADDR)\n    Dl_info info;\n") }
  end

  # An Android app's Ruby is given an argv its host allocates, so the
  # title $0= writes over it never reaches /proc/PID/cmdline. The edit
  # points setproctitle at the process's own argument area, which
  # /proc/self/stat names, once compat_init_setproctitle has measured the
  # argv it was given.
  def test_an_android_apps_ruby_titles_the_process_in_its_own_argument_area
    edited = Edits.setproctitle_c(SETPROCTITLE_LINES)

    assert_includes edited, "#if ALLOCATE_ENVIRON && defined(__ANDROID__)\n"
    assert_includes edited, "FILE *file = fopen(\"/proc/self/stat\", \"re\");\n"
    assert_includes edited, "&start, &end, &env_start, &env_end) != 4 || end <= start) return;\n"
    assert_includes edited, "    argv_len = argv_env_len = end - start;\n"
    assert_includes edited, "    if (env_start == end && env_end > env_start) argv_env_len = env_end - start;\n}\n#endif\n\n" \
      "void\ncompat_init_setproctitle(int argc, char *argv[])\n"
    assert_includes edited, "\talloc_environ[i] = environ[i] = NULL;\n#if defined(__ANDROID__)\n" \
      "\tfledge_use_process_argument_area(argv[0]);\n#endif\n#endif /* SPT_REUSEARGV */\n}\n"
    assert_raises(RuntimeError) { Edits.setproctitle_c(SETPROCTITLE_LINES.sub("NULL;\n#endif", "NULL;\n\n#endif")) }
    assert_raises(RuntimeError) { Edits.setproctitle_c(SETPROCTITLE_LINES.sub("int argc, char *argv[]", "int argc, char **argv")) }
  end

  # An iOS app's Ruby is given an argv its host allocates too, and Darwin
  # reads a process's arguments from the strings it started with, so the
  # edit has compat_init_setproctitle measure the process's own argv,
  # which _NSGetArgv keeps, before anything else.
  def test_an_ios_apps_ruby_titles_the_process_over_its_own_arguments
    edited = Edits.setproctitle_c(SETPROCTITLE_LINES)

    assert_includes edited, "#if ALLOCATE_ENVIRON && defined(__APPLE__)\n#include <crt_externs.h>\n#endif\n"
    assert_includes edited, "void\ncompat_init_setproctitle(int argc, char *argv[])\n{\n" \
      "#if ALLOCATE_ENVIRON && defined(__APPLE__)\n\tif (*_NSGetArgv() != NULL && argv != *_NSGetArgv()) {\n" \
      "\t\targc = *_NSGetArgc();\n\t\targv = *_NSGetArgv();\n\t}\n#endif\n\targv_env_len"
    assert_raises(RuntimeError) { Edits.setproctitle_c(SETPROCTITLE_LINES.sub("char *argv[])\n{", "char *argv[]) {")) }
  end

  # The edits each mobile runtime makes to Ruby's source: the title's on
  # both phones.
  def test_both_phones_title_their_process
    [RuntimeBuilder::IOS, RuntimeBuilder::Android].each do |builder|
      assert_includes builder.allocate.__send__(:edits), :setproctitle_c, builder.name
    end
  end

  # compat_init_setproctitle's first and last lines in
  # missing/setproctitle.c, lines 116 to 118 and 166 to 172 at
  # 4.1.0-preview1.
  SETPROCTITLE_LINES = "void\ncompat_init_setproctitle(int argc, char *argv[])\n{\n" \
    "\targv_env_len = lastenvp - argv[0];\n\n\tfor (i = 0; envp[i] != NULL; i++)\n" \
    "\t\talloc_environ[i] = environ[i] = ruby_strdup(envp[i]);\n\talloc_environ[i] = environ[i] = NULL;\n" \
    "#endif /* SPT_REUSEARGV */\n}\n"

  def test_applies_each_edit_to_its_file_in_a_source_tree
    Dir.mktmpdir do |source|
      FileUtils.mkdir_p(File.join(source, "ext", "psych"))
      File.write(File.join(source, "ext", "psych", "extconf.rb"), "elsif pkg_config('yaml-0.1')\n")
      File.write(File.join(source, "vm_dump.c"), "int r = system(buf);\n")

      Edits.apply(source, %i[psych_extconf vm_dump])

      assert_equal "elsif false\n", File.read(File.join(source, "ext", "psych", "extconf.rb"))
      assert_includes File.read(File.join(source, "vm_dump.c")), "#if defined(HAVE_SYSTEM)"
    end
  end

  # A linked extension of a bundled gem is found only once its gem is
  # active, as a desktop finds the gem's shared object only in its
  # folders: the gate goes into the lookup of linked extensions, with
  # each gem's extension and the gem it belongs to.
  def test_ruby_finds_a_gems_linked_extension_only_through_the_gate
    text = "typedef int (*feature_func)(void);\n\nstatic int\nsearch_required(const rb_box_t *box)\n{\n" \
      "            ftptr = RSTRING_PTR(lookup_name);\n" \
      "            if (st_lookup(&vm->static_ext_inits, (st_data_t)ftptr, NULL)) {\n"

    edited = Edits.load_c(text, { "racc/cparse.so" => "racc-1.8.1", "bigdecimal.so" => "bigdecimal-4.1.3" })
    assert_includes edited, "    {\"bigdecimal.so\", \"bigdecimal-4.1.3\"},\n    {\"racc/cparse.so\", \"racc-1.8.1\"},\n};\n"
    assert_includes edited,
      "if (st_lookup(&vm->static_ext_inits, (st_data_t)ftptr, NULL) && fledge_gem_extension_reachable_p(box, ftptr)) {\n"
    assert_operator edited.index("fledge_gem_extension_reachable_p(const rb_box_t"), :<, edited.index("search_required(const")
    assert_raises(RuntimeError) { Edits.load_c(text.sub("NULL)) {", "NULL) == 1) {"), { "nkf.so" => "nkf-0.3.0" }) }
    assert_raises(ArgumentError) { Edits.load_c(text, {}) }
  end

  # The gate's own C, compiled by this computer's mkmf against this
  # Ruby, with $LOAD_PATH for the expanded load path load.c reads: a
  # gem's extension is found only while a folder named for its gem is
  # on it, and any other extension always.
  # The iOS SDK lacks sys/vnode.h, which dir.c includes on Apple systems
  # for the vnode types; xord/cruby writes a stub with XNU's values.
  def test_writes_the_vnode_header_the_ios_sdk_lacks
    Dir.mktmpdir do |stub|
      Edits.write_vnode_stub(stub)

      assert_includes File.read(File.join(stub, "sys", "vnode.h")), "enum {VREG = 1, VDIR = 2, VLNK = 5, VT_HFS = 16, VT_CIFS = 23};"
    end
  end

  # Ruby's build never links a bundled gem's extension statically
  # (template/configure-ext.mk.tmpl builds .bundle/gems with
  # --no-extstatic), so each gem's extension is copied among Ruby's own,
  # to be linked in and registered in extinit.c, while the gem itself
  # stays a gem that RubyGems and Bundler see.
  def test_copies_each_bundled_gems_extension_among_rubys_own
    Dir.mktmpdir do |source|
      gem = -> (full, files) { files.each { |file| write(File.join(source, ".bundle", "gems", full, file), "x") } }
      gem.call("bigdecimal-4.0.1", %w[ext/bigdecimal/extconf.rb ext/bigdecimal/bigdecimal.c lib/bigdecimal.rb])
      gem.call("rbs-3.10.0", %w[ext/rbs_extension/extconf.rb include/rbs.h src/parser.c lib/rbs.rb])
      gem.call("fiddle-1.1.8", %w[ext/fiddle/extconf.rb])
      gem.call("win32ole-1.9.2", %w[ext/win32ole/extconf.rb])
      gem.call("csv-3.3.5", %w[lib/csv.rb])
      gem.call("racc-1.8.1", %w[ext/racc/cparse/extconf.rb ext/racc/cparse/test/extconf.rb])

      copied = RuntimeBuilder::BundledExtensions.copy(source, omit: %w[fiddle], recipe: ["true"])

      assert_equal({ "bigdecimal" => "bigdecimal-4.0.1", "racc" => "racc-1.8.1", "rbs" => "rbs-3.10.0" }, copied)
      assert_equal %w[bigdecimal bigdecimal-* fiddle fiddle-* racc racc-* rbs rbs-* win32ole win32ole-*],
        RuntimeBuilder::BundledExtensions.without(source)
      ext = File.join(source, "ext", "gems")
      copies = Dir.glob("**/*", base: ext).select { |path| File.file?(File.join(ext, path)) }.sort
      expected = %w[
        bigdecimal/ext/bigdecimal/bigdecimal.c
        bigdecimal/ext/bigdecimal/depend
        bigdecimal/ext/bigdecimal/extconf.rb
        bigdecimal/lib/bigdecimal.rb
        racc/ext/racc/cparse/depend
        racc/ext/racc/cparse/extconf.rb
        rbs/ext/rbs_extension/depend
        rbs/ext/rbs_extension/extconf.rb
        rbs/include/rbs.h
        rbs/lib/rbs.rb
        rbs/src/parser.c
      ]
      assert_equal expected, copies
    end
  end

  # A gem's own depend file keeps its rules, and the relocatable link's
  # follow them; an extension without one keeps the header dependencies
  # mkmf writes only when there is none. The rules' behavior is
  # BundledExtensionsTest's.
  def test_each_copied_extension_gets_the_relocatable_link_after_its_own_rules
    Dir.mktmpdir do |source|
      write(File.join(source, ".bundle/gems/fiddle-1.1.8/ext/fiddle/extconf.rb"), "x")
      write(File.join(source, ".bundle/gems/fiddle-1.1.8/ext/fiddle/depend"), "$(OBJS): $(FFI_H)\n")
      write(File.join(source, ".bundle/gems/prism-1.9.0/ext/prism/extconf.rb"), "x")

      RuntimeBuilder::BundledExtensions.copy(source, omit: [], recipe: ["$(CC) -r -o $@ $(FLEDGE_OBJS)", "strip $@"])

      fiddle = File.read(File.join(source, "ext/gems/fiddle/ext/fiddle/depend"))
      prism = File.read(File.join(source, "ext/gems/prism/ext/prism/depend"))
      assert fiddle.start_with?("$(OBJS): $(FFI_H)\n\nCFLAGS += -fno-common\n"), fiddle
      assert prism.start_with?("$(OBJS): $(HDRS) $(ruby_headers)\n\nCFLAGS += -fno-common\n"), prism
      assert_includes prism, "\n\t$(Q) $(CC) -r -o $@ $(FLEDGE_OBJS)\n\t$(Q) strip $@\n"
    end
  end

  # rbinstall.rb installs a bundled gem with an extension only when the
  # build marked its extension built (.bundle/extensions/PLATFORM/API/
  # FULL_NAME/gem.build_complete), and copies that folder to the gem's
  # extension folder, where RubyGems looks for the same file before it
  # will load the gem.
  # The gate in load.c needs the feature each copied extension is
  # registered as, which extmk takes from its extconf.rb's
  # create_makefile, and the gem it belongs to.
  def test_names_the_feature_of_each_copied_gems_extension
    Dir.mktmpdir do |source|
      write(File.join(source, "ext/gems/bigdecimal/ext/bigdecimal/extconf.rb"), "create_makefile('bigdecimal') {|mf|\n")
      write(File.join(source, "ext/gems/racc/ext/racc/cparse/extconf.rb"), "require 'mkmf'\ncreate_makefile 'racc/cparse'\n")
      write(File.join(source, "ext/gems/racc/ext/racc/cparse/test/extconf.rb"), "create_makefile 'test'\n")
      write(File.join(source, "ext/gems/syslog/ext/syslog/extconf.rb"), "if have_header('syslog.h')\n    create_makefile(\"syslog_ext\")\nend\n")
      gems = { "bigdecimal" => "bigdecimal-4.1.3", "racc" => "racc-1.8.1", "syslog" => "syslog-0.4.0" }

      expected = { "bigdecimal.so" => "bigdecimal-4.1.3", "racc/cparse.so" => "racc-1.8.1", "syslog_ext.so" => "syslog-0.4.0" }
      assert_equal expected, RuntimeBuilder::BundledExtensions.features(source, gems)
      write(File.join(source, "ext/gems/nkf/ext/nkf/extconf.rb"), "create_makefile(target)\n")
      assert_raises(RuntimeError) { RuntimeBuilder::BundledExtensions.features(source, { "nkf" => "nkf-0.3.0" }) }
    end
  end

  def test_marks_each_copied_gems_extension_built_where_rbinstall_and_rubygems_look
    Dir.mktmpdir do |build|
      RuntimeBuilder::BundledExtensions.mark_built(build, { "nkf" => "nkf-0.2.0" }, platform: "arm64-darwin", api: "4.0.0-static")

      assert_path_exists File.join(build, ".bundle/extensions/arm64-darwin/4.0.0-static/nkf-0.2.0/gem.build_complete")
    end
  end

  def test_an_installed_gem_without_its_specification_or_mark_fails
    Dir.mktmpdir do |gems|
      write(File.join(gems, "specifications", "nkf-0.2.0.gemspec"), "")
      write(File.join(gems, "extensions", "aarch64-linux-android", "4.0.0-static", "nkf-0.2.0", "gem.build_complete"), "")
      write(File.join(gems, "specifications", "racc-1.8.1.gemspec"), "")

      error = assert_raises(RuntimeError) do
        RuntimeBuilder::BundledExtensions.check_installed(gems, { "nkf" => "nkf-0.2.0", "racc" => "racc-1.8.1" },
          platform: "aarch64-linux-android", api: "4.0.0-static")
      end
      assert_equal "racc-1.8.1 was not installed as a gem with its extension marked built", error.message
    end
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
