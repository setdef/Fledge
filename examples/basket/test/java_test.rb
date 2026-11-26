# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's calls into Java by name (lib/basket/android/java.rb), tested
# with Minitest as any Ruby is. Reading what Java lists for a class and
# choosing an overload by the arguments need no Java, so ruby
# test/java_test.rb runs those on your computer; the calls
# themselves need Android's Java, so the last tests run only inside the
# app, where test/phone.rb runs them with the others:
#
#   fledge test android test/phone.rb

require "minitest/autorun"
require_relative "../lib/basket/android/java"

# The tests of Basket::Android::Java::Member, which need no Java.
class MemberTest < Minitest::Test
  # What Arrays.toString gives for a class's getMethods.
  LISTING = "[public static void android.os.Looper.loop(), " \
    "public boolean java.util.ArrayList.add(java.lang.Object), " \
    "public void java.util.ArrayList.add(int,java.lang.Object), " \
    "public final native void java.lang.Object.wait(long,int) throws java.lang.InterruptedException, " \
    "public java.lang.Object[] java.util.ArrayList.toArray(java.lang.Object[])]"

  # The member under test.
  def member
    Basket::Android::Java::Member
  end

  # A Java object that is an instance of the types it lists.
  FakeObject = Struct.new(:types) do
    # Whether the object is an instance of +type+.
    def instance_of_type?(type)
      types.include?(type)
    end
  end

  # Each method of the listing has its name, parameters, result, and
  # whether it is static.
  def test_a_listing_of_methods_gives_each_overload
    methods = member.methods_in(LISTING)

    assert_equal %w[loop add add wait toArray], methods.map(&:name)
    assert_equal [["int", "java.lang.Object"], ["long", "int"], ["java.lang.Object[]"]], methods.values_at(2, 3, 4).map(&:parameters)
    assert_equal %w[void boolean void void java.lang.Object[]], methods.map(&:returns)
    assert_equal [true, false, false, false, false], methods.map(&:static)
  end

  # A constructor has the name JNI gives constructors, and no result.
  def test_a_listing_of_constructors_gives_each_overload
    constructors = member.constructors_in("[public android.widget.EditText(android.content.Context), public a.B$C(int,int,float)]")

    assert_equal [["android.content.Context"], ["int", "int", "float"]], constructors.map(&:parameters)
    assert_equal ["<init>"], constructors.map(&:name).uniq
  end

  # A method's JNI signature spells each type as JNI does.
  def test_a_signature_spells_each_type_as_jni_does
    add = member.methods_in(LISTING)[2]

    assert_equal "(ILjava/lang/Object;)V", add.signature
    assert_equal "([Ljava/lang/Object;)[Ljava/lang/Object;", member.methods_in(LISTING).last.signature
    assert_equal "[B", member.descriptor("byte[]")
  end

  # The overload whose parameters take the arguments is the one chosen,
  # by their count first.
  def test_the_overload_that_takes_the_arguments_is_chosen
    adds = member.methods_in(LISTING).select { |each| each.name == "add" }

    assert_equal ["java.lang.Object"], member.choose(adds, ["milk"]).parameters
    assert_equal ["int", "java.lang.Object"], member.choose(adds, [0, "milk"]).parameters
  end

  # A Ruby value fits the narrowest type that takes it.
  def test_a_value_fits_the_narrowest_type_that_takes_it
    assert_equal 0, member.cost("int", 1)
    assert_equal 1, member.cost("long", 1)
    assert_nil member.cost("boolean", 1)
    assert_equal 0, member.cost("boolean", true)
    assert_equal 0, member.cost("float", 1.0)
    assert_equal 1, member.cost("java.lang.CharSequence", "milk")
    assert_nil member.cost("int", nil)
    assert_equal 1, member.cost("java.lang.Object", nil)
    assert_equal 0, member.cost("android.view.View", FakeObject.new(["android.view.View"]))
    assert_nil member.cost("android.view.View", FakeObject.new([]))
  end

  # A call no overload takes is an Error that says so.
  def test_arguments_no_overload_takes_are_an_error
    adds = member.methods_in(LISTING).select { |each| each.name == "add" }
    error = assert_raises(Basket::Android::Java::Error) { member.choose(adds, [1.5]) }

    assert_match(/no add of Java takes \(Float\)/, error.message)
  end
end

if RUBY_PLATFORM.include?("android")
  # The tests of Basket::Android::Java, which call Android's Java.
  class JavaTest < Minitest::Test
    # The Java classes the tests use.
    ARRAY_LIST = Basket::Android::Java::Klass["java.util.ArrayList"]

    # A constructor, an overloaded method, and a method whose name an
    # overload shares with another's, are called by name.
    def test_a_list_is_made_added_to_and_removed_from_by_name
      list = ARRAY_LIST.new
      list.add("milk")
      list.add(0, "eggs")

      assert_equal 2, list.size
      assert_equal "eggs", list.remove(0).to_s
      assert_equal true, list.remove("milk")
      assert list.isEmpty
    end

    # A static field is read as a constant, and a static method is
    # called by name.
    def test_a_constant_and_a_static_method_are_read_by_name
      integer = Basket::Android::Java::Klass["java.lang.Integer"]

      assert_equal 2_147_483_647, integer.MAX_VALUE
      assert_equal 42, integer.valueOf(42).intValue
      assert_equal "42", integer.toString(42)
    end

    # A method no class has is a NoMethodError, and a call no overload
    # takes is an Error.
    def test_a_method_that_does_not_exist_raises
      list = ARRAY_LIST.new

      assert_raises(NoMethodError) { list.noSuchMethod }
      assert_raises(Basket::Android::Java::Error) { list.add(1.5, 2.5, 3.5) }
    end
  end
end
