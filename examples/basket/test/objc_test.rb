# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's bridge to the Objective-C runtime (lib/basket/objc.rb), tested
# with Foundation, whose classes a Mac and an iPhone have alike: messages
# with keywords for a selector's parts, strings and arrays across, a class
# written in Ruby that Objective-C sends messages to, and the reference
# each Ruby object holds. UIKit is for the screen's tests
# (test/screen_test.rb). On a Mac, this runs as any Ruby test does:
#
#   ruby test/objc_test.rb
#
# and on a phone, test/phone.rb runs it.

require "minitest/autorun"

if RUBY_PLATFORM.include?("darwin")
  require "fiddle"
  Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
  require_relative "../lib/basket/objc"

  # A class written in Ruby that Objective-C finds by its name: the
  # Objective-C runtime has no way to take a class back, so a process
  # defines it once.
  class BasketBridgeTestGreeter < Basket::ObjC::NSObject
    # What <tt>hear:</tt> was told.
    attr_reader :heard

    objc_method("greet:", "@@:@") { |name| "Hello, #{name}" }
    objc_method("add:to:", "q@:qq") { |number, to| number + to }
    objc_method("boom", "q@:") { raise ArgumentError, "boom" }
    objc_method("hear:", "v@:@") { |sender| @heard = sender.to_s }
    objc_method("description", "@@:") { "greeter" }
  end

  # A data source of UIKit's, whose protocol a process of Ruby alone has
  # no way to ask the Objective-C runtime for, so Basket::ObjC records its
  # encodings.
  class BasketBridgeTestRows < Basket::ObjC::NSObject
    objc_protocols "UITableViewDataSource"

    objc_method("tableView:numberOfRowsInSection:") { |_table, section| 40 + section }
  end
end

