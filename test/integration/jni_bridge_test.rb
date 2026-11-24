# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "open3"
require "tmpdir"
require_relative "../test_helper"

# The Android runtime's bridge from Ruby to Java
# (runtime/mobile/vendor_ruby/fledge/jni.rb;
# doc/contributors/design/phone-widgets.md), run against a desktop
# Java VM, whose JNI is the one Android's ART implements: a Ruby of its
# own makes the VM with JNI_CreateJavaVM, names it to the bridge, and
# reports what the bridge did. Android's views are Android's alone; the
# mobile parity check runs an app that draws with them on an emulator.
# Needs a JDK in JAVA_HOME, as MISE_ENV=android's mise gives one.
class JNIBridgeTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  BRIDGE = File.join(ROOT, "runtime/mobile/vendor_ruby/fledge/jni.rb")
  PROXY = File.join(ROOT, "runtime/mobile/android/src/main/java/org/setdef/fledge/RubyProxy.java")

  # A class whose static field only its static initializer sets, so that
  # the field reads zero until the class is initialized, as every static
  # field of an Android class does until ART initializes it.
  CONSTANTS = <<~JAVA
    public class FledgeBridgeTestConstants {
        public static int COUNT = 7;
    }
  JAVA

  PROGRAM = <<~'RUBY'
    require "fiddle"
    require "json"
    bridge, library, classes = ARGV
    jvm = Fiddle.dlopen(library)
    create = Fiddle::Function.new(jvm["JNI_CreateJavaVM"], [Fiddle::TYPE_VOIDP] * 3, Fiddle::TYPE_INT)
    options = ["-Djava.class.path=#{classes}", "-Xrs"].map { |option| Fiddle::Pointer[option] }
    table = options.map { |option| [option.to_i, 0].pack("Q<2") }.join
    arguments = [0x00010008, options.size, Fiddle::Pointer[table].to_i, 0].pack("l<l<Q<C").ljust(24, "\0")
    vm = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    env = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    abort "JNI_CreateJavaVM failed" unless create.call(vm, env, arguments).zero?
    require bridge
    JNI = Fledge::JNI
    JNI.java_vm = vm[0, 8].unpack1("Q<")
    report = {}
    list = JNI.import("java.util.ArrayList").new
    list.add("one")
    list.add("twö 😀")
    report["list"] = [list.size, list.get(1), list.toString]
    builder = JNI.import("java.lang.StringBuilder").new("a")
    builder.append(1)
    builder.append("b")
    builder.append(2.5)
    builder.append(true)
    report["overloads"] = builder.toString
    report["field"] = JNI.import("java.lang.Integer").MAX_VALUE
    report["static"] = JNI.import("java.lang.Math").max(3, 7)
    report["initialized"] = JNI.import("FledgeBridgeTestConstants").COUNT
    org = JNI.import("org.setdef.fledge.RubyProxy")
    begin
      JNI.import("java.lang.Integer").parseInt("x")
    rescue JNI::JavaError => e
      report["thrown"] = e.message
    end
    ran = []
    runnable = JNI.implement("java.lang.Runnable", run: -> { ran << Thread.current.name.to_s })
    JNI.import("java.lang.Thread").new(runnable).run
    report["ran"] = ran.size
    comparator = JNI.implement("java.util.Comparator", Class.new { def compare(one, other) = one.to_s <=> other.to_s }.new)
    sorted = JNI.import("java.util.ArrayList").new
    %w[c a b].each { |item| sorted.add(item) }
    JNI.import("java.util.Collections").sort(sorted, comparator)
    report["sorted"] = sorted.toString
    report["object"] = [comparator.equals(comparator), comparator.hashCode.is_a?(Integer)]
    failing = JNI.implement("java.util.concurrent.Callable", call: -> { raise ArgumentError, "boom" })
    report["failed"] = failing.call.nil?
    ran_before = ran.size
    org.rubyEnded
    JNI.import("java.lang.Thread").new(runnable).run
    report["after_end"] = [ran.size - ran_before, comparator.compare("a", "b"), comparator.equals(comparator)]
    puts JSON.generate(report)
  RUBY

  def setup
    home = ENV.fetch("JAVA_HOME", nil)
    skip "no JDK in JAVA_HOME" unless home && File.executable?(File.join(home, "bin", "javac"))
    @library = %w[lib/server/libjvm.dylib lib/server/libjvm.so].map { |path| File.join(home, path) }.find { |path| File.file?(path) }
    skip "this JDK has no libjvm this test can open" unless @library
    @home = home
  end

  def test_ruby_reaches_java_and_java_reaches_ruby
    Dir.mktmpdir do |work|
      constants = File.join(work, "FledgeBridgeTestConstants.java")
      File.write(constants, CONSTANTS)
      _, err, status = Open3.capture3(File.join(@home, "bin", "javac"), "-d", work, PROXY, constants)
      assert status.success?, err
      program = File.join(work, "program.rb")
      File.write(program, PROGRAM)
      # A Ruby with no Bundler of the tests', which hides fiddle unless
      # the bundle installed it.
      out, err, status = Bundler.with_unbundled_env { Open3.capture3(RbConfig.ruby, program, BRIDGE, @library, work) }
      assert status.success?, err
      report = JSON.parse(out.lines.last)

      assert_equal [2, "twö 😀", "[one, twö 😀]"], report.fetch("list"), "Ruby's strings cross as Java's, past Unicode's first plane"
      assert_equal "a1b2.5true", report.fetch("overloads"), "each append takes the overload its argument fits"
      assert_equal 2_147_483_647, report.fetch("field")
      assert_equal 7, report.fetch("static")
      assert_equal 7, report.fetch("initialized"), "a static field is read after its class is initialized"
      assert_equal 'java.lang.NumberFormatException: For input string: "x"', report.fetch("thrown")
      assert_equal 1, report.fetch("ran"), "Java called a Runnable written in Ruby"
      assert_equal "[a, b, c]", report.fetch("sorted"), "Java sorted with a Comparator written in Ruby"
      assert_equal [true, true], report.fetch("object"), "Object's own methods are the proxy's"
      assert_equal [0, 0, true], report.fetch("after_end"), "once Ruby has ended, Java's calls into it return zero and run nothing"
      assert report.fetch("failed"), "an exception in Ruby returns null to Java"
      assert_match(/boom \(ArgumentError\)/, err, "and is printed as Ruby prints one")
    end
  end
end
