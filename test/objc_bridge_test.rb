# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# The iOS runtime's bridge to the Objective-C runtime
# (runtime/mobile/vendor_ruby/fledge/objc.rb;
# doc/contributors/design/phone-widgets.md), loaded into this process on
# a Mac, whose libobjc and Foundation are the same runtime and classes
# iOS has: messages with keywords for a selector's parts, strings and
# arrays across, a class written in Ruby that Objective-C sends messages
# to, and the reference each Ruby object holds. UIKit itself is iOS's
# alone; the mobile parity check runs an app that draws with it.
class ObjCBridgeTest < Minitest::Test
  BRIDGE = File.expand_path("../runtime/mobile/vendor_ruby/fledge/objc.rb", __dir__)

  def setup
    skip "the Objective-C runtime is Apple's" unless RUBY_PLATFORM.include?("darwin")
    require "fiddle"
    Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
    require BRIDGE
    require_relative "support/objc_greeter"
  end

  def objc
    Fledge::ObjC
  end

  def test_a_string_crosses_both_ways_as_utf_8
    string = objc.string("Grüße, 🌍")
    assert_equal "Grüße, 🌍", string.to_s
    assert_equal Encoding::UTF_8, string.to_s.encoding
    assert_equal 9, string.length, "NSString counts UTF-16 units, the emoji two"
  end

  def test_keywords_spell_the_rest_of_a_selector
    list = objc::NSMutableArray.new
    list.addObject("one")
    list.insertObject("zero", atIndex: 0)
    assert_equal 2, list.count
    assert_equal %w[zero one], (0...(list.count)).map { |at| list.objectAtIndex(at).to_s }
  end

  def test_a_setter_sends_set_and_the_name
    dictionary = objc::NSMutableDictionary.new
    dictionary.setValue("v", forKey: "k")
    assert_equal "v", dictionary.valueForKey("k").to_s
    holder = objc::NSMutableString.new
    holder.string = "set"
    assert_equal "set", holder.to_s
  end

  def test_an_array_becomes_an_nsarray
    array = objc.array(["a", objc.string("b")])
    assert_equal 2, array.count
    assert_equal "b", array.lastObject.to_s
  end

  def test_classes_are_constants_with_objective_c_superclasses
    assert_equal objc::NSArray, objc::NSMutableArray.superclass
    assert_equal "NSMutableArray", objc::NSMutableArray.objc_name
    assert_kind_of objc::NSString, objc.string("x")
    assert_same objc::NSString, objc.wrap(objc::NSString.objc_pointer)
  end

  def test_objective_c_calls_a_method_written_in_ruby
    greeter = FledgeBridgeTestGreeter.new
    assert_equal "Hello, world", greeter.objc_send("performSelector:withObject:", :"greet:", "world").to_s
    assert_equal 5, greeter.objc_send("add:to:", 2, 3)
    assert greeter.respondsToSelector(:"add:to:")
  end

  def test_the_object_objective_c_names_is_the_ruby_object_itself
    greeter = FledgeBridgeTestGreeter.new
    greeter.objc_send("performSelector:withObject:", :"hear:", "you")
    assert_equal "you", greeter.heard
    assert_same greeter, objc.wrap(greeter.objc_pointer)
  end

  def test_a_block_method_takes_its_selector_and_its_protocols_encoding
    evictions = FledgeBridgeTestEvictions.new
    assert_equal "v32@0:8@16@24", objc.protocol_encoding(["NSCacheDelegate"], "cache:willEvictObject:")
    assert_nil evictions.objc_send("cache:willEvictObject:", nil, "gone")
    assert_equal "gone", evictions.evicted
    assert_equal "evictions", evictions.objc_send("description").to_s, "an override takes its superclass's encoding"
  end

  def test_a_protocol_the_runtime_lacks_gives_its_recorded_encodings
    rows = FledgeBridgeTestRows.new
    assert_equal "q32@0:8@16q24", objc.protocol_encoding(["UITableViewDataSource"], "tableView:numberOfRowsInSection:")
    assert_equal "q32@0:8@16q24", objc.encoding_of(rows.objc_pointer, objc.selector("tableView:numberOfRowsInSection:"))
    assert rows.respondsToSelector(:"tableView:numberOfRowsInSection:")
    assert_equal 42, rows.objc_send("tableView:numberOfRowsInSection:", nil, 2)
  end

  def test_a_protocol_nothing_knows_is_refused_by_name
    error = assert_raises(Fledge::ObjC::Error) { Class.new(objc::NSObject) { def self.name = "FledgeBridgeTestNoProtocol" }.objc_protocols("FledgeNoSuchProtocol") }
    assert_match(/no protocol FledgeNoSuchProtocol/, error.message)
  end

  def test_a_framework_is_loaded_by_name_and_a_missing_one_is_not
    assert objc.load_framework("CoreFoundation")
    refute objc.load_framework("FledgeNoSuchFramework")
  end

  def test_an_exception_in_a_method_objective_c_called_is_printed_not_raised
    greeter = FledgeBridgeTestGreeter.new
    _, err = capture_subprocess_io { assert_equal 0, greeter.objc_send("boom") }
    assert_match(/boom \(ArgumentError\)/, err)
  end

  def test_a_selector_the_object_does_not_answer_raises
    error = assert_raises(NoMethodError) { objc.string("x").noSuchSelector }
    assert_match(/does not answer noSuchSelector/, error.message)
  end

  def test_a_struct_argument_is_refused_by_name
    error = assert_raises(Fledge::ObjC::Error) { objc::NSValue.valueWithRange([0, 1]) }
    assert_match(/cannot pass .*_NSRange/, error.message)
  end

  def test_type_encodings_lose_qualifiers_and_offsets
    assert_equal %w[v @ : @], objc.parse("v24@0:8@16")
    assert_equal ["@", "@", ":", "r^{CGPoint=dd}"].map { |code| code.delete("r") }, objc.parse("@32@0:8r^{CGPoint=dd}16")
    assert_equal ["v", "@", ":", '@"NSString"', "@?"], objc.parse('v@:@"NSString"@?')
  end

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