# The tests of Basket::ObjC.
class ObjCTest < Minitest::Test
  # Skips off a Mac, whose Objective-C runtime this needs.
  def setup
    skip "the Objective-C runtime is Apple's" unless RUBY_PLATFORM.include?("darwin")
  end

  # The bridge under test.
  def objc
    Basket::ObjC
  end

  # A String is an NSString and back, as UTF-8.
  def test_a_string_crosses_both_ways_as_utf_8
    string = objc.string("Grüße, 🌍")

    assert_equal "Grüße, 🌍", string.to_s
    assert_equal Encoding::UTF_8, string.to_s.encoding
    assert_equal 9, string.length, "NSString counts UTF-16 units, the emoji two"
  end

  # A keyword argument is the next part of the selector.
  def test_keywords_spell_the_rest_of_a_selector
    list = objc::NSMutableArray.new
    list.addObject("one")
    list.insertObject("zero", atIndex: 0)

    assert_equal 2, list.count
    assert_equal %w[zero one], (0...(list.count)).map { |at| list.objectAtIndex(at).to_s }
  end

  # <tt>name=</tt> sends <tt>setName:</tt>.
  def test_a_setter_sends_set_and_the_name
    dictionary = objc::NSMutableDictionary.new
    dictionary.setValue("v", forKey: "k")

    assert_equal "v", dictionary.valueForKey("k").to_s
    holder = objc::NSMutableString.new
    holder.string = "set"

    assert_equal "set", holder.to_s
  end

  # An Array is an NSArray.
  def test_an_array_becomes_an_nsarray
    array = objc.array(["a", objc.string("b")])

    assert_equal 2, array.count
    assert_equal "b", array.lastObject.to_s
  end

  # A class is a constant, in Objective-C's hierarchy.
  def test_classes_are_constants_with_objective_c_superclasses
    assert_equal objc::NSArray, objc::NSMutableArray.superclass
    assert_equal "NSMutableArray", objc::NSMutableArray.objc_name
    assert_kind_of objc::NSString, objc.string("x")
    assert_same objc::NSString, objc.wrap(objc::NSString.objc_pointer)
  end

  # Objective-C sends a message to a method Ruby defined.
  def test_objective_c_calls_a_method_written_in_ruby
    greeter = BasketBridgeTestGreeter.new

    assert_equal "Hello, world", greeter.objc_send("performSelector:withObject:", :"greet:", "world").to_s
    assert_equal 5, greeter.objc_send("add:to:", 2, 3)
    assert greeter.respondsToSelector(:"add:to:")
  end

  # The object Objective-C passes back is the Ruby object, with its state.
  def test_the_object_objective_c_names_is_the_ruby_object_itself
    greeter = BasketBridgeTestGreeter.new
    greeter.objc_send("performSelector:withObject:", :"hear:", "you")

    assert_equal "you", greeter.heard
    assert_same greeter, objc.wrap(greeter.objc_pointer)
  end

  # A Ruby method replaces its Objective-C superclass's.
  def test_a_method_overrides_its_superclasss
    assert_equal "greeter", BasketBridgeTestGreeter.new.objc_send("description").to_s
  end

  # A class that adopts a protocol UIKit's headers say is the one the
  # bridge records takes its methods' encodings from the record.
  def test_a_protocol_the_runtime_lacks_gives_its_recorded_encodings
    rows = BasketBridgeTestRows.new

    assert_equal "q32@0:8@16q24", objc.protocol_encoding(["UITableViewDataSource"], "tableView:numberOfRowsInSection:")
    assert_equal "q32@0:8@16q24", objc.encoding_of(rows.objc_pointer, objc.selector("tableView:numberOfRowsInSection:"))
    assert rows.respondsToSelector(:"tableView:numberOfRowsInSection:")
    assert_equal 42, rows.objc_send("tableView:numberOfRowsInSection:", nil, 2)
  end

  # A protocol with no recorded encodings is refused by its name.
  def test_a_protocol_nothing_knows_is_refused_by_name
    error = assert_raises(Basket::ObjC::Error) do
      Class.new(objc::NSObject) do
        def self.name
          "BasketBridgeTestNoProtocol"
        end
      end.objc_protocols("BasketNoSuchProtocol")
    end

    assert_match(/no encodings for the protocol BasketNoSuchProtocol/, error.message)
  end

  # Loading a framework says whether the system has it.
  def test_a_framework_is_loaded_by_name_and_a_missing_one_is_not
    assert objc.load_framework("CoreFoundation")
    refute objc.load_framework("BasketNoSuchFramework")
  end

  # An exception in a method Objective-C called is printed, not raised
  # through Objective-C's frames.
  def test_an_exception_in_a_method_objective_c_called_is_printed_not_raised
    greeter = BasketBridgeTestGreeter.new
    _, err = capture_subprocess_io { assert_equal 0, greeter.objc_send("boom") }

    assert_match(/boom \(ArgumentError\)/, err)
  end

  # A message the receiver does not answer is a NoMethodError.
  def test_a_selector_the_object_does_not_answer_raises
    error = assert_raises(NoMethodError) { objc.string("x").noSuchSelector }

    assert_match(/does not answer noSuchSelector/, error.message)
  end

  # A struct argument is refused by its type's name.
  def test_a_struct_argument_is_refused_by_name
    error = assert_raises(Basket::ObjC::Error) { objc::NSValue.valueWithRange([0, 1]) }

    assert_match(/cannot pass .*_NSRange/, error.message)
  end

  # An encoding's type codes come without qualifiers and offsets.
  def test_type_encodings_lose_qualifiers_and_offsets
    assert_equal %w[v @ : @], objc.parse("v24@0:8@16")
    assert_equal ["@", "@", ":", "^{CGPoint=dd}"], objc.parse("@32@0:8r^{CGPoint=dd}16")
    assert_equal ["v", "@", ":", '@"NSString"', "@?"], objc.parse('v@:@"NSString"@?')
  end

  # Only the owning families of methods return an object the caller owns.
  def test_only_the_owning_families_return_an_owned_object
    assert objc.owning?("alloc")
    assert objc.owning?("initWithBytes:length:encoding:")
    assert objc.owning?("newObject")
    assert objc.owning?("mutableCopy")
    refute objc.owning?("news")
    refute objc.owning?("initialized")
    refute objc.owning?("stringWithUTF8String:")
  end

  # An object a message gives Ruby holds one reference, which Ruby gives
  # back, on the main queue, once it collects the object; an owned
  # result's reference is the one the caller already holds.
  def test_each_ruby_object_holds_one_reference
    string = objc::NSMutableString.alloc.initWithString("counted")

    assert_equal 1, string.retainCount
    again = objc.wrap(string.objc_pointer)

    assert_equal 2, string.retainCount
    assert_equal string, again
  end
end
