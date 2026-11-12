# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "rexml/document"

# Fledge::Msix: the manifest and the mapping file it gives MakeAppx.
# test/integration/msix_test.rb has the Windows SDK's MakeAppx pack one
# on Windows, and Delivery installs one, signed with a test certificate,
# runs the app from it, and removes it (.github/scripts/deliver-msix.ps1).
class MsixTest < Minitest::Test
  X64 = Fledge::Platform.find("x64-mingw-ucrt")
  ARM64 = Fledge::Platform.find("aarch64-mingw-ucrt")
  PUBLISHER = "CN=Example, O=Example, C=US"

  def setup
    @dist = Dir.mktmpdir("msix-test")
    @folder = File.join(@dist, "My App-x64-mingw-ucrt")
    [
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755),
      Fledge::Entry.file("fledge.cfg", "# Written by fledge build\nentry = main.rb\nidentifier = com.example.MyApp\n"),
      Fledge::Entry.file("app/main.rb", "puts 1\n"),
      Fledge::Entry.file("ruby/bin/x64-ucrt-ruby410.dll", "MZ"),
      Fledge::Entry.file("icons/app-44.png", "png"),
      Fledge::Entry.file("icons/app-50.png", "png"),
      Fledge::Entry.file("icons/app-150.png", "png"),
    ].each { |entry| entry.write_into(@folder) }
    @icon = Fledge::Icon.new(base: File.join(@folder, "icons", "app"), name: "icons/app")
  end

  def teardown
    FileUtils.rm_rf(@dist)
  end

  def identity(name: "My App", publisher: "Example, Inc.", version: "1.2.3.pre.4", identifier: "com.example.MyApp", icon: @icon, description: nil,
    file_associations: []
  )
    Fledge::Identity.new(name:, kind: "windowed", identifier:, version:, publisher:, copyright: nil, icon:, description:,
      long_description: nil, homepage: nil, file_associations:)
  end

  def windows(msix_name: nil, msix_publisher: PUBLISHER)
    Fledge::Config::Windows.new(msix_name:, msix_publisher:)
  end

  def msix(identity: self.identity, windows: self.windows, platform: X64, env: {})
    Fledge::Msix.new(identity:, windows:, folder: @folder, platform:, to: "#{@folder}.msix", env:)
  end

  def manifest(**) = REXML::Document.new(msix(**).manifest)

  def first(document, path) = REXML::XPath.first(document, path, Fledge::Msix::NAMESPACES.transform_keys { |key| key.delete_prefix("xmlns").delete_prefix(":").then { |prefix| prefix.empty? ? "m" : prefix } })

  # Partner Center's Package/Identity/Name and Publisher, or the
  # identifier, with the Store's version: three numbers and a 0, which
  # the Store keeps for itself.
  def test_the_identity_is_the_packages
    identity = first(manifest, "/m:Package/m:Identity")

    assert_equal ["com.example.MyApp", PUBLISHER, "1.2.3.0", "x64"], %w[Name Publisher Version ProcessorArchitecture].map { |key| identity.attributes[key] }
    named = first(manifest(windows: windows(msix_name: "12345Example.MyApp"), platform: ARM64), "/m:Package/m:Identity")
    assert_equal %w[12345Example.MyApp arm64], [named.attributes["Name"], named.attributes["ProcessorArchitecture"]]
    assert_equal "7.0.0.0", first(manifest(identity: identity(version: "7")), "/m:Package/m:Identity").attributes["Version"]
  end

  # A desktop app packaged by hand, as Microsoft's "Generating MSIX
  # package components" describes one: full trust, for Windows.Desktop,
  # with the logos its manifest must name.
  def test_it_is_a_full_trust_desktop_app
    document = manifest(identity: identity(description: "Says <hello> & more"))

    assert_equal ["My App", "Example, Inc.", "Says <hello> & more", "Assets\\StoreLogo.png"],
      %w[DisplayName PublisherDisplayName Description Logo].map { |key| first(document, "/m:Package/m:Properties/m:#{key}").text }
    family = first(document, "/m:Package/m:Dependencies/m:TargetDeviceFamily")
    assert_equal %w[Windows.Desktop 10.0.17763.0 10.0.26100.0], %w[Name MinVersion MaxVersionTested].map { |key| family.attributes[key] }
    assert_equal "runFullTrust", first(document, "/m:Package/m:Capabilities/rescap:Capability").attributes["Name"]
    assert_equal "en-us", first(document, "/m:Package/m:Resources/m:Resource").attributes["Language"]
    application = first(document, "/m:Package/m:Applications/m:Application")
    assert_equal ["App", "My App.exe", "Windows.FullTrustApplication"], %w[Id Executable EntryPoint].map { |key| application.attributes[key] }
    visual = first(document, "/m:Package/m:Applications/m:Application/uap:VisualElements")
    assert_equal ["My App", "Says <hello> & more", "transparent", "Assets\\Square150x150Logo.png", "Assets\\Square44x44Logo.png"],
      %w[DisplayName Description BackgroundColor Square150x150Logo Square44x44Logo].map { |key| visual.attributes[key] }
    assert_equal "My App", first(manifest, "/m:Package/m:Applications/m:Application/uap:VisualElements").attributes["Description"]
  end

  # ADR 052: each extension the app opens is offered in its "Open with",
  # by a file type association named in lower case; folders and MIME
  # types alone have no place in a package.
  def test_the_extensions_it_opens_are_file_type_associations
    associations = [
      Fledge::Config::FileAssociation.new(name: "My Report", role: "editor", extensions: %w[myreport MyRep], mime_types: [], content_types: [], folders: false),
      Fledge::Config::FileAssociation.new(name: "Folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true),
      Fledge::Config::FileAssociation.new(name: "my report!", role: "viewer", extensions: ["old"], mime_types: [], content_types: [], folders: false),
      Fledge::Config::FileAssociation.new(name: "Text", role: "viewer", extensions: [], mime_types: ["text/plain"], content_types: [], folders: false),
    ]
    document = manifest(identity: identity(file_associations: associations))
    found = REXML::XPath.match(document, "//uap:FileTypeAssociation", "uap" => Fledge::Msix::NAMESPACES.fetch("xmlns:uap")).map do |element|
      [element.attributes["Name"], element.elements["uap:DisplayName"].text, element.get_elements("uap:SupportedFileTypes/uap:FileType").map(&:text)]
    end

    assert_equal [["myreport", "My Report", %w[.myreport .myrep]], ["myreport2", "my report!", [".old"]]], found
    assert_equal "windows.fileTypeAssociation", first(document, "//uap:Extension").attributes["Category"]
    assert_nil first(manifest, "//m:Extensions")
  end

  # MakeAppx packs every file of the folder at its path, with the
  # manifest, the logos, and a fledge.cfg with no identifier, so that the
  # launcher leaves the process the package's own AppUserModelID.
  def test_the_mapping_puts_the_folder_in_the_package
    lines = msix.mapping(File.join(@dist, "work")).split("\r\n")
    host = -> (path) { Fledge::Nsis.host_path(path) }

    assert_equal "[Files]", lines.first
    assert_equal %("#{host.(File.join(@dist, 'work', 'AppxManifest.xml'))}" "AppxManifest.xml"), lines[1]
    assert_equal %("#{host.(File.join(@dist, 'work', 'fledge.cfg'))}" "fledge.cfg"), lines[2]
    assert_includes lines, %("#{host.("#{@icon.base}-44.png")}" "Assets\\Square44x44Logo.png")
    assert_includes lines, %("#{host.("#{@icon.base}-50.png")}" "Assets\\StoreLogo.png")
    assert_includes lines, %("#{host.("#{@icon.base}-150.png")}" "Assets\\Square150x150Logo.png")
    assert_includes lines, %("#{host.(File.join(@folder, 'ruby/bin/x64-ucrt-ruby410.dll'))}" "ruby\\bin\\x64-ucrt-ruby410.dll")
    assert_includes lines, %("#{host.(File.join(@folder, 'My App.exe'))}" "My App.exe")
    assert_equal 1, lines.count { |line| line.end_with?(%("fledge.cfg")) }
    assert_equal "# Written by fledge build\nentry = main.rb\n",
      Fledge::Msix.packaged_config(File.read(File.join(@folder, "fledge.cfg")))
    assert_equal "[main]\nentry = a.rb\n[gui]\nentry = b.rb\n",
      Fledge::Msix.packaged_config("[main]\nentry = a.rb\nidentifier = com.example.A\n[gui]\nentry = b.rb\nidentifier = com.example.B\n")
  end

  def test_it_says_what_a_package_needs
    {
      -> { msix(identity: identity(icon: nil)).manifest } => /an msix installer needs fledge\.yml's icon\. An MSIX package takes one PNG of each size, -44, -50, -150/,
      -> { msix(windows: nil).manifest } => /needs fledge\.yml's windows: msix_publisher/,
      -> { msix(identity: identity(publisher: nil)).manifest } => /needs a publisher to show/,
      -> { msix(identity: identity(identifier: "com.example.#{'a' * 40}")).manifest } => /cannot name an MSIX package.*give fledge\.yml's windows an msix_name/,
      -> { msix(platform: Fledge::Platform.find("x86_64-linux")).manifest } => /an msix installer is for Windows/,
      -> { msix(identity: identity(version: "1.70000")).manifest } => /larger than Windows' version numbers hold/,
    }.each do |build, message|
      assert_match message, assert_raises(Fledge::Error) { build.call }.message
    end
    File.delete("#{@icon.base}-50.png")
    assert_match(%r{icons/app-50\.png does not exist}, assert_raises(Fledge::Error) { msix.manifest }.message)
  end

  # Without MakeAppx on PATH or in a Windows SDK, the build says how to
  # get it, and leaves no package behind.
  def test_it_needs_makeappx
    File.write("#{@folder}.msix", "old")
    error = assert_raises(Fledge::Error) { msix(env: { "PATH" => "", "ProgramFiles(x86)" => @dist }).write }

    assert_match(/\Aan msix installer needs makeappx, which is on no PATH and in no Windows SDK\. Install the Windows SDK/, error.message)
    refute_path_exists "#{@folder}.msix"
  end
end
