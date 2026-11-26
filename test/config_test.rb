# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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
      icon: "art/icon", publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", description: nil, long_description: nil, homepage: nil, license_file: nil, installers: nil, programs: nil, ios: nil, android: nil, linux: nil, macos: nil, windows: nil,
      file_associations: nil, build_tools: nil), config
    assert_equal "console", load("kind: console\n").kind
    assert_equal "0.1.0.pre.2", load("version: 0.1.0.pre.2\n").version
  end

  # A macOS build number, held for CFBundleVersion
  # (doc/contributors/design/public-interface.md, "Reserved names").
  def test_reads_a_macos_build_number
    assert_equal "1.2.417", load("macos:\n  build: \"1.2.417\"\n").macos&.build
    assert_nil load("macos:\n  build:\n").macos&.build
    assert_nil load("name: A\n").macos
  end

  # The libraries from the developer's computer that a macOS app carries,
  # by the file names its gems' compiled files give them, once each
  # (doc/contributors/design/gems.md, "Libraries a Mac app carries").
  def test_reads_the_libraries_a_mac_app_carries
    config = load("macos:\n  carried_libraries: [libSDL3.0.dylib, libc++.1.dylib, libSDL3.0.dylib]\n")
    assert_equal ["libSDL3.0.dylib", "libc++.1.dylib"], config.macos&.carried_libraries
    assert_equal ["libSDL3.0.dylib", "libc++.1.dylib"], config.carried_libraries("darwin")
    assert_empty config.carried_libraries("linux")
    assert_empty load("macos:\n  build: \"4\"\n").carried_libraries("darwin")
    assert_empty load("name: A\n").carried_libraries("darwin")
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

  # A windowed app lists the installers it wants, once each, or
  # none; without the key it gets every one.
  def test_reads_the_installers_a_windowed_app_wants
    assert_equal %w[dmg appimage deb], load("kind: windowed\ninstallers: [dmg, appimage, dmg, deb]\n").installers
    assert_equal [], load("kind: windowed\ninstallers: []\n").installers
    assert_equal [], load("installers: []\n").installers
    assert_nil load("kind: windowed\n").installers
  end

  # An MSIX package's name and publisher are Partner Center's for the
  # Store, or the signing certificate's subject; msix asks for the
  # publisher, and the name defaults to the identifier.
  def test_reads_the_package_identity_of_an_msix
    config = load(<<~YAML)
      kind: windowed
      identifier: com.example.Hello
      installers: [nsis, msix]
      windows:
        msix_name: 12345Example.Hello
        msix_publisher: CN=1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D
    YAML

    assert_equal %w[nsis msix], config.installers
    assert_equal Fledge::Config::Windows.new(msix_name: "12345Example.Hello", msix_publisher: "CN=1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D",
      msix_dependencies: [], visual_c_runtime: nil), config.windows
    assert_nil load("windows:\n  msix_publisher: \"CN=Example, O=Example, C=US\"\n").windows.msix_name
    assert_equal "local", load("windows:\n  visual_c_runtime: local\n").windows.visual_c_runtime
    assert_equal "central", load("windows:\n  visual_c_runtime: central\n").windows.visual_c_runtime
    assert_nil load("kind: windowed\n").windows
  end

  # A package that needs a framework package, such as Microsoft's Windows
  # App Runtime, names it as a PackageDependency does: its name, its
  # publisher, and the oldest version that serves.
  def test_reads_the_framework_packages_an_msix_depends_on
    config = load(<<~YAML)
      windows:
        msix_publisher: CN=Example
        msix_dependencies:
          - name: Microsoft.WindowsAppRuntime.2
            publisher: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
            min_version: 2.7.0.0
          - name: Example.Framework
            publisher: CN=Example
            min_version: "1.0.0.0"
    YAML

    assert_equal [
      Fledge::Config::Windows::Dependency.new(name: "Microsoft.WindowsAppRuntime.2",
        publisher: "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US", min_version: "2.7.0.0"),
      Fledge::Config::Windows::Dependency.new(name: "Example.Framework", publisher: "CN=Example", min_version: "1.0.0.0"),
    ], config.windows.msix_dependencies
    assert_equal [], load("windows:\n  msix_publisher: CN=Example\n").windows.msix_dependencies
    assert_equal [], load("windows:\n  msix_dependencies:\n").windows.msix_dependencies
  end

  # Fledge takes no position on an app's gems' licenses (2026-10-28;
  # doc/contributors/design/gems.md, "Checks that are not about
  # licenses"), so the keys that corrected a gem's license or said what
  # its compiled code holds are gone, and fail like any other unknown key.
  def test_refuses_what_it_cannot_use
    known = "It knows name, kind, identifier, version, icon, publisher, copyright, description, long_description, homepage, license_file, installers, programs, ios, android, linux, macos, windows, file_associations, and build_tools."
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name, kind, identifier, version, icon, publisher, copyright, description, long_description, homepage, license_file, installers, programs, ios, android, linux, macos, windows, file_associations, and build_tools\z/,
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
      "license_file: ../LICENSE\n" => %r{: license_file, "\.\./LICENSE", must name a file in the project, with / between folders, such as license_file: LICENSE\.txt\z},
      "linux:\n  deb_changelog: /CHANGELOG\n" => %r{: linux: deb_changelog, "/CHANGELOG", must name a file in the project},
      "linux:\n  changelog: CHANGELOG\n" => /: linux has 'changelog', which Fledge does not know\. It knows system_libraries, system_typelibs, deb_depends, and deb_changelog\.\z/,
      "macos: \"42\"\n" => /: macos must be a mapping of build and carried_libraries, such as macos: \{ build: "42" \}\z/,
      "macos:\n  bulid: \"42\"\n" => /: macos has 'bulid', which Fledge does not know\. It knows build and carried_libraries\.\z/,
      "macos:\n  carried_libraries: libSDL3.0.dylib\n" => /: macos: carried_libraries must be a list of the names compiled files give libraries, such as \[libSDL3\.0\.dylib\]\z/,
      "macos:\n  carried_libraries: [/opt/homebrew/lib/libSDL3.0.dylib]\n" =>
        %r{: macos: carried_libraries has "/opt/homebrew/lib/libSDL3\.0\.dylib", which is not a library's name: name it as compiled files do, such as libSDL3\.0\.dylib, with no folder\z},
      "macos:\n  carried_libraries: [SDL3.framework]\n" => /: macos: carried_libraries has "SDL3\.framework", which is not a library's name/,
      "macos:\n  build: 42\n" => /: macos: build must be text; quote it, as in build: "42"\z/,
      "macos:\n  build: \"1.2.3.4\"\n" => /: macos: build must be one to three whole numbers between periods, as Apple's CFBundleVersion is, .* not 1\.2\.3\.4\z/,
      "macos:\n  build: \"1.0b2\"\n" => /: macos: build must be one to three whole numbers between periods/,
      "homepage: example.com\n" => %r{: homepage must be an http or https URL with no spaces, such as https://example\.com/cool-app, not example\.com\z},
      "homepage: \"https://example.com/a b\"\n" => /: homepage must be an http or https URL/,
      "kind: windowed\ninstallers: dmg\n" => /: installers must be a list of dmg, nsis, appimage, deb, msix, such as installers: \[dmg, nsis, appimage, deb\], or \[\] for none\z/,
      "kind: windowed\ninstallers: [msi]\n" => /: installers has msi, which Fledge does not build\. It builds dmg, nsis, appimage, deb, msix\.\z/,
      "installers: [dmg]\n" => /: only a windowed app has installers; a console app ships as its archive/,
      "kind: windowed\ninstallers: [msix]\n" => /: an msix installer needs windows: msix_publisher, the package's publisher: Partner Center's .* such as CN=Example\z/,
      "kind: windowed\ninstallers: [msix]\nwindows: {}\n" => /: an msix installer needs windows: msix_publisher/,
      "windows: CN=Example\n" => /: windows must be a mapping of msix_name, msix_publisher, msix_dependencies, and visual_c_runtime, such as windows: \{ msix_publisher: CN=Example \}\z/,
      "windows:\n  publisher: CN=Example\n" => /: windows has 'publisher', which Fledge does not know\. It knows msix_name, msix_publisher, msix_dependencies, and visual_c_runtime\.\z/,
      "windows:\n  visual_c_runtime: true\n" => /: windows: visual_c_runtime must be local, to copy Microsoft's Visual C\+\+ runtime from this computer into the app, or central, for computers that have the Visual C\+\+ Redistributable, not true\z/,
      "windows:\n  visual_c_runtime: app\n" => /: windows: visual_c_runtime must be local, .* not "app"\z/,
      "windows:\n  msix_name: ab\n" => /: windows: msix_name must be 3 to 50 letters, digits, periods, and hyphens, .* not "ab"\z/,
      "windows:\n  msix_name: My_App\n" => /: windows: msix_name must be 3 to 50/,
      "windows:\n  msix_name: #{'a' * 51}\n" => /: windows: msix_name must be 3 to 50/,
      "windows:\n  msix_publisher: Example\n" => /: windows: msix_publisher must be a distinguished name, such as CN=Example: .* not "Example"\z/,
      "windows:\n  msix_publisher: 3\n" => /: windows: msix_publisher must be a distinguished name/,
      "windows:\n  msix_dependencies: Microsoft.WindowsAppRuntime.2\n" => /: windows: msix_dependencies must be a list of mappings, each with a name, a publisher, and a min_version, not "Microsoft.WindowsAppRuntime.2"\z/,
      "windows:\n  msix_dependencies: [a]\n" => /: windows: msix_dependencies must be a list of mappings, each with a name, a publisher, and a min_version, not "a"\z/,
      "windows:\n  msix_dependencies:\n    - name: Example.Framework\n      publisher: CN=Example\n" => /: windows: msix_dependencies has an entry with no min_version, such as min_version: 1\.0\.0\.0\z/,
      "windows:\n  msix_dependencies:\n    - name: Example.Framework\n      min_version: 1.0.0.0\n" => /: windows: msix_dependencies has an entry with no publisher/,
      "windows:\n  msix_dependencies:\n    - publisher: CN=Example\n      min_version: 1.0.0.0\n" => /: windows: msix_dependencies has an entry with no name/,
      "windows:\n  msix_dependencies:\n    - {name: ab, publisher: CN=Example, min_version: 1.0.0.0}\n" => /: windows: msix_dependencies name must be 3 to 50 letters, digits, periods, and hyphens, .* not "ab"\z/,
      "windows:\n  msix_dependencies:\n    - {name: Example.Framework, publisher: Example, min_version: 1.0.0.0}\n" => /: windows: msix_dependencies publisher must be a distinguished name, such as CN=Example, .* not "Example"\z/,
      "windows:\n  msix_dependencies:\n    - {name: Example.Framework, publisher: CN=Example, min_version: 1.0}\n" => /: windows: msix_dependencies min_version must be four whole numbers between periods, each at most 65535, such as 2\.7\.0\.0, not 1\.0\z/,
      "windows:\n  msix_dependencies:\n    - {name: Example.Framework, publisher: CN=Example, min_version: 1.0.0.65536}\n" => /: windows: msix_dependencies min_version must be four whole numbers/,
      "windows:\n  msix_dependencies:\n    - {name: Example.Framework, publisher: CN=Example, min_version: 1.0.0.0, optional: true}\n" => /: windows: msix_dependencies has 'optional', which Fledge does not know\. It knows name, publisher, and min_version\.\z/,
      "windows:\n  msix_dependencies:\n    - {name: Example.Framework, publisher: CN=Example, min_version: 1.0.0.0}\n    - {name: Example.Framework, publisher: CN=Example, min_version: 2.0.0.0}\n" => /: windows: msix_dependencies lists Example\.Framework twice, which a package manifest does not allow\z/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  # programs lists each program's path, name, kind, identifier,
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
      publisher: "Me", copyright: nil, description: nil, long_description: nil, homepage: nil, license_file: nil, installers: nil, programs: nil, ios: nil, android: nil, linux: nil, macos: nil, windows: nil,
      file_associations: nil, build_tools: nil), config.for_program(config.programs.to_a.first)
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

  # doc/contributors/design/phone-projects.md, "Host files": ios and
  # android each name the folder of the project's own host files, which
  # fledge build ios or fledge build android copies over the project it
  # writes. The folder is checked when that phone's project is built, so
  # a desktop build never needs it.
  def test_reads_each_phones_host
    config = load("ios:\n  host: host/ios\nandroid:\n  host: host/android\n")

    assert_equal [Fledge::Config::Phone.new(host: "host/ios", host_libraries: []), Fledge::Config::Phone.new(host: "host/android", host_libraries: [])],
      [config.ios, config.android]
    assert_equal [nil, nil], [load("ios:\n").ios, load("android:\n  host:\n").android&.host]
    assert_equal "missing", load("ios:\n  host: missing\n").ios&.host, "the folder is a phone build's to check"
    program = Fledge::Config::Program.from({ "path" => "a" }, 1, "fledge.yml")
    assert_equal config.ios, config.for_program(program).ios
  end

  def test_refuses_a_host_it_cannot_copy
    {
      "ios: host/ios\n" => %r{: ios must be a mapping of host, such as ios: \{ host: host/ios \}\z},
      "android: [host]\n" => %r{: android must be a mapping of host and host_libraries, such as android: \{ host: host/android \}\z},
      "ios:\n  hots: host/ios\n" => /: ios has 'hots', which Fledge does not know\. It knows host\.\z/,
      "ios:\n  host_libraries: [libSDL3.so]\n" => /: ios has 'host_libraries', which Fledge does not know\. It knows host\.\z/,
      "android:\n  hots: host/android\n" => /: android has 'hots', which Fledge does not know\. It knows host and host_libraries\.\z/,
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

  # doc/contributors/design/phone-projects.md, "What each library
  # needs": android names, once each, the native libraries the app's
  # host adds to the APK through its own Gradle dependencies, each a
  # name Android's package installer extracts, lib*.so.
  def test_reads_the_libraries_an_android_host_adds
    config = load("android:\n  host_libraries: [libSDL3.so, libc++_shared.so, libSDL3.so]\n")

    assert_equal Fledge::Config::Phone.new(host: nil, host_libraries: %w[libSDL3.so libc++_shared.so]), config.android
    assert_equal [], load("android:\n  host: host/android\n").android&.host_libraries
    assert_equal [], load("android:\n  host_libraries: []\n").android&.host_libraries
  end

  def test_refuses_a_host_library_android_would_not_extract
    {
      "android:\n  host_libraries: libSDL3.so\n" =>
        /: android: host_libraries must be a list of the names compiled files give libraries, such as \[libSDL3\.so\]\z/,
      "android:\n  host_libraries: [3]\n" => /: android: host_libraries must be a list/,
      "android:\n  host_libraries: [libc.so.6]\n" =>
        /: android: host_libraries has "libc\.so\.6", which is not a name Android extracts from an APK: name a library lib\*\.so, with no folder, such as libSDL3\.so\z/,
      "android:\n  host_libraries: [SDL3.so]\n" => /: android: host_libraries has "SDL3\.so", which is not a name Android extracts/,
      "android:\n  host_libraries: [lib/x86_64/libSDL3.so]\n" => %r{: android: host_libraries has "lib/x86_64/libSDL3\.so", which is not},
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
    end
  end

  # The libraries a project's gems load from the Linux distribution
  # (doc/contributors/design/gems.md, "Libraries from the Linux
  # distribution"), by the names their compiled files give them, once
  # each.
  def test_reads_the_system_libraries_a_projects_gems_load_on_linux
    config = load("linux:\n  system_libraries: [libwebkit2gtk-4.1.so.0, libgtk-3.so.0, libwebkit2gtk-4.1.so.0]\n")

    assert_equal Fledge::Config::Linux.new(system_libraries: %w[libwebkit2gtk-4.1.so.0 libgtk-3.so.0], system_typelibs: [], deb_depends: [], deb_changelog: nil), config.linux
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

  # The relationships a .deb's Depends gains for what the app's Ruby
  # opens by itself (doc/contributors/design/desktop-apps.md, "Depends
  # on what the app's Ruby opens"), as Debian Policy 7.1 writes them,
  # once each, on Linux only.
  def test_reads_the_deb_dependencies_a_projects_ruby_needs_on_linux
    config = load("linux:\n  deb_depends: [libgtk-4-1, \"libadwaita-1-0 (>= 1.4)\", \"libfoo1t64 | libfoo1\", libgtk-4-1, \"libc6:any (>> 2.30)\"]\n")

    assert_equal ["libgtk-4-1", "libadwaita-1-0 (>= 1.4)", "libfoo1t64 | libfoo1", "libc6:any (>> 2.30)"], config.linux&.deb_depends
    assert_equal [], load("linux:\n  deb_depends: []\n").linux&.deb_depends
    assert_equal [], load("linux:\n  system_libraries: [libgtk-4.so.1]\n").linux&.deb_depends
    assert_equal [config.linux.deb_depends, [], []], %w[linux darwin windows].map { |os| config.deb_depends(os) }
    assert_equal [], Fledge::Config.none.deb_depends("linux")
  end

  # The GObject introspection data a project's gems load from the Linux
  # distribution by name while the app runs (doc/contributors/design/gems.md,
  # "Typelibs from the Linux distribution"), each as libgirepository
  # names a typelib, its namespace and version, once each.
  def test_reads_the_system_typelibs_a_projects_gems_load_on_linux
    config = load("linux:\n  system_typelibs: [Gtk-4.0, GdkPixbuf-2.0, cairo-1.0, HarfBuzz-0.0, Gtk-4.0]\n")

    assert_equal Fledge::Config::Linux.new(system_libraries: [], system_typelibs: %w[Gtk-4.0 GdkPixbuf-2.0 cairo-1.0 HarfBuzz-0.0], deb_depends: [], deb_changelog: nil),
      config.linux
    assert_equal [], load("linux:\n  system_typelibs: []\n").linux&.system_typelibs
    assert_equal [], load("linux:\n  system_libraries: [libgtk-4.so.1]\n").linux&.system_typelibs
    assert_equal [%w[Gtk-4.0 GdkPixbuf-2.0 cairo-1.0 HarfBuzz-0.0], [], []], %w[linux darwin windows].map { |os| config.system_typelibs(os) }
    assert_equal [], Fledge::Config.none.system_typelibs("linux")
  end

  def test_refuses_a_system_typelib_that_is_not_a_namespace_and_its_version
    {
      "linux:\n  system_typelibs: Gtk-4.0\n" =>
        /: linux: system_typelibs must be a list of GObject introspection namespaces and their versions, such as \[Gtk-4\.0\]\z/,
      "linux:\n  system_typelibs: [4]\n" => /: linux: system_typelibs must be a list/,
      "linux:\n  system_typelibs: [Gtk]\n" =>
        /: linux: system_typelibs has "Gtk", which is not a namespace and its version: name it as its typelib file is named, less \.typelib, such as Gtk-4\.0\z/,
      "linux:\n  system_typelibs: [Gtk-4.0.typelib]\n" => /: linux: system_typelibs has "Gtk-4\.0\.typelib", which is not a namespace and its version/,
      "linux:\n  system_typelibs: [/usr/lib/girepository-1.0/Gtk-4.0]\n" => /: linux: system_typelibs has ".+", which is not a namespace/,
      "linux:\n  system_typelibs: [Gtk-4]\n" => /: linux: system_typelibs has "Gtk-4", which is not a namespace/,
      "linux:\n  system_typelibs: [gir1.2-gtk-4.0]\n" => /: linux: system_typelibs has "gir1\.2-gtk-4\.0", which is not a namespace/,
      "linux:\n  system_typelibs: [\"Gtk-4.0 \"]\n" => /: linux: system_typelibs has "Gtk-4\.0 ", which is not a namespace/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  def test_refuses_a_deb_dependency_that_is_not_a_relationship
    {
      "linux:\n  deb_depends: libgtk-4-1\n" =>
        /: linux: deb_depends must be a list of the packages a \.deb depends on, such as \[libgtk-4-1\]\z/,
      "linux:\n  deb_depends: [4]\n" => /: linux: deb_depends must be a list/,
      "linux:\n  deb_depends: [libgtk-4.so.1]\n" =>
        /: linux: deb_depends has "libgtk-4\.so\.1", which is a library's soname and not a package: name the package that provides it, such as libgtk-4-1 for libgtk-4\.so\.1\z/,
      "linux:\n  deb_depends: [\"libfoo1 | libfoo.so.1\"]\n" => /: linux: deb_depends has "libfoo1 \| libfoo\.so\.1", which is a library's soname/,
      "linux:\n  deb_depends: [\"\"]\n" => /: linux: deb_depends has "", which is not a package and, if it has one, its version/,
      "linux:\n  deb_depends: [LibGTK]\n" =>
        /: linux: deb_depends has "LibGTK", which is not a package and, if it has one, its version: name it as Debian Policy 7\.1 does, such as "libgtk-4-1 \(>= 4\.6\)" or "libfoo1t64 \| libfoo1"\z/,
      "linux:\n  deb_depends: [a]\n" => /: linux: deb_depends has "a"/,
      "linux:\n  deb_depends: [\"libgtk-4-1, libadwaita-1-0\"]\n" => /: linux: deb_depends has "libgtk-4-1, libadwaita-1-0"/,
      "linux:\n  deb_depends: [\"libgtk-4-1 (>= )\"]\n" => /: linux: deb_depends has "libgtk-4-1 \(>= \)"/,
      "linux:\n  deb_depends: [\"libgtk-4-1 (> 4)\"]\n" => /: linux: deb_depends has "libgtk-4-1 \(> 4\)"/,
      "linux:\n  deb_depends: [\"libgtk-4-1 |\"]\n" => /: linux: deb_depends has "libgtk-4-1 \|"/,
      "linux:\n  deb_depends: [\"libgtk-4-1\\n\"]\n" => /: linux: deb_depends has "libgtk-4-1\\n"/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  def test_refuses_a_system_library_that_is_not_a_librarys_name
    {
      "linux: [libpng16.so.16]\n" =>
        /: linux must be a mapping of system_libraries, system_typelibs, deb_depends, and deb_changelog, such as linux: \{ system_libraries: \[libgtk-3\.so\.0\] \}\z/,
      "linux:\n  libraries: [libpng16.so.16]\n" => /: linux has 'libraries', which Fledge does not know\. It knows system_libraries, system_typelibs, deb_depends, and deb_changelog\.\z/,
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

  # The files and folders a windowed app opens: a viewer of
  # each unless it says editor, each list once each, and the list kept
  # for each program, where the windowed one declares it.
  def test_reads_the_files_and_folders_a_windowed_app_opens
    config = load(<<~YAML)
      kind: windowed
      identifier: com.example.A
      file_associations:
        - name: Project folder
          folders: true
        - name: Project archive
          role: editor
          extensions: [zip, ZIP, zip]
          mime_types: [application/zip]
          content_types: [public.zip-archive]
        - name: Lota game
          extensions: [lota]
          mime_types: [application/x-lota-game]
          defines_type: true
    YAML

    association = Fledge::Config::FileAssociation
    assert_equal [
      association.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true, defines_type: false),
      association.new(name: "Project archive", role: "editor", extensions: %w[zip ZIP], mime_types: ["application/zip"],
        content_types: ["public.zip-archive"], folders: false, defines_type: false),
      association.new(name: "Lota game", role: "viewer", extensions: ["lota"], mime_types: ["application/x-lota-game"],
        content_types: [], folders: false, defines_type: true),
    ], config.file_associations
    assert_equal config.file_associations, config.for_program(Fledge::Config::Program.from({ "path" => "a" }, 1, "fledge.yml")).file_associations
    assert_equal [], load("file_associations: []\n").file_associations
    assert_nil load("kind: windowed\nidentifier: com.example.A\nfile_associations:\n").file_associations
    windowed = "programs:\n  - path: a\n    kind: windowed\n    identifier: com.example.A\n  - path: b\n"
    assert_equal 1, load("#{windowed}file_associations:\n  - name: Text\n    mime_types: [text/plain]\n").file_associations&.size
  end

  def test_refuses_file_associations_it_cannot_declare
    windowed = "kind: windowed\nidentifier: com.example.A\nfile_associations:\n"
    {
      "file_associations:\n  - name: Text\n    extensions: [txt]\n" =>
        /: only a windowed app opens files and folders a person gives it; leave out file_associations, or make the app windowed\z/,
      "#{windowed}  name: Text\n" => /: file_associations must be a list of what the app opens, each a mapping such as - name: Project folder\z/,
      "#{windowed}  - Text\n" => /: file_associations' entry 1 must be a mapping of name, role, extensions, mime_types, content_types, folders, and defines_type/,
      "#{windowed}  - name: Text\n    extension: [txt]\n" => /: file_associations' entry 1 has 'extension', which Fledge does not know\. It knows name, role/,
      "#{windowed}  - extensions: [txt]\n" => /: file_associations' entry 1 needs a name, the kind of document a person sees, such as name: Project archive\z/,
      "#{windowed}  - name: \" \"\n    extensions: [txt]\n" => /: file_associations' entry 1 needs a name/,
      "#{windowed}  - name: Text\n    role: owner\n    extensions: [txt]\n" => /: file_associations' entry 1: role must be viewer or editor, not owner\z/,
      "#{windowed}  - name: Text\n    extensions: [.txt]\n" => /: file_associations' entry 1: extensions must be a list such as \[zip, txt\], without the dot\z/,
      "#{windowed}  - name: Text\n    extensions: txt\n" => /: file_associations' entry 1: extensions must be a list such as/,
      "#{windowed}  - name: Text\n    extensions: [tar.gz]\n" => /: file_associations' entry 1: extensions must be a list/,
      "#{windowed}  - name: Text\n    mime_types: [text]\n" => %r{: file_associations' entry 1: mime_types must be a list such as \[application/zip\]\z},
      "#{windowed}  - name: Text\n    content_types: [text]\n" => /: file_associations' entry 1: content_types must be a list such as \[public\.zip-archive\]\z/,
      "#{windowed}  - name: Text\n    folders: yes please\n" => /: file_associations' entry 1: folders must be true or false\z/,
      "#{windowed}  - name: Text\n" => /: file_associations' entry 1 names nothing to open: give it extensions, mime_types, content_types, or folders: true\z/,
      "#{windowed}  - name: Text\n    folders: false\n    extensions: []\n" => /: file_associations' entry 1 names nothing to open/,
      "#{windowed}  - name: Text\n    extensions: [txt]\n  - name: Both\n    folders: true\n    extensions: [txt]\n" =>
        /: file_associations' entry 2 is for folders and files; give the files an entry of their own\z/,
      "#{windowed}  - name: Game\n    extensions: [game]\n    mime_types: [application/x-game]\n    defines_type: yes please\n" =>
        /: file_associations' entry 1: defines_type must be true or false\z/,
      "#{windowed}  - name: Game\n    mime_types: [application/x-game]\n    defines_type: true\n" =>
        %r{: file_associations' entry 1 defines a type, so give it the extensions its files end in and its one MIME type, such as extensions: \[game\] and mime_types: \[application/x-game\]\z},
      "#{windowed}  - name: Game\n    extensions: [game]\n    defines_type: true\n" => /: file_associations' entry 1 defines a type, so give it/,
      "#{windowed}  - name: Game\n    extensions: [game]\n    mime_types: [application/x-game, application/x-game2]\n    defines_type: true\n" =>
        /: file_associations' entry 1 defines a type, so give it/,
      "#{windowed}  - name: Folder\n    folders: true\n    defines_type: true\n" => /: file_associations' entry 1 defines a type, so give it/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end

  # build_tools: whether the app carries what fledge build
  # --from needs, for any kind of app.
  def test_reads_whether_the_app_carries_its_build_tools
    assert_equal [true, false, nil], ["build_tools: true\n", "build_tools: false\n", "build_tools:\n"].map { |yaml| load(yaml).build_tools }
    error = assert_raises(Fledge::Error) { load("build_tools: rcedit\n") }
    assert_match(/fledge\.yml: build_tools must be true or false, such as build_tools: true\z/, error.message)
  end
end
