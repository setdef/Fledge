# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "rbconfig"
require_relative "../test_helper"

# The file a phone's app has where a desktop has a gem's extension
# (Fledge::MobileExtensions::Stub), run by this computer's Ruby. A phone's
# extension is linked in and found by its feature alone; here a folder on
# $LOAD_PATH after the gem's, holding the compiled extension, stands in
# for that, and the gem's own lib/ holds only its Ruby and the stub, as
# on a phone.
# The Mobile apps jobs run examples/native_phone, whose gem's Ruby
# require_relatives its extension, on each phone.
class MobileExtensionStubTest < Minitest::Test
  EXTENSION = <<~C
    #include <ruby.h>
    void Init_stubbed(void) {
        rb_define_module("Stubbed");
        rb_gv_set("$stubbed_inits", INT2FIX(NUM2INT(rb_gv_get("$stubbed_inits")) + 1));
    }
  C

  # The gem's Ruby as Bundler's template wrote it from 2.2.0 to 4.0.0
  # (lib/bundler/templates/newgem/lib/newgem.rb.tt, line 5).
  GEM = <<~RUBY
    require_relative "stubbed/stubbed"
  RUBY

  # The gem loaded by its path, as require_relative asks for it, then
  # again by its path and by its feature: the extension initializes once,
  # and each later require says it is loaded.
  SCRIPT = <<~RUBY
    $stubbed_inits = 0
    lib = ARGV.fetch(0)
    first = require File.join(lib, "stubbed")
    again = require File.join(lib, "stubbed", "stubbed")
    feature = require "stubbed/stubbed"
    p [first, defined?(Stubbed), $stubbed_inits, again, feature]
  RUBY

  def test_a_require_of_the_extensions_path_loads_the_extension_by_its_feature
    skip "the phones' extensions are compiled on macOS and Linux" if Gem.win_platform?
    Dir.mktmpdir do |dir|
      linked = File.join(dir, "linked")
      compile(File.join(dir, "ext"), into: File.join(linked, "stubbed"))
      lib = File.join(dir, "gem", "lib")
      FileUtils.mkdir_p(File.join(lib, "stubbed"))
      File.write(File.join(lib, "stubbed.rb"), GEM)
      File.write(File.join(lib, "stubbed", "stubbed.rb"), Fledge::MobileExtensions::Stub.source("stubbed/stubbed"))

      out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-I", linked, "-e", SCRIPT, lib)

      assert status.success?, out
      assert_equal "[true, \"constant\", 1, false, false]\n", out
    end
  end

  # The extension compiled with this Ruby's mkmf, as stubbed/stubbed, into
  # the folder +into+.
  def compile(dir, into:)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "stubbed.c"), EXTENSION)
    sh(dir, RbConfig.ruby, "-rmkmf", "-e", 'create_makefile("stubbed/stubbed")')
    sh(dir, "make")
    FileUtils.mkdir_p(into)
    FileUtils.cp(File.join(dir, "stubbed.#{RbConfig::CONFIG['DLEXT']}"), into)
  end

  def sh(dir, *command)
    out, status = Open3.capture2e(*command, chdir: dir)
    assert status.success?, "#{command.join(' ')} failed:\n#{out}"
  end
end
