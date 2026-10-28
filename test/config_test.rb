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

  def test_reads_a_name
    assert_equal "CoolApp", load("name: CoolApp\n").name
  end

  # Fledge takes no position on an app's gems' licenses (2026-10-28; ADR
  # 007), so the keys that corrected a gem's license or said what its
  # compiled code holds are gone, and fail like any other unknown key.
  def test_refuses_what_it_cannot_use
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name\z/,
      "nmae: x\n" => /has 'nmae', which Fledge does not know\. It knows only name\.\z/,
      "licenses:\n  gem: MIT\n" => /has 'licenses', which Fledge does not know\. It knows only name\.\z/,
      "compiled:\n  gem: []\n" => /has 'compiled', which Fledge does not know\. It knows only name\.\z/,
      "name: 3\n" => /: name must be text, such as name: MyCoolApp\z/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end
end
