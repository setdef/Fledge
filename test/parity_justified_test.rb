# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "yaml"
require_relative "test_helper"
require_relative "../tasks/parity"

# ADR 029, section 2: Parity::JUSTIFIED and Parity::MOBILE_JUSTIFIED may
# only shrink in 1.x. An entry joins test/parity_justified.yml only by a
# deliberate change to that list, so that widening how a built app may
# differ from ruby main.rb cannot pass unnoticed. The words of a reason
# may change freely; what an entry allows may not.
class ParityJustifiedTest < Minitest::Test
  ALLOWED = YAML.safe_load_file(File.join(__dir__, "parity_justified.yml"))

  def self.described(justification)
    {
      "fact" => justification.fact,
      "reference" => justification.reference.map(&:source),
      "app" => justification.app.map(&:source),
      "platforms" => justification.platforms,
      "checks" => justification.checks.map(&:to_s),
    }
  end

  def self.added(entries)
    entries.map { |entry| described(entry) } - ALLOWED
  end

  { "JUSTIFIED" => Parity::JUSTIFIED, "MOBILE_JUSTIFIED" => Parity::MOBILE_JUSTIFIED }.each do |name, entries|
    define_method(:"test_#{name.downcase}_allows_nothing_the_list_does_not") do
      assert_empty self.class.added(entries), "Parity::#{name} allows a difference test/parity_justified.yml does not list. " \
        "ADR 029, section 2, forbids a new difference from ruby main.rb after 1.0: these lists may only shrink in 1.x, " \
        "so adding an entry waits for a major version, and then changes the list on purpose."
    end
  end

  def test_a_new_or_widened_entry_is_caught
    widened = Parity::Justification.new(fact: "$0", reference: [/./], reason: "Any reason.")

    assert_equal [self.class.described(widened)], self.class.added([*Parity::JUSTIFIED, widened])
  end

  def test_a_reworded_reason_is_not_a_new_entry
    entry = Parity::JUSTIFIED.first or flunk

    assert_empty self.class.added([entry.with(reason: "Other words.")])
  end
end
