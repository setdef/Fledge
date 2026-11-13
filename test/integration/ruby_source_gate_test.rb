# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "rbconfig"
require_relative "../test_helper"
require_relative "../../tasks/runtime_builder"

# The gate the phones' load.c edit adds (ADR 068), compiled with this
# computer's mkmf and Ruby: it finds a gem's linked extension only
# while the gem's extension folder is on $LOAD_PATH.
class RubySourceGateTest < Minitest::Test
  Edits = RuntimeBuilder::RubySource

  def test_the_gate_finds_a_gems_extension_while_a_folder_named_for_the_gem_is_on_the_load_path
    skip "the phones' runtimes are built on macOS and Linux" if Gem.win_platform?
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "gate.c"), GATE_HARNESS.sub("GATE\n", format(Edits::GATE, table: "    {\"gate.so\", \"gate-1.0.0\"},\n")))
      sh(dir, RbConfig.ruby, "-rmkmf", "-e", 'create_makefile("gate")')
      sh(dir, "make")

      assert_equal "[false, true, false, true]\n", sh(dir, RbConfig.ruby, "-e", format(GATE_SCRIPT, gate: File.join(dir, "gate").dump))
    end
  end

  # The features a require of an extension's file by its path or by
  # DLEXT (here ".bundle", as on iOS) turns into, where it finds no file:
  # each made relative to the folders on $LOAD_PATH that hold it, with
  # ".so"; none for a Ruby file, another extension, or a relative name
  # Ruby's own lookup has tried.
  def test_a_path_or_dlext_names_the_features_a_linked_extension_is_registered_as
    skip "the phones' runtimes are built on macOS and Linux" if Gem.win_platform?
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "linked.c"), LINKED_HARNESS.sub("LINKED\n", Edits::LINKED_FEATURES))
      sh(dir, RbConfig.ruby, "-rmkmf", "-e", 'create_makefile("linked")')
      sh(dir, "make")

      both = ["adder/adder.so", "lib/adder/adder.so"]
      expected = [both, both, both, ["syslog_ext.so"], ["adder/adder.so"], [], [], [], [], []]
      assert_equal "#{expected.inspect}\n", sh(dir, RbConfig.ruby, "-e", format(LINKED_SCRIPT, linked: File.join(dir, "linked").dump))
    end
  end

  # fledge_linked_features inside an extension of this Ruby's, with
  # iOS's DLEXT and stand-ins for load.c's own functions.
  LINKED_HARNESS = <<~C
    #include <ruby.h>
    #include <string.h>
    #undef DLEXT
    #define DLEXT ".bundle"
    typedef void rb_box_t;
    void *memrchr(const void *, int, size_t);
    static VALUE get_expanded_load_path(rb_box_t *box) { (void)box; return rb_gv_get("$LOAD_PATH"); }
    LINKED
    static VALUE features(VALUE self, VALUE name) { (void)self; return fledge_linked_features(NULL, name); }
    void Init_linked(void) { rb_define_global_function("fledge_linked_features", features, 1); }
  C

  # The names: a path with ".bundle", one with ".so", one in two folders
  # of $LOAD_PATH, one with no extension, and a relative ".bundle"; then
  # a relative ".so" and a relative name with none, which Ruby's own
  # lookup tried, a Ruby file, another extension, and a path under no
  # folder of $LOAD_PATH.
  LINKED_SCRIPT = <<~RUBY
    require %<linked>s
    $LOAD_PATH.unshift("/gems/adder-1.0.0/lib", "/gems/adder-1.0.0", "/ext/syslog-0.3.0")
    names = %%w[/gems/adder-1.0.0/lib/adder/adder.bundle /gems/adder-1.0.0/lib/adder/adder.so /gems/adder-1.0.0/lib/adder/adder
      /ext/syslog-0.3.0/syslog_ext adder/adder.bundle adder/adder.so adder/adder /gems/adder-1.0.0/lib/adder.rb
      /gems/adder-1.0.0/lib/adder.dylib /elsewhere/adder.bundle]
    p names.map { |name| fledge_linked_features(name) }
  RUBY

  # The gate inside an extension of this Ruby's, which load.c's own
  # get_expanded_load_path stands in for.
  GATE_HARNESS = <<~C
    #include <ruby.h>
    #include <string.h>
    typedef void rb_box_t;
    static VALUE get_expanded_load_path(rb_box_t *box) { (void)box; return rb_gv_get("$LOAD_PATH"); }
    GATE
    static VALUE reachable(VALUE self, VALUE feature) {
        (void)self;
        return fledge_gem_extension_reachable_p(NULL, StringValueCStr(feature)) ? Qtrue : Qfalse;
    }
    void Init_gate(void) { rb_define_global_function("fledge_gate_reachable?", reachable, 1); }
  C

  # What the gate answers for a gem's extension and etc's, before
  # the gem's folders are on $LOAD_PATH, beside a folder whose name only
  # starts with the gem's, and with the gem's extension folder.
  GATE_SCRIPT = <<~RUBY
    require %<gate>s
    before = [fledge_gate_reachable?("gate.so"), fledge_gate_reachable?("etc.so")]
    $LOAD_PATH << "/gems/extensions/arm64-darwin/4.1.0-static/gate-1.0.00" << "/gems/gate-1.0.0/lib"
    between = fledge_gate_reachable?("gate.so")
    $LOAD_PATH << "/gems/extensions/arm64-darwin/4.1.0-static/gate-1.0.0"
    p [*before, between, fledge_gate_reachable?("gate.so")]
  RUBY

  def sh(dir, *command)
    out, status = Open3.capture2e(*command, chdir: dir)
    assert status.success?, "#{command.join(' ')} failed:\n#{out}"
    out
  end
end
