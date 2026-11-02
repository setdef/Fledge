# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "json"
require "json_schemer"

# lib/fledge/config.schema.json is written by hand, and Fledge::Config
# is what fledge build obeys (ADR 023). These tests hold the two
# together: the schema's keys, kinds, installers, and identifier rule
# are compared with Config's constants, and each document below must be
# accepted by both or refused by both.
class ConfigSchemaTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PATH = File.join(ROOT, "lib", "fledge", "config.schema.json")
  URL = "https://raw.githubusercontent.com/setdef/Fledge/trunk/lib/fledge/config.schema.json"
  HEADER = "# yaml-language-server: $schema=#{URL}".freeze

  # Each document, and whether fledge build takes it. Both the schema and
  # Fledge::Config (with Fledge::Identity, which refuses a windowed app
  # with no identifier) must agree with the second column.
  DOCUMENTS = {
    "" => true,
    "name: Cool App\n" => true,
    "name: \"  \"\n" => false,
    "name: 3\n" => false,
    "name: [a]\n" => false,
    "nmae: Cool App\n" => false,
    "licenses: {}\n" => false,
    "- name\n" => false,
    "kind: console\n" => true,
    "kind: windowed\nidentifier: com.example.CoolApp\n" => true,
    "kind: windowed\n" => false,
    "kind: windowed\nidentifier:\n" => false,
    "kind: gui\n" => false,
    "kind: Windowed\n" => false,
    "identifier: com.example.Cool-App\n" => true,
    "identifier: com.example.CoolApp2\n" => true,
    "identifier: example\n" => false,
    "identifier: com..example\n" => false,
    "identifier: -com.example\n" => false,
    "identifier: com.example.Cool_App\n" => false,
    "identifier: \"com.example.CoolApp\\n\"\n" => false,
    "identifier: com.#{'a' * 124}\n" => true,
    "identifier: com.#{'a' * 125}\n" => false,
    "version: \"1.2.3\"\n" => true,
    "version: 0.1.0.pre.2\n" => true,
    "version: 1.2.3-beta.1\n" => true,
    "version: \"1.2.3 \"\n" => true,
    "version: 1.2\n" => false,
    "version: 1\n" => false,
    "version: v1.2.3\n" => false,
    "version: \" 1.2.3\"\n" => false,
    "version: 1..2\n" => false,
    "version: 1.2.\n" => false,
    "version: \"1.2.3\\n4\"\n" => false,
    "icon: icons/app\n" => true,
    "icon: icons/app.png\n" => false,
    "icon: icons/app.ICNS\n" => false,
    "icon: icons/app.ico\n" => false,
    "icon: icons/app.svg\n" => true,
    "publisher: Example, Inc.\n" => true,
    "publisher: \"\"\n" => false,
    "copyright: © 2026 Example, Inc.\n" => true,
    "copyright: true\n" => false,
    "kind: windowed\nidentifier: com.example.A\ninstallers: [dmg, nsis, appimage, deb]\n" => true,
    "kind: windowed\nidentifier: com.example.A\ninstallers: [dmg, dmg]\n" => true,
    "kind: windowed\nidentifier: com.example.A\ninstallers: []\n" => true,
    "kind: windowed\nidentifier: com.example.A\ninstallers:\n" => true,
    "kind: windowed\nidentifier: com.example.A\ninstallers: [msi]\n" => false,
    "kind: windowed\nidentifier: com.example.A\ninstallers: [DMG]\n" => false,
    "kind: windowed\nidentifier: com.example.A\ninstallers: dmg\n" => false,
    "kind: windowed\nidentifier: com.example.A\ninstallers: [1]\n" => false,
    "installers: []\n" => true,
    "installers: [dmg]\n" => false,
    "kind: console\ninstallers: [dmg]\n" => false,
  }.merge(
    # Every key may be empty, which Config reads as absent, and none may
    # be blank or a number.
    *Fledge::Config::KEYS.map { |key| { "#{key}:\n" => true, "#{key}: \" \\t\"\n" => false, "#{key}: 7\n" => false } }
  ).freeze

  def schema
    @schema ||= JSON.parse(File.read(PATH))
  end

  # Editors read a pattern as ECMA-262 does, where ^ and $ are the ends of
  # the text, not of a line, as they are in Ruby.
  def schemer
    @schemer ||= JSONSchemer.schema(schema, regexp_resolver: "ecma")
  end

  # The document as an editor's language server sees it: an empty file
  # holds nothing to check, as Config reads it as no keys.
  def schema_accepts?(yaml)
    schemer.valid?(YAML.safe_load(yaml) || {})
  end

  def fledge_accepts?(yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, Fledge::Config::FILE), yaml)
      config = Fledge::Config.load(dir)
      Fledge::Identity.from(config:, gemspec: nil, name: "CoolApp", root: dir)
    end
    true
  rescue Fledge::Error
    false
  end

  def test_is_a_draft_07_schema
    assert_equal "http://json-schema.org/draft-07/schema#", schema.fetch("$schema")
    assert_equal URL, schema.fetch("$id")
    assert_empty JSONSchemer.draft7.validate(schema).to_a
  end

  def test_knows_configs_keys_and_refuses_any_other
    assert_equal Fledge::Config::KEYS, schema.fetch("properties").keys
    assert_equal "object", schema.fetch("type")
    refute schema.fetch("additionalProperties")
    schema.fetch("properties").each do |key, property|
      refute_empty property.fetch("description").to_s, "#{key} has no description"
    end
  end

  def test_kinds_are_configs
    assert_equal [*Fledge::Config::KINDS, nil], schema.dig("properties", "kind", "enum")
    assert_equal "console", schema.dig("properties", "kind", "default")
  end

  def test_installers_are_configs
    installers = schema.dig("properties", "installers")
    assert_equal Fledge::Config::INSTALLERS, installers.dig("items", "enum")
    assert_equal Fledge::Config::DEFAULT_INSTALLERS, installers.fetch("default")
  end

  # Ruby's \A and \z are ECMA-262's ^ and $ without the multiline flag.
  def test_identifier_is_configs
    identifier = schema.dig("properties", "identifier")
    ecma = Fledge::Config::IDENTIFIER.source.sub(/\A\\A/, "^").sub(/\\z\z/, "$")
    assert_equal ecma, identifier.fetch("pattern")
    assert_equal Fledge::Config::IDENTIFIER_MAX, identifier.fetch("maxLength")
  end

  def test_agrees_with_fledge_on_every_document
    DOCUMENTS.each do |yaml, accepted|
      assert_equal accepted, fledge_accepts?(yaml), "fledge build #{accepted ? 'refused' : 'took'} #{yaml.inspect}"
      assert_equal accepted, schema_accepts?(yaml), "the schema #{accepted ? 'refused' : 'took'} #{yaml.inspect}"
    end
  end

  # Every fledge.yml in the repository names the schema, and both the
  # schema and fledge build take it.
  def test_every_fledge_yml_names_the_schema_and_passes_it
    files = IO.popen(["git", "ls-files", "-z", "--", "*fledge.yml"], chdir: ROOT, &:read).split("\x0")
    assert_includes files, "examples/windowed_app/fledge.yml"
    files.each do |file|
      yaml = File.read(File.join(ROOT, file))
      assert_includes yaml.lines.map(&:chomp), HEADER, "#{file} does not name the schema"
      assert schema_accepts?(yaml), "the schema refused #{file}: #{schemer.validate(YAML.safe_load(yaml)).map { |e| e['error'] }}"
      assert fledge_accepts?(yaml), "fledge build refused #{file}"
    end
  end
end
