# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The edits the mobile runtimes make to Ruby 4.0.9's source (ADR 011,
# section 3), each against the lines of Ruby's own files it changes, and
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

      copied = RuntimeBuilder::BundledExtensions.copy(source, omit: %w[fiddle])

      assert_equal({ "bigdecimal" => "bigdecimal-4.0.1", "racc" => "racc-1.8.1", "rbs" => "rbs-3.10.0" }, copied)
      assert_equal %w[bigdecimal bigdecimal-* fiddle fiddle-* racc racc-* rbs rbs-* win32ole win32ole-*],
        RuntimeBuilder::BundledExtensions.without(source)
      ext = File.join(source, "ext", "gems")
      copies = Dir.glob("**/*", base: ext).select { |path| File.file?(File.join(ext, path)) }.sort
      expected = %w[
        bigdecimal/ext/bigdecimal/bigdecimal.c
        bigdecimal/ext/bigdecimal/extconf.rb
        bigdecimal/lib/bigdecimal.rb
        racc/ext/racc/cparse/extconf.rb
        rbs/ext/rbs_extension/extconf.rb
        rbs/include/rbs.h
        rbs/lib/rbs.rb
        rbs/src/parser.c
      ]
      assert_equal expected, copies
    end
  end

  # rbinstall.rb installs a bundled gem with an extension only when the
  # build marked its extension built (.bundle/extensions/PLATFORM/API/
  # FULL_NAME/gem.build_complete), and copies that folder to the gem's
  # extension folder, where RubyGems looks for the same file before it
  # will load the gem.
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
