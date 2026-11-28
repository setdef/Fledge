# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "find"
require_relative "test_helper"
require_relative "support/fake_extensions"
require_relative "../lib/fledge/mobile_project"

# A host copies a template's file to replace it at its path, with Fledge's
# marks in it, so those paths and marks are frozen for 1.x. A new file
# or mark is compatible; a path or a mark that goes away breaks every
# host that copied it.
class MobileTemplateContractTest < Minitest::Test
  PATHS = {
    "ios" => %w[
      Host/Assets.xcassets/AppIcon.appiconset/Contents.json
      Host/Assets.xcassets/Contents.json
      Host/Info.plist
      Host/PrivacyInfo.xcprivacy
      Host/main.m
      project.yml
    ],
    "android" => %w[
      .gitignore
      build.gradle
      gradle.properties
      gradle/wrapper/gradle-wrapper.jar
      gradle/wrapper/gradle-wrapper.properties
      gradlew
      gradlew.bat
      settings.gradle
      src/main/AndroidManifest.xml
      src/main/java/org/setdef/fledge/host/MainActivity.java
      src/main/res/values/strings.xml
    ],
  }.freeze

  MARKS = {
    "ios" => { "project.yml" => %w[APP_ICON EXTENSIONS IDENTIFIER LDFLAGS NAME RUBY_EMBED VERSION] },
    "android" => {
      "build.gradle" => %w[APPLICATION_ID VERSION_CODE VERSION_NAME],
      "settings.gradle" => %w[AGP PROJECT_NAME],
      "src/main/AndroidManifest.xml" => %w[ICON],
      "src/main/java/org/setdef/fledge/host/MainActivity.java" => %w[LOAD_EXTENSIONS],
      "src/main/res/values/strings.xml" => %w[NAME],
    },
  }.freeze

  # The native libraries an Android host may load by name, frozen with
  # the paths: a host that owns
  # startup names its libraries in a fixed list, as SDL's SDLActivity
  # does in getLibraries(), and fails to start when one is missing, so a
  # name that is not in every app it is promised for breaks every such
  # host, whether or not Fledge's own MainActivity still loads it.
  # libfledgeruby.so is the runtime's AAR's, in every app; each other is
  # the project's own, in every app with a gem whose extension fledge
  # build compiles.
  ANDROID_LIBRARIES = %w[fledgeruby fledgeext].freeze

  def template(system)
    File.join(Fledge::MobileProject::TEMPLATES, system)
  end

  def files(system)
    Find.find(template(system)).select { |path| File.file?(path) }.map { |path| path.delete_prefix("#{template(system)}/") }
  end

  def marks(system, path)
    File.binread(File.join(template(system), path)).scrub.scan(Fledge::MobileProject::TOKEN).flatten.uniq.sort
  end

  %w[ios android].each do |system|
    define_method(:"test_every_path_#{system}_hosts_may_replace_is_still_there") do
      assert_empty PATHS.fetch(system) - files(system), "These paths are frozen for 1.x: a host replaces them by name"
    end

    define_method(:"test_every_mark_#{system}_hosts_may_copy_is_still_there") do
      MARKS.fetch(system).each do |path, expected|
        assert_empty expected - marks(system, path), "The marks of #{path} are frozen for 1.x: a host copies them"
      end
    end

    # A new mark is compatible, and once a host can copy it, frozen too.
    define_method(:"test_the_snapshot_of_#{system}_marks_is_complete") do
      found = files(system).filter_map { |path| [path, marks(system, path)] unless marks(system, path).empty? }.to_h

      assert_equal MARKS.fetch(system), found, "A mark was added or moved: add it to MARKS, where it is frozen as well"
    end
  end

  # libfledgeruby.so comes in the runtime's AAR, which the project's
  # build.gradle names; the runtime's build checks the AAR holds it.
  def test_an_android_project_carries_libfledgeruby_from_the_runtimes_aar
    project = android_project(nil)

    assert_includes ANDROID_LIBRARIES, "fledgeruby"
    assert_path_exists File.join(project, "libs", "FledgeRuby.aar")
    assert_includes File.read(File.join(project, "build.gradle")), "implementation files('libs/FledgeRuby.aar')"
  end

  # libfledgeext.so is in each ABI of every app with a gem whose
  # extension fledge build compiles, whatever the extensions came to:
  # linked into it, each a library of its own that Ruby loads as a file,
  # or nothing at all, as a Rakefile that builds nothing gives.
  {
    "an extension linked in" => { registrations: [["tally/tally", "Init_fledge_0"]], libraries: [] },
    "an extension built as a file" => { registrations: [], libraries: ["adder/adder"] },
    "a build that gave no extension" => { registrations: [], libraries: [] },
  }.each do |case_name, extensions|
    define_method(:"test_an_android_app_with_#{case_name.tr(' ', '_')}_carries_libfledgeext") do
      project = android_project(extensions)

      (ANDROID_LIBRARIES - ["fledgeruby"]).product(%w[arm64-v8a x86_64]).each do |name, abi|
        assert_path_exists File.join(project, "src", "main", "jniLibs", abi, "lib#{name}.so"), "#{case_name}: a host loads #{name} by name"
      end
    end
  end

  def test_an_android_app_with_no_extension_carries_no_libfledgeext
    refute_path_exists File.join(android_project(nil), "src", "main", "jniLibs")
  end

  # Writes the Android project of a script app whose gems' extensions
  # came to +extensions+ (the features registered, and those built as
  # files) for both ABIs, or that has none, and returns its folder.
  private def android_project(extensions)
    dir = Dir.mktmpdir
    @dirs = [*@dirs, dir]
    app = Fledge::App.at(FakeApp.write(dir).tap { |root| File.write(File.join(root, "fledge.yml"), "identifier: com.example.Hello\n") })
    runtime = FakeRuntime.write_mobile(dir, Fledge::MobilePlatform.find("android"))
    compiler = extensions && FakeExtensions.new(built(dir, **extensions))
    Fledge::MobileProject::Android.new(app:, runtime:, out: File.join(dir, "dist"), extensions: compiler).call
  end

  private def built(dir, registrations:, libraries:)
    targets = { "aarch64-linux-android" => "arm64-v8a", "x86_64-linux-android" => "x86_64" }.to_h do |name, abi|
      target = Fledge::MobileExtensions::Target.new(name:, root: dir, arch_dir: dir, libdir: dir, environment: {}, abi:)
      files = libraries.map do |feature|
        path = File.join(dir, abi, "#{feature}.so")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "ELF #{feature}")
        Fledge::MobileExtensions::Library.new(gem: "adder", feature:, path:, flags: [], links: ["app/gems/#{feature}.so"])
      end
      [name, Fledge::MobileExtensions::TargetBuild.new(target:, archives: [], flags: [], cxx: false, libraries: files, ffi_libraries: [])]
    end
    Fledge::MobileExtensions::Built.new(registrations:, targets:, ndk: nil, stubs: [], left: [], apart: {})
  end

  def teardown
    (@dirs || []).each { |dir| FileUtils.rm_rf(dir) }
  end
end
