# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "rbconfig"

# The C extensions of examples/native_phone and examples/cmake_phone,
# which app developers copy, compiled for the Ruby running these tests
# with their own extconf.rb, as gem install would, and called from a Ruby
# of their own. Each totals any Array it is given, so neither its size
# nor its numbers may break the process: a buffer as large as the Array
# on the C stack overran the stack, and a sum past what a long long holds
# is undefined behaviour in C and C++.
class ExampleExtensionsTest < Minitest::Test
  ADDER = File.expand_path("../examples/native_phone/gems/adder/ext/adder", __dir__)
  TALLY = File.expand_path("../examples/cmake_phone/gems/tally/ext/tally", __dir__)

  # Many more numbers than a thread's stack holds as long longs: 8 MiB
  # holds a million.
  MANY = 4_000_000

  def setup
    skip "the examples' extensions are compiled with the C toolchain mkmf finds, which Windows' CI lacks" if Gem.win_platform?
  end

  def test_adder_totals_more_numbers_than_the_stack_holds
    assert_equal ["#{MANY}\n", ""], call(ADDER, "Adder", "puts Adder.total(Array.new(#{MANY}, 1))")
  end

  def test_adder_refuses_a_sum_a_long_long_cannot_hold
    script = "[-> { Adder.add(2**62, 2**62) }, -> { Adder.total([2**62, 2**62]) }, -> { Adder.total([-2**63, -1]) }]" \
      ".each { |sum| sum.call rescue puts $!.class }\nputs Adder.add(-2**62, -2**62), Adder.total([2**62, -2**62])"

    assert_equal ["RangeError\nRangeError\nRangeError\n#{-2 ** 63}\n0\n", ""], call(ADDER, "Adder", script)
  end

  def test_tally_totals_more_numbers_than_the_stack_holds
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?

    assert_equal ["#{MANY}\n", ""], call(TALLY, "Tally", "puts Tally.sum(Array.new(#{MANY}, 1))")
  end

  def test_tally_refuses_a_sum_a_long_long_cannot_hold
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?
    script = "[[2**62, 2**62], [-2**63, -1]].each { |numbers| Tally.sum(numbers) rescue puts $!.class }\n" \
      "puts Tally.sum([2**62, -2**62])"

    assert_equal ["RangeError\nRangeError\n0\n", ""], call(TALLY, "Tally", script)
  end

  # The extension in +source+, compiled once, and +script+'s standard
  # output and standard error from a Ruby that has required it.
  def call(source, name, script)
    library = self.class.compiled[source] ||= compile(source, name.downcase)
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", "require #{library.dump}\n#{script}")
    assert_predicate status, :success?, "#{name}: #{err}"
    [out, err]
  end

  class << self
    def compiled = (@compiled ||= {})
  end

  # Runs +source+'s extconf.rb and make in a folder of their own, and
  # returns the path of the library they make.
  def compile(source, feature)
    dir = Dir.mktmpdir
    Minitest.after_run { FileUtils.rm_rf(dir) }
    [[RbConfig.ruby, File.join(source, "extconf.rb")], ["make"]].each do |command|
      out, status = Open3.capture2e(*command, chdir: dir)
      assert_predicate status, :success?, out
    end
    File.join(dir, "#{feature}.#{RbConfig::CONFIG.fetch('DLEXT')}")
  end

  def cmake?
    system("cmake", "--version", out: File::NULL, err: File::NULL) || false
  end
end
