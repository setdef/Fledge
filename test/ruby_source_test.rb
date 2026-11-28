# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "rbconfig"
require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The edits the mobile runtimes make to Ruby 4.1.0-preview1's source, each
# against the lines of Ruby's own files it changes, and each failing loudly when
# a new Ruby no longer has those lines, so that moving the Ruby pin shows which
# edit to look at again.
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

  # On Android a gem's command in the app's bin folder is a link to the
  # ruby program, since Android runs no script from an app's files, and
  # RubyGems' wrapper is kept beside it. Prism reads every Ruby file,
  # the main script, load, and require, through pm_load_file, so the
  # edit lets the embedder name the file to read in place of the one
  # asked for, which every message and __FILE__ still name.
  def test_prism_lets_its_embedder_read_a_command_in_place_of_its_link
    text = "VALUE\npm_load_file(pm_parse_result_t *result, VALUE filepath, bool load_error)\n{\n    pm_source_init_result_t init_result;\n" \
      "    result->source = pm_source_mapped_new(RSTRING_PTR(filepath), O_RDONLY | O_NONBLOCK, &init_result);\n\n    int err;\n" \
      "            .fd = rb_cloexec_open(RSTRING_PTR(filepath), args.open_mode, 0),\n"

    edited = Edits.prism_compile_c(text)
    assert_includes edited, "    pm_source_init_result_t init_result;\n    const char *source_path = RSTRING_PTR(filepath);\n#ifdef __ANDROID__\n" \
      "    char embed_source[4096];\n" \
      "    if (ruby_embed_source_path && ruby_embed_source_path(source_path, embed_source, sizeof embed_source)) source_path = embed_source;\n" \
      "#endif\n    result->source = pm_source_mapped_new(source_path, O_RDONLY | O_NONBLOCK, &init_result);\n"
    assert_includes edited, "            .fd = rb_cloexec_open(source_path, args.open_mode, 0),\n"
    assert_match(/\A#ifdef __ANDROID__\n#include <stddef.h>\nint \(\*ruby_embed_source_path\)\(const char \*, char \*, size_t\);\n#endif\n/, edited)
    # Elsewhere than Android it reads the path it is given, as before.
    assert_equal text.gsub("RSTRING_PTR(filepath), ", "source_path, ").sub("init_result;\n", "init_result;\n    const char *source_path = RSTRING_PTR(filepath);\n"),
      without_android(edited)
    assert_raises(RuntimeError) { Edits.prism_compile_c("VALUE\npm_load_file(pm_parse_result_t *result, VALUE filepath)\n{\n") }
  end

  # And parse.y's reader, which --parser=parse.y and a script's DATA use.
  def test_ruby_lets_its_embedder_read_a_command_in_place_of_its_link
    text = "        int mode = MODE_TO_LOAD;\n#if defined DOSISH || defined __CYGWIN__\n"

    edited = Edits.ruby_c_source(text)
    assert_includes edited, "        int mode = MODE_TO_LOAD;\n#ifdef __ANDROID__\n        char embed_source[4096];\n" \
      "        extern int (*ruby_embed_source_path)(const char *, char *, size_t);\n" \
      "        if (ruby_embed_source_path && ruby_embed_source_path(fname, embed_source, sizeof embed_source)) fname = embed_source;\n#endif\n"
    assert_equal text, without_android(edited), "elsewhere than Android ruby.c is as it was"
    assert_raises(RuntimeError) { Edits.ruby_c_source("        int mode = O_RDONLY;\n") }
  end

  # +text+ as a compiler for a system other than Android reads it: without
  # each <tt>#ifdef __ANDROID__</tt> block.
  private def without_android(text)
    text.gsub(/^#ifdef __ANDROID__\n.*?^#endif\n/m, "")
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

  # An edit that takes a fix from Ruby's master leaves a Ruby that
  # already has the fix as it is, so a snapshot of master builds with
  # the edits the pinned release needs: Ruby's master of 2026-11-20
  # (21ee43fb1e) has both fixes, in these lines.
  def test_an_edit_that_takes_a_fix_from_master_leaves_a_ruby_that_has_it_alone
    fork = "static void\nrelease_fork_lock_after_fork(rb_pid_t pid)\n{\n    if (pid == 0) {\n" \
      "        rb_thread_reset_fork_lock();\n    }\n    else {\n        rb_thread_release_fork_lock();\n    }\n}\n"
    thread = "    if (threadptr_initialized(target_th) && target_th->has_dedicated_nt &&\n" \
      "        target_th->status != THREAD_KILLED) {\n        native_set_another_thread_name(target_th->nt->thread_id, name);\n"

    assert_equal fork, Edits.process_c(fork)
    assert_equal thread, Edits.thread_c(thread)
  end

  # A linked extension of a bundled gem is found only once its gem is
  # active, as a desktop finds the gem's shared object only in its
  # folders: the gate goes into the lookup of linked extensions, with
  # each gem's extension and the gem it belongs to.
  def test_ruby_finds_a_gems_linked_extension_only_through_the_gate
    text = "typedef int (*feature_func)(void);\n\nstatic int\nsearch_required(const rb_box_t *box)\n{\n" \
      "            ftptr = RSTRING_PTR(lookup_name);\n" \
      "            if (st_lookup(&vm->static_ext_inits, (st_data_t)ftptr, NULL)) {\n" \
      "                return 's';\n            }\n        }\n    }\n\n    switch (type) {\n"

    edited = Edits.load_c(text, { "racc/cparse.so" => "racc-1.8.1", "bigdecimal.so" => "bigdecimal-4.1.3" })
    assert_includes edited, "    {\"bigdecimal.so\", \"bigdecimal-4.1.3\"},\n    {\"racc/cparse.so\", \"racc-1.8.1\"},\n    {NULL, NULL},\n};\n"
    assert_includes edited,
      "if (st_lookup(&vm->static_ext_inits, (st_data_t)ftptr, NULL) && fledge_gem_extension_reachable_p(box, ftptr)) {\n"
    assert_operator edited.index("fledge_gem_extension_reachable_p(const rb_box_t"), :<, edited.index("search_required(const")
    assert_raises(RuntimeError) { Edits.load_c(text.sub("NULL)) {", "NULL) == 1) {"), { "nkf.so" => "nkf-0.3.0" }) }
  end

  # A Ruby that links no bundled gem's extension in, as Android's builds
  # each one as a file, gets a gate with no gem in it, which lets the
  # app's own linked extensions through.
  def test_a_ruby_with_no_linked_gem_extension_gets_a_gate_that_guards_none
    text = "static int\nsearch_required(const rb_box_t *box)\n{\n" \
      "            if (st_lookup(&vm->static_ext_inits, (st_data_t)ftptr, NULL)) {\n" \
      "                return 's';\n            }\n        }\n    }\n\n    switch (type) {\n"

    assert_includes Edits.load_c(text, {}), "static const char *const fledge_gem_extensions[][2] = {\n    {NULL, NULL},\n};\n"
  end

  # The gate's loop stops at the row of NULLs, so the gate's own C ends
  # the table it is given: a table without that row would have the loop
  # read past it, which a compiler may take as leave to assume the first
  # row always matches.
  def test_the_gate_ends_the_table_it_is_given
    assert_includes format(Edits::GATE, table: "    {\"gate.so\", \"gate-1.0.0\"},\n"),
      "    {\"gate.so\", \"gate-1.0.0\"},\n    {NULL, NULL},\n};\n"
  end

  # Android's package installer extracts only lib*.so, so a shared Ruby
  # for Android is named, and needed by its extensions, without Linux's
  # version (the lines configure generates from configure.ac, lines 3618
  # to 3626 at 4.1.0-preview1, tab-indented as autoconf writes them).
  def test_configure_names_androids_shared_ruby_without_a_version
    linux = "  linux* | gnu* | haiku*) :\n\n\t# RUBY_APPEND_OPTIONS(LIBRUBY_DLDFLAGS)\n\tdone\n" \
      "\tLIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'\n\tif test \"$load_relative\" = yes\n"
    freebsd = "  freebsd*) :\n\tLIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'\n"

    edited = Edits.configure_soname(linux + freebsd)
    assert_includes edited, "\tLIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'\n\tLIBRUBY_SO='lib$(RUBY_SO_NAME).$(SOEXT)'\n" \
      "\tLIBRUBY_SONAME='$(LIBRUBY_SO)'\n\tLIBRUBY_ALIASES=''\n\tif test"
    assert edited.end_with?(freebsd)
    assert_raises(RuntimeError) { Edits.configure_soname(freebsd) }
  end

  # The openssl extension, which links OpenSSL in on Android, sends
  # OpenSSL's every call of X509_get_default_cert_file to Fledge's, with
  # the flag added to its link after its checks.
  def test_the_openssl_extension_links_with_fledges_default_certificates
    text = "create_header\ncreate_makefile(\"openssl\")\nLogging::message \"Done.\\n\"\n"

    assert_equal "create_header\n$DLDFLAGS << \" -Wl,--wrap=X509_get_default_cert_file\"\ncreate_makefile(\"openssl\")\n" \
      "Logging::message \"Done.\\n\"\n", Edits.openssl_extconf(text)
    assert_raises(RuntimeError) { Edits.openssl_extconf("create_makefile('openssl')\n") }
  end

  # A require of a linked extension's file by its path or by DLEXT, which
  # finds no file, looks the extension up by the feature it is registered
  # as: after Ruby's own lookup of linked extensions, before the switch on
  # the file it found, with the function that names the features before
  # search_required.
  def test_ruby_finds_a_linked_extension_by_the_path_of_its_file
    text = "static int\nsearch_required(const rb_box_t *box)\n{\n" \
      "            if (st_lookup(&vm->static_ext_inits, (st_data_t)ftptr, NULL)) {\n" \
      "                return 's';\n            }\n        }\n    }\n\n    switch (type) {\n"

    edited = Edits.load_c(text, { "racc/cparse.so" => "racc-1.8.1" })
    assert_includes edited, "                return 's';\n            }\n        }\n        if (type == 0) {\n" \
      "            VALUE fledge_features = fledge_linked_features(box, tmp);\n"
    assert_includes edited, "            }\n        }\n    }\n\n    switch (type) {\n"
    assert_operator edited.index("fledge_linked_features(const rb_box_t"), :<, edited.index("search_required(const")
    assert_raises(RuntimeError) { Edits.load_c(text.sub("    switch (type)", "    switch (kind)"), { "nkf.so" => "nkf-0.3.0" }) }
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

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
