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
      icon: art/icon
      publisher: Example, Inc.
      copyright: © 2026 Example, Inc.
    YAML
    assert_equal Fledge::Config.new(name: "Hello Window", kind: "windowed", identifier: "com.example.Hello-Window", version: "1.10",
      icon: "art/icon", publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", installers: nil, programs: nil), config
    assert_equal "console", load("kind: console\n").kind
    assert_equal "0.1.0.pre.2", load("version: 0.1.0.pre.2\n").version
  end

  # A windowed app lists the installers it wants (ADR 009), once each, or
  # none; without the key it gets every one.
  def test_reads_the_installers_a_windowed_app_wants
    assert_equal %w[dmg appimage deb], load("kind: windowed\ninstallers: [dmg, appimage, dmg, deb]\n").installers
    assert_equal [], load("kind: windowed\ninstallers: []\n").installers
    assert_equal [], load("installers: []\n").installers
    assert_nil load("kind: windowed\n").installers
  end

  # Fledge takes no position on an app's gems' licenses (2026-10-28; ADR
  # 007), so the keys that corrected a gem's license or said what its
  # compiled code holds are gone, and fail like any other unknown key.
  def test_refuses_what_it_cannot_use
    known = "It knows name, kind, identifier, version, icon, publisher, copyright, installers, and programs."
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name, kind, identifier, version, icon, publisher, copyright, installers, and programs\z/,
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
      "icon: 3\n" => %r{: icon must be text, such as icon: icons/app\z},
      "icon: art/icon.png\n" => %r{: icon names the icon's files without an extension, such as icon: art/icon for art/icon\.icns, \.ico, and -16\.png to -512\.png\z},
      "publisher: [a]\n" => /: publisher must be text/,
      "copyright: true\n" => /: copyright must be text/,
      "kind: windowed\ninstallers: dmg\n" => /: installers must be a list of dmg, nsis, appimage, deb, such as installers: \[dmg, nsis, appimage, deb\], or \[\] for none\z/,
      "kind: windowed\ninstallers: [msi]\n" => /: installers has msi, which Fledge does not build\. It builds dmg, nsis, appimage, deb\.\z/,
      "installers: [dmg]\n" => /: only a windowed app has installers; a console app ships as its archive/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  # ADR 024: programs lists each program's path, name, kind, identifier,
  # and icon, in order; a name defaults to the path's file name without
  # its extension.
  def test_reads_a_projects_programs
    config = load(<<~YAML)
      name: Deckbuilder
      version: "1.0.0"
      installers: [dmg]
      programs:
        - path: gui/main.rb
          name: Deckbuilder
          kind: windowed
          identifier: com.example.Deckbuilder
          icon: icons/deck
        - path: bin/cli
        - path: bin/tui.rb
          name: deckbuilder-tui
    YAML

    program = Fledge::Config::Program
    assert_equal [
      program.new(path: "gui/main.rb", name: "Deckbuilder", kind: "windowed", identifier: "com.example.Deckbuilder", icon: "icons/deck"),
      program.new(path: "bin/cli", name: "cli", kind: nil, identifier: nil, icon: nil),
      program.new(path: "bin/tui.rb", name: "deckbuilder-tui", kind: nil, identifier: nil, icon: nil),
    ], config.programs
    assert_equal [true, false, false], config.programs.to_a.map(&:windowed?)
    assert_equal %w[Deckbuilder 1.0.0], [config.name, config.version]
    assert_equal ["dmg"], config.installers
  end

  # A program's configuration is the project's with the program's own
  # name, kind, identifier, and icon.
  def test_a_programs_configuration_is_the_projects_with_its_own_identity
    config = load("version: \"2.0\"\npublisher: Me\nprograms:\n  - path: w.rb\n    kind: windowed\n    identifier: com.example.W\n    icon: art\n")

    assert_equal Fledge::Config.new(name: "w", kind: "windowed", identifier: "com.example.W", version: "2.0", icon: "art",
      publisher: "Me", copyright: nil, installers: nil, programs: nil), config.for_program(config.programs.to_a.first)
  end

  def test_refuses_programs_it_cannot_ship
    {
      "programs: []\n" => %r{: programs must be a list of at least one program, each a mapping such as - path: bin/cli\z},
      "programs: bin/cli\n" => /: programs must be a list/,
      "programs:\n  - bin/cli\n" => %r{: program 1 must be a mapping of path, name, kind, identifier, and icon, such as - path: bin/cli\z},
      "programs:\n  - name: cli\n" => %r{: program 1 has no path, the program's file in the project, such as path: bin/cli\z},
      "programs:\n  - path: a\n  - path: [b]\n" => %r{: program 2: path must be text, such as path: bin/cli\z},
      "programs:\n  - path: ../elsewhere/cli\n" => %r{: program 1's path, "\.\./elsewhere/cli", must name a file in the project},
      "programs:\n  - path: /usr/bin/cli\n" => %r{: program 1's path, "/usr/bin/cli", must name a file in the project},
      "programs:\n  - path: bin\\\\cli\n" => /: program 1's path, .* must name a file in the project/,
      "programs:\n  - path: \"bin/cli \"\n" => /: program 1's path, .* must name a file in the project/,
      "programs:\n  - path: bin/cli\n    paht: x\n" => %r{: the program bin/cli has 'paht', which Fledge does not know\. A program knows path, name, kind, identifier, and icon\.\z},
      "programs:\n  - path: bin/cli\n    kind: gui\n" => %r{: the program bin/cli: kind must be console or windowed, not gui\z},
      "programs:\n  - path: bin/cli\n    identifier: cli\n" => %r{: the program bin/cli: identifier must be reverse-DNS},
      "programs:\n  - path: bin/cli\n    icon: cli.png\n" => %r{: the program bin/cli: icon names the icon's files without an extension},
      "programs:\n  - path: a/cli\n  - path: b/CLI.rb\n" => %r{: a/cli and b/CLI\.rb are both named cli; give each its own\z},
      "programs:\n  - path: a\n    identifier: com.example.A\n  - path: b\n    identifier: com.example.a\n" =>
        /: a and b are both identified as com\.example\.A; give each its own\z/,
      "programs:\n  - path: a\n    kind: windowed\n    identifier: com.example.A\n  - path: b\n    kind: windowed\n    identifier: com.example.B\n" =>
        /: a and b are both windowed, and a project has one windowed program; build another on its own, with fledge build b\z/,
      "kind: windowed\nprograms:\n  - path: a\n" => /: with programs, kind belongs to each program; move it into the program it describes\z/,
      "identifier: com.example.A\nprograms:\n  - path: a\n" => /: with programs, identifier belongs to each program/,
      "icon: art\nprograms:\n  - path: a\n" => /: with programs, icon belongs to each program/,
      "installers: [dmg]\nprograms:\n  - path: a\n" => /: only a windowed app has installers/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  # A windowed program among them is what installers are for.
  def test_installers_need_a_windowed_program
    yaml = "installers: [dmg]\nprograms:\n  - path: a\n  - path: b\n    kind: windowed\n    identifier: com.example.B\n"

    assert_equal ["dmg"], load(yaml).installers
  end
end
