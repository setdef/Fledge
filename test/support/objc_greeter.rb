# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# A class written in Ruby that Objective-C knows by its name, for
# test/objc_bridge_test.rb, which requires it once Fledge::ObjC is
# loaded: the Objective-C runtime has no way to take a class back, so a
# process defines it once.
class FledgeBridgeTestGreeter < Fledge::ObjC::NSObject
  attr_reader :heard

  objc_method def greet(name) = "Hello, #{name}", "@@:@"
  objc_method def add(number, to:) = number + to, "q@:qq"
  objc_method def boom = raise(ArgumentError, "boom"), "q@:"

  objc_method def hear(sender)
    @heard = sender.to_s
  end
end

# A delegate of Foundation's NSCache whose method is a block named by its
# selector, with the encoding the protocol gives it.
class FledgeBridgeTestEvictions < Fledge::ObjC::NSObject
  objc_protocols "NSCacheDelegate"
  attr_reader :evicted

  objc_method("cache:willEvictObject:") { |_cache, object| @evicted = object.to_s }
  objc_method("description") { "evictions" }
end
