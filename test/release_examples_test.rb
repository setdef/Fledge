# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/release_examples"
require "tmpdir"

# The example apps a release carries (doc/contributors/design/releases.md,
# "The examples a release carries"): which files each platform's job
# stages, what a release's folder of them must hold, and how each is named.
class ReleaseExamplesTest < Minitest::Test
  VERSION = "1.2.3"

  # Every folder under examples/ is carried, or is left out with a reason,
  # so that an example added later is not missing from a release unnoticed.
  def test_every_example_is_carried_or_left_out_with_a_reason
    folders = Dir.children(File.join(ReleaseExamples::ROOT, "examples")).select { |name| File.directory?(File.join(ReleaseExamples::ROOT, "examples", name)) }

    assert_empty folders - ReleaseExamples::DESKTOP - ReleaseExamples::LEFT_OUT.keys, "examples/ folders no release carries, and no LEFT_OUT entry says why"
    assert_empty ReleaseExamples::DESKTOP & ReleaseExamples::LEFT_OUT.keys
    assert_empty (ReleaseExamples::DESKTOP + ReleaseExamples::LEFT_OUT.keys) - folders, "listed, but not under examples/"
    assert(ReleaseExamples::LEFT_OUT.values.all? { |reason| reason.length > 20 })
  end

  def test_a_desktop_example_is_its_archive_and_each_installer_its_fledge_yml_lists
    assert_equal [["Hello-x86_64-linux.tar.gz", "fledge-example-hello-1.2.3-x86_64-linux.tar.gz"]], hello("x86_64-linux")
    assert_equal [["Hello-x64-mingw-ucrt.zip", "fledge-example-hello-1.2.3-x64-mingw-ucrt.zip"]], hello("x64-mingw-ucrt")

    markdown = ReleaseExamples.desktop("x64-mingw-ucrt", version: VERSION).select { |source, _| source.start_with?("Markdown to HTML") }
    assert_equal [
      ["Markdown to HTML-x64-mingw-ucrt.zip", "fledge-example-markdown-to-html-1.2.3-x64-mingw-ucrt.zip"],
      ["Markdown to HTML-x64-mingw-ucrt-setup.exe", "fledge-example-markdown-to-html-1.2.3-x64-mingw-ucrt-setup.exe"],
], markdown
  end

  def test_basket_is_carried_with_every_installer_but_not_on_musl
    sources = -> (platform) { ReleaseExamples.desktop(platform, version: VERSION).map(&:first).grep(/\ABasket-/) }

    assert_equal %w[Basket-arm64-darwin.tar.gz Basket-arm64-darwin.dmg], sources.("arm64-darwin")
    assert_equal %w[Basket-x64-mingw-ucrt.zip Basket-x64-mingw-ucrt-setup.exe Basket-x64-mingw-ucrt.msix], sources.("x64-mingw-ucrt")
    assert_equal %w[Basket-aarch64-linux.tar.gz Basket-aarch64-linux.AppImage Basket-aarch64-linux.deb], sources.("aarch64-linux")
    assert_empty sources.("x86_64-linux-musl")
  end

  def test_a_musl_example_gets_no_deb
    sources = ReleaseExamples.desktop("aarch64-linux-musl", version: VERSION).map(&:first)

    assert_includes sources, "Markdown to HTML-aarch64-linux-musl.AppImage"
    refute(sources.any? { |source| source.end_with?(".deb") })
  end

  def test_the_phone_examples_are_those_the_phone_jobs_build_from_examples
    assert_equal %w[Hello Basket], ReleaseExamples.phones.map(&:last)
  end

  def test_names_tell_example_platform_and_version_apart_and_are_never_a_runtimes
    assets = ReleaseExamples.assets(version: VERSION)

    assert_equal assets.uniq, assets
    assets.each { |name| assert_match(/\Afledge-example-[a-z0-9-]+-1\.2\.3-[a-z0-9_-]+\.[A-Za-z.]+\z/, name) }
    assert_includes assets, "fledge-example-basket-1.2.3-android.apk"
    assert_includes assets, "fledge-example-hello-1.2.3-ios-project.tar.gz"
    assert_empty assets & RuntimeBuilder.release_assets(version: VERSION)
    assert_equal Fledge::Platform.names.size, assets.grep(/-hello-/).grep(/(?<!project)\.(tar\.gz|zip)\z/).size
  end

  def test_staging_copies_each_file_under_its_release_name
    in_tmp do |dir|
      dist = populate(dir, "dist", ReleaseExamples.desktop("x64-mingw-ucrt", version: VERSION).map(&:first) + ["Parity-x64-mingw-ucrt.zip"])

      staged = ReleaseExamples.stage_desktop(dist, File.join(dir, "out"), platform: "x64-mingw-ucrt", version: VERSION)

      assert_equal ReleaseExamples.desktop("x64-mingw-ucrt", version: VERSION).map(&:last), staged
      assert_equal staged.sort, Dir.children(File.join(dir, "out")).sort
      assert_equal "Hello-x64-mingw-ucrt.zip", File.read(File.join(dir, "out", "fledge-example-hello-1.2.3-x64-mingw-ucrt.zip"))
    end
  end

  def test_staging_refuses_a_dist_that_lacks_an_example_and_copies_nothing
    in_tmp do |dir|
      files = ReleaseExamples.desktop("arm64-darwin", version: VERSION).map(&:first) - ["Lectern-arm64-darwin.tar.gz"]
      dist = populate(dir, "dist", files)

      error = assert_raises(ReleaseExamples::Mismatch) { ReleaseExamples.stage_desktop(dist, File.join(dir, "out"), platform: "arm64-darwin", version: VERSION) }

      assert_includes error.message, "Lectern-arm64-darwin.tar.gz"
      refute_path_exists File.join(dir, "out")
    end
  end

  def test_android_stages_each_debug_apk_by_the_apps_name
    in_tmp do |dir|
      apks = populate(dir, "apks", %w[com.setdef.fledge.Hello.apk com.setdef.fledge.Basket.apk com.setdef.fledge.Parity.apk com.setdef.fledge.Hello.apks])

      staged = ReleaseExamples.stage_android(apks, File.join(dir, "out"), version: VERSION)

      assert_equal %w[fledge-example-hello-1.2.3-android.apk fledge-example-basket-1.2.3-android.apk], staged
      assert_equal "com.setdef.fledge.Basket.apk", File.read(File.join(dir, "out", "fledge-example-basket-1.2.3-android.apk"))
      assert_raises(ReleaseExamples::Mismatch) { ReleaseExamples.stage_android(File.join(dir, "empty"), File.join(dir, "out2"), version: VERSION) }
    end
  end

  def test_ios_archives_each_projects_folder
    in_tmp do |dir|
      projects = File.join(dir, "projects")
      %w[Hello Basket Parity].each do |name|
        FileUtils.mkdir_p(File.join(projects, name, "#{name}.xcodeproj"))
        File.write(File.join(projects, name, "#{name}.xcodeproj", "project.pbxproj"), name)
      end

      staged = ReleaseExamples.stage_ios(projects, File.join(dir, "out"), version: VERSION)

      assert_equal %w[fledge-example-hello-1.2.3-ios-project.tar.gz fledge-example-basket-1.2.3-ios-project.tar.gz], staged
      assert_equal "Basket", Fledge::Archive.read(File.join(dir, "out", staged.last), "Basket/Basket.xcodeproj/project.pbxproj")
      assert_raises(ReleaseExamples::Mismatch) { ReleaseExamples.stage_ios(File.join(dir, "none"), File.join(dir, "out2"), version: VERSION) }
    end
  end

  def test_a_folder_of_exactly_the_releases_examples_passes
    in_tmp do |dir|
      folder = populate(dir, "release-examples", ReleaseExamples.assets(version: VERSION))

      ReleaseExamples.check(folder, version: VERSION)
    end
  end

  def test_a_folder_missing_a_file_or_holding_another_or_an_empty_one_fails
    in_tmp do |dir|
      assets = ReleaseExamples.assets(version: VERSION)
      missing = populate(dir, "missing", assets - [assets.first])
      stray = populate(dir, "stray", assets + ["stray.txt"])
      empty = populate(dir, "empty", assets)
      File.write(File.join(empty, assets.last), "")

      assert_includes assert_raises(ReleaseExamples::Mismatch) { ReleaseExamples.check(missing, version: VERSION) }.message, "missing: #{assets.first}"
      assert_includes assert_raises(ReleaseExamples::Mismatch) { ReleaseExamples.check(stray, version: VERSION) }.message, "unexpected: stray.txt"
      assert_includes assert_raises(ReleaseExamples::Mismatch) { ReleaseExamples.check(empty, version: VERSION) }.message, assets.last
    end
  end

  private def hello(platform) = ReleaseExamples.desktop(platform, version: VERSION).select { |source, _| source.start_with?("Hello-") }

  private def in_tmp(&) = Dir.mktmpdir(&)

  # A folder +name+ in +dir+ holding a file for each of +files+, each
  # with its own name as its content.
  private def populate(dir, name, files)
    folder = File.join(dir, name)
    FileUtils.mkdir_p(folder)
    files.each { |file| File.write(File.join(folder, file), file) }
    folder
  end
end
