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
