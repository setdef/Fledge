# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Which names each extension linked into a phone's app keeps to itself: the
# arithmetic over the names each part defines, which needs no tool.
# test/integration/mobile_linked_symbols_test.rb builds real extensions with the
# phones' tools and runs what they link.
class MobileExtensionsSeparationTest < Minitest::Test
  Owner = Fledge::MobileExtensions::Separation::Owner

  def test_an_extension_that_shares_no_name_keeps_every_name_global
    a = Owner.new(what: "a", names: %w[Init_fledge_0 a_only], keep: %w[Init_fledge_0])
    b = Owner.new(what: "b", names: %w[Init_fledge_1 b_only], keep: %w[Init_fledge_1])

    assert_equal [[], []], local_names([a, b])
  end

  def test_two_extensions_that_define_one_name_each_keep_it_to_themselves
    a = Owner.new(what: "a", names: %w[Init_fledge_0 clash_file clash_lib a_only], keep: %w[Init_fledge_0])
    b = Owner.new(what: "b", names: %w[Init_fledge_1 clash_lib clash_file], keep: %w[Init_fledge_1])

    assert_equal [%w[clash_file clash_lib], %w[clash_file clash_lib]], local_names([a, b])
  end

  def test_an_extension_that_defines_a_name_of_the_runtime_keeps_its_own
    yamlish = Owner.new(what: "yamlish", names: %w[Init_fledge_0 yaml_get_version], keep: %w[Init_fledge_0])
    runtime = Owner.new(what: "the runtime", names: %w[yaml_get_version rb_define_module], keep: [])

    assert_equal [%w[yaml_get_version]], local_names([yamlish], [runtime])
  end

  def test_a_name_a_shared_library_defines_is_kept_by_the_extension_that_defines_it_too
    a = Owner.new(what: "a", names: %w[Init_fledge_0 shared_thing], keep: %w[Init_fledge_0])
    b = Owner.new(what: "b", names: %w[Init_fledge_1], keep: %w[Init_fledge_1])
    shared = Owner.new(what: "libshared.a", names: %w[shared_thing], keep: [])

    assert_equal [%w[shared_thing], []], local_names([a, b], [shared])
  end

  def test_an_extension_keeps_its_init_function_global_while_another_hides_it
    a = Owner.new(what: "a", names: %w[Init_fledge_0], keep: %w[Init_fledge_0])
    b = Owner.new(what: "b", names: %w[Init_fledge_1 Init_fledge_0], keep: %w[Init_fledge_1])

    assert_equal [[], %w[Init_fledge_0]], local_names([a, b])
  end

  def test_a_name_two_parts_that_stay_whole_define_is_refused_naming_both
    a = Owner.new(what: "a", names: %w[Init_fledge_0], keep: %w[Init_fledge_0])
    shared = Owner.new(what: "the static library libssl.a, which the gems a and b link", names: %w[SSL_new], keep: [])
    runtime = Owner.new(what: "the runtime's libfledgeruby.a", names: %w[SSL_new], keep: [])

    error = assert_raises(Fledge::Error) { local_names([a], [shared, runtime]) }
    assert_includes error.message, "SSL_new"
    assert_includes error.message, "the static library libssl.a, which the gems a and b link"
    assert_includes error.message, "the runtime's libfledgeruby.a"
  end

  def test_two_extensions_that_must_keep_one_init_function_global_are_refused
    a = Owner.new(what: "the gem a's extension a/a", names: %w[Init_x], keep: %w[Init_x])
    b = Owner.new(what: "the gem b's extension b/b", names: %w[Init_x], keep: %w[Init_x])

    error = assert_raises(Fledge::Error) { local_names([a, b]) }
    assert_match(%r{\AInit_x is defined by the gem a's extension a/a, and by the gem b's extension b/b, and one app cannot link it twice}, error.message)
  end

  def test_a_name_an_object_defines_twice_is_no_clash
    a = Owner.new(what: "a", names: %w[Init_fledge_0 twice twice], keep: %w[Init_fledge_0])

    assert_equal [[]], local_names([a])
  end

  private def local_names(objects, fixed = [])
    Fledge::MobileExtensions::Separation.local_names(objects, fixed)
  end
end
