# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def load(yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "fledge.yml"), yaml) if yaml
      Fledge::Config.load(dir)
    end
  end

  def test_no_file_is_no_configuration
    assert_equal Fledge::Config.none, load(nil)
    assert_equal Fledge::Config.none, load("")
    assert_equal Fledge::Config.none, load("# only a comment\n")
  end

  def test_reads_a_name_and_license_corrections
    config = load("name: CoolApp\nlicenses:\n  unlabeled: MIT\n  other: Apache-2.0 OR MIT\n")

    assert_equal "CoolApp", config.name
    assert_equal({ "unlabeled" => "MIT", "other" => "Apache-2.0 OR MIT" }, config.licenses)
  end

  def test_refuses_what_it_cannot_use
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name and licenses\z/,
      "nmae: x\n" => /has 'nmae', which Fledge does not know\. It knows name and licenses\.\z/,
      "name: 3\n" => /: name must be text, such as name: MyCoolApp\z/,
      "licenses: MIT\n" => /: licenses must map gem names to SPDX license expressions/,
      "licenses:\n  gem: ''\n" => /: licenses must map gem names to SPDX license expressions/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end
end
