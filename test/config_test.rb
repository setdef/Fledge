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
      icon: "art/icon", publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", description: nil, long_description: nil, homepage: nil, installers: nil, programs: nil, ios: nil, android: nil, linux: nil), config
    assert_equal "console", load("kind: console\n").kind
    assert_equal "0.1.0.pre.2", load("version: 0.1.0.pre.2\n").version
  end

  # What an app says about itself: a line, paragraphs, and a web page,
  # which a program of several takes from the project.
  def test_reads_what_an_app_says_about_itself
    config = load("description: Keeps notes\nlong_description: |\n  Notes.\n\n  More.\nhomepage: https://example.com/notes\n" \
      "programs:\n  - path: a.rb\n")
    assert_equal ["Keeps notes", "Notes.\n\nMore.\n", "https://example.com/notes"], [config.description, config.long_description, config.homepage]
    program = config.for_program(config.programs.to_a.first)
    assert_equal ["Keeps notes", "https://example.com/notes"], [program.description, program.homepage]
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
    known = "It knows name, kind, identifier, version, icon, publisher, copyright, description, long_description, homepage, installers, programs, ios, android, and linux."
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name, kind, identifier, version, icon, publisher, copyright, description, long_description, homepage, installers, programs, ios, android, and linux\z/,
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
      "description: \"One.\\nTwo.\"\n" => /: description must be one line; put the rest in long_description\z/,
      "long_description: [a]\n" => /: long_description must be text/,
      "homepage: example.com\n" => %r{: homepage must be an http or https URL with no spaces, such as https://example\.com/cool-app, not example\.com\z},
      "homepage: \"https://example.com/a b\"\n" => /: homepage must be an http or https URL/,
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
      name: MyGame
      version: "1.0.0"
      installers: [dmg]
      programs:
        - path: gui/main.rb
          name: MyGame
          kind: windowed
          identifier: com.example.MyGame
          icon: icons/deck
        - path: bin/cli
        - path: bin/tui.rb
          name: my-game-tui
    YAML

    program = Fledge::Config::Program
    assert_equal [
      program.new(path: "gui/main.rb", name: "MyGame", kind: "windowed", identifier: "com.example.MyGame", icon: "icons/deck"),
      program.new(path: "bin/cli", name: "cli", kind: nil, identifier: nil, icon: nil),
      program.new(path: "bin/tui.rb", name: "my-game-tui", kind: nil, identifier: nil, icon: nil),
    ], config.programs
    assert_equal [true, false, false], config.programs.to_a.map(&:windowed?)
    assert_equal %w[MyGame 1.0.0], [config.name, config.version]
    assert_equal ["dmg"], config.installers
  end

  # A windowed program with no name has none in fledge.yml's reading:
  # Fledge::App gives it the project's, which only it knows.
  def test_a_windowed_program_with_no_name_is_left_for_the_project_to_name
    config = load("programs:\n  - path: gui/main.rb\n    kind: windowed\n    identifier: com.example.W\n  - path: bin/cli\n")

    assert_equal [nil, "cli"], config.programs.to_a.map(&:name)
    assert_nil config.for_program(config.programs.to_a.first).name
  end

  # A program's configuration is the project's with the program's own
  # name, kind, identifier, and icon.
  def test_a_programs_configuration_is_the_projects_with_its_own_identity
    config = load("version: \"2.0\"\npublisher: Me\nprograms:\n  - path: w.rb\n    name: W\n    kind: windowed\n    identifier: com.example.W\n    icon: art\n")

    assert_equal Fledge::Config.new(name: "W", kind: "windowed", identifier: "com.example.W", version: "2.0", icon: "art",
      publisher: "Me", copyright: nil, description: nil, long_description: nil, homepage: nil, installers: nil, programs: nil, ios: nil, android: nil, linux: nil), config.for_program(config.programs.to_a.first)
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

  # ADR 025, section 5: ios and android each name the folder of the
  # project's own host files, which fledge build ios or fledge build
  # android copies over the project it writes. The folder is checked when
  # that phone's project is built, so a desktop build never needs it.
  def test_reads_each_phones_host
    config = load("ios:\n  host: host/ios\nandroid:\n  host: host/android\n")

    assert_equal [Fledge::Config::Phone.new(host: "host/ios"), Fledge::Config::Phone.new(host: "host/android")], [config.ios, config.android]
    assert_equal [nil, nil], [load("ios:\n").ios, load("android:\n  host:\n").android&.host]
    assert_equal "missing", load("ios:\n  host: missing\n").ios&.host, "the folder is a phone build's to check"
    program = Fledge::Config::Program.from({ "path" => "a" }, 1, "fledge.yml")
    assert_equal config.ios, config.for_program(program).ios
  end

  def test_refuses_a_host_it_cannot_copy
    {
      "ios: host/ios\n" => %r{: ios must be a mapping of host, such as ios: \{ host: host/ios \}\z},
      "android: [host]\n" => %r{: android must be a mapping of host, such as android: \{ host: host/android \}\z},
      "ios:\n  hots: host/ios\n" => /: ios has 'hots', which Fledge does not know\. It knows host\.\z/,
      "ios:\n  host: 3\n" => %r{: ios: host must be text, such as host: host/ios\z},
      "android:\n  host: ../shared/android\n" =>
        %r{: android's host, "\.\./shared/android", must name a folder in the project, with / between folders, such as host: host/android\z},
      "ios:\n  host: /Users/me/host\n" => %r{: ios's host, "/Users/me/host", must name a folder in the project},
      "ios:\n  host: .\n" => /: ios's host, "\.", must name a folder in the project/,
      "ios:\n  host: host/\n" => %r{: ios's host, "host/", must name a folder in the project},
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  # The libraries a project's gems load from the Linux distribution (ADR
  # 030), by the names their compiled files give them, once each.
  def test_reads_the_system_libraries_a_projects_gems_load_on_linux
    config = load("linux:\n  system_libraries: [libwebkit2gtk-4.1.so.0, libgtk-3.so.0, libwebkit2gtk-4.1.so.0]\n")

    assert_equal Fledge::Config::Linux.new(system_libraries: %w[libwebkit2gtk-4.1.so.0 libgtk-3.so.0]), config.linux
    assert_equal [], load("linux:\n  system_libraries: []\n").linux&.system_libraries
    assert_equal [], load("linux: {}\n").linux&.system_libraries
    assert_nil load("linux:\n").linux
    assert_equal %w[libc.musl-x86_64.so.1 libstdc++.so.6 libfoo.so],
      load("linux:\n  system_libraries: [libc.musl-x86_64.so.1, libstdc++.so.6, libfoo.so]\n").linux&.system_libraries
    program = Fledge::Config::Program.from({ "path" => "a" }, 1, "fledge.yml")
    assert_equal config.linux, config.for_program(program).linux
    assert_equal [%w[libwebkit2gtk-4.1.so.0 libgtk-3.so.0], [], []], %w[linux darwin windows].map { |os| config.system_libraries(os) }
    assert_equal [], Fledge::Config.none.system_libraries("linux")
  end

  def test_refuses_a_system_library_that_is_not_a_librarys_name
    {
      "linux: [libpng16.so.16]\n" =>
        /: linux must be a mapping of system_libraries, such as linux: \{ system_libraries: \[libgtk-3\.so\.0\] \}\z/,
      "linux:\n  libraries: [libpng16.so.16]\n" => /: linux has 'libraries', which Fledge does not know\. It knows system_libraries\.\z/,
      "linux:\n  system_libraries: libpng16.so.16\n" =>
        /: linux: system_libraries must be a list of the names compiled files give libraries, such as \[libgtk-3\.so\.0\]\z/,
      "linux:\n  system_libraries: [3]\n" => /: linux: system_libraries must be a list/,
      "linux:\n  system_libraries: [/usr/lib/libpng16.so.16]\n" =>
        %r{: linux: system_libraries has "/usr/lib/libpng16\.so\.16", which is not a library's name: name it as compiled files do, such as libgtk-3\.so\.0, with no folder\z},
      "linux:\n  system_libraries: [libpng16]\n" => /: linux: system_libraries has "libpng16", which is not a library's name/,
      "linux:\n  system_libraries: [libpng16-16t64]\n" => /: linux: system_libraries has "libpng16-16t64", which is not a library's name/,
      "linux:\n  system_libraries: [\"libpng16.so.16 \"]\n" => /: linux: system_libraries has "libpng16\.so\.16 ", which is not a library's name/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end
end
