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

  def test_reads_an_apps_identity
    config = load(<<~YAML)
      name: Hello Window
      kind: windowed
      identifier: com.example.Hello-Window
      version: "1.10"
      icon: art/icon.png
      publisher: Example, Inc.
      copyright: © 2026 Example, Inc.
    YAML
    assert_equal Fledge::Config.new(name: "Hello Window", kind: "windowed", identifier: "com.example.Hello-Window", version: "1.10",
      icon: "art/icon.png", publisher: "Example, Inc.", copyright: "© 2026 Example, Inc."), config
    assert_equal "console", load("kind: console\n").kind
    assert_equal "0.1.0.pre.2", load("version: 0.1.0.pre.2\n").version
  end

  # Fledge takes no position on an app's gems' licenses (2026-10-28; ADR
  # 007), so the keys that corrected a gem's license or said what its
  # compiled code holds are gone, and fail like any other unknown key.
  def test_refuses_what_it_cannot_use
    known = "It knows name, kind, identifier, version, icon, publisher, and copyright."
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name, kind, identifier, version, icon, publisher, and copyright\z/,
      "nmae: x\n" => /has 'nmae', which Fledge does not know\. #{known}\z/,
      "licenses:\n  gem: MIT\n" => /has 'licenses', which Fledge does not know\. #{known}\z/,
      "compiled:\n  gem: []\n" => /has 'compiled', which Fledge does not know\. #{known}\z/,
      "name: 3\n" => /: name must be text, such as name: MyCoolApp\z/,
      "name: \"  \"\n" => /: name must be text, such as name: MyCoolApp\z/,
      "kind: gui\n" => /: kind must be console or windowed, not gui\z/,
      "kind: [windowed]\n" => /: kind must be text, such as kind: windowed\z/,
      "identifier: MyCoolApp\n" => /: identifier must be reverse-DNS, such as com\.example\.MyCoolApp: .* not MyCoolApp\z/,
      "identifier: com.example.my_app\n" => /: identifier must be reverse-DNS.* not com\.example\.my_app\z/,
      "identifier: com.#{'a' * 130}\n" => /: identifier must be reverse-DNS.*in at most 128 characters/,
      "version: 1.2\n" => /: version must be text; quote it, as in version: "1\.2"\z/,
      "version: v1\n" => /: version must be a version that begins with a number, such as 1\.2\.3, not v1\z/,
      "icon: 3\n" => /: icon must be text, such as icon: icon\.png\z/,
      "publisher: [a]\n" => /: publisher must be text/,
      "copyright: true\n" => /: copyright must be text/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end
end
