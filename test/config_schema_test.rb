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
    "programs:\n  - path: bin/cli\n" => true,
    "programs:\n  - path: bin/cli\n    name: cli\n    kind: console\n    identifier: com.example.Cli\n    icon: icons/cli\n" => true,
    "programs:\n  - path: gui/main.rb\n    kind: windowed\n    identifier: com.example.Gui\n  - path: bin/cli\n" => true,
    "programs:\n  - path: gui/main.rb\n    kind: windowed\n" => false,
    "programs:\n  - path: bin/cli\n    name:\n    kind:\n    identifier:\n    icon:\n" => true,
    "programs: []\n" => false,
    "programs: bin/cli\n" => false,
    "programs:\n  - bin/cli\n" => false,
    "programs:\n  - name: cli\n" => false,
    "programs:\n  - path:\n" => false,
    "programs:\n  - path: bin/cli\n    paht: x\n" => false,
    "programs:\n  - path: bin/cli\n    kind: gui\n" => false,
    "programs:\n  - path: bin/cli\n    identifier: cli\n" => false,
    "programs:\n  - path: bin/cli\n    icon: cli.png\n" => false,
    "programs:\n  - path: bin/cli\n    name: \" \"\n" => false,
    "programs:\n  - path: \"bin/my cli\"\n" => true,
    "programs:\n  - path: .hidden/cli\n" => true,
    "programs:\n  - path: ../cli\n" => false,
    "programs:\n  - path: bin/./cli\n" => false,
    "programs:\n  - path: bin/..\n" => false,
    "programs:\n  - path: /bin/cli\n" => false,
    "programs:\n  - path: bin//cli\n" => false,
    "programs:\n  - path: bin/\n" => false,
    "programs:\n  - path: bin\\\\cli\n" => false,
    "programs:\n  - path: \" bin/cli\"\n" => false,
    "programs:\n  - path: \"bin/cli\\t\"\n" => false,
    "programs:\n  - path: \"bin/cli\\nx\"\n" => false,
    "kind: windowed\nidentifier: com.example.A\nprograms:\n  - path: a\n" => false,
    "identifier: com.example.A\nprograms:\n  - path: a\n" => false,
    "icon: art\nprograms:\n  - path: a\n" => false,
    "kind:\nprograms:\n  - path: a\n" => true,
    "installers: [dmg]\nprograms:\n  - path: a\n" => false,
    "installers: [dmg]\nprograms:\n  - path: a\n  - path: b\n    kind: windowed\n    identifier: com.example.B\n" => true,
    "ios:\n  host: host/ios\nandroid:\n  host: host/android\n" => true,
    "ios:\n  host:\n" => true,
    "ios: {}\n" => true,
    "ios: host/ios\n" => false,
    "android: [host]\n" => false,
    "ios:\n  hots: host/ios\n" => false,
    "ios:\n  host: 3\n" => false,
    "ios:\n  host: \" \"\n" => false,
    "android:\n  host: ../android\n" => false,
    "android:\n  host: /host/android\n" => false,
    "android:\n  host: .\n" => false,
    "android:\n  host: host/\n" => false,
    "android:\n  host: host\\\\android\n" => false,
  }.merge(
    # Every key may be empty, which Config reads as absent, and none may
    # be blank or a number.
    *Fledge::Config::KEYS.map { |key| { "#{key}:\n" => true, "#{key}: \" \\t\"\n" => false, "#{key}: 7\n" => false } }
  ).freeze

  # Documents Config refuses and no draft-07 schema can: draft-07 has no
  # way to say that at most one item of a list matches, or that items
  # differ in one property (ADR 024, section 2). An editor takes them; the
  # build refuses them, naming what to change.
  CONFIG_ONLY = [
    "programs:\n  - path: a\n    kind: windowed\n    identifier: com.example.A\n  - path: b\n    kind: windowed\n    identifier: com.example.B\n",
    "programs:\n  - path: a/cli\n  - path: b/cli\n",
    "programs:\n  - path: a\n    name: Same\n  - path: b\n    name: same\n",
    "programs:\n  - path: a\n    identifier: com.example.A\n  - path: b\n    identifier: com.example.A\n",
  ].freeze

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
      [config, *config.programs.to_a.map { |program| config.for_program(program) }].each do |each|
        Fledge::Identity.from(config: each, gemspec: nil, name: "CoolApp", root: dir)
      end
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

  # A program's keys and kinds are Config::Program's, and its identifier
  # and icon follow the app's rules.
  def test_programs_are_configs
    item = schema.dig("properties", "programs", "items")
    assert_equal Fledge::Config::Program::KEYS, item.fetch("properties").keys
    assert_equal ["path"], item.fetch("required")
    refute item.fetch("additionalProperties")
    assert_equal [*Fledge::Config::KINDS, nil], item.dig("properties", "kind", "enum")
    assert_equal({ "$ref" => "#/properties/identifier" }, item.dig("properties", "identifier"))
    assert_equal({ "$ref" => "#/properties/icon" }, item.dig("properties", "icon"))
    assert_equal Fledge::Config::PER_PROGRAM, schema.fetch("allOf").first.dig("then", "properties").keys
  end

  # Each phone's mapping holds Config::Phone's keys, and its host is a
  # path as a program's is.
  def test_phones_are_configs
    Fledge::Config::PHONES.each do |phone|
      property = schema.dig("properties", phone)
      assert_equal Fledge::Config::Phone::KEYS, property.fetch("properties").keys
      refute property.fetch("additionalProperties")
      assert_equal schema.dig("properties", "programs", "items", "properties", "path", "pattern"), property.dig("properties", "host", "pattern")
    end
  end

  def test_only_config_refuses_what_draft_07_cannot_say
    CONFIG_ONLY.each do |yaml|
      refute fledge_accepts?(yaml), "fledge build took #{yaml.inspect}"
      assert schema_accepts?(yaml), "the schema refused #{yaml.inspect}"
    end
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
