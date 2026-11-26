# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "runtime_builder"
require_relative "runtime_pins"
require_relative "mobile_parity"

# The example apps a release carries, built (doc/contributors/design/releases.md,
# "The examples a release carries"). CI's jobs stage each example's files
# under the names the release gives them, in artifacts named
# <tt>example-*</tt>, and release.yml checks that the folder it gathered
# from them holds exactly the files this module expects at the tagged
# commit, and attaches them.
#
#   ruby tasks/release_examples.rb stage-desktop DIST OUT PLATFORM
#   ruby tasks/release_examples.rb stage-android APKS OUT
#   ruby tasks/release_examples.rb stage-ios PROJECTS OUT
#   ruby tasks/release_examples.rb check FOLDER
#   ruby tasks/release_examples.rb names
#
# A file is named <tt>fledge-example-NAME-VERSION-PLATFORM.EXTENSION</tt>:
# NAME is the app's name as <tt>fledge.yml</tt> gives it, in lowercase
# letters, digits and hyphens, since GitHub turns a space in an asset's
# name into a period; VERSION is Fledge's, the release's. An Android app
# is a <tt>.apk</tt> on the platform +android+; an iOS app is its Xcode
# project in a <tt>.tar.gz</tt> on +ios+, with <tt>-project</tt> after the
# platform, since it is no app a person installs.
module ReleaseExamples
  # The assets staged or found are not the ones a release carries.
  class Mismatch < StandardError; end

  # The checkout the examples are read from.
  ROOT = File.expand_path("..", __dir__)

  # What every asset's name starts with, which tells an example from a
  # runtime (+fledge-runtime-+), so that a release's runtimes and its
  # examples are told apart by name alone.
  PREFIX = "fledge-example-"

  # The folders under examples/ built for each desktop platform, then
  # delivered, by ci.yml's Build and Delivery jobs, each in the folder
  # +dist+ of its job.
  DESKTOP = %w[hello file_drop markdown_to_html lectern basket libui_app lota_pop].freeze

  # The platforms no Build job builds an example for, by folder.
  # Basket's Ruby draws its window with GTK 4 and libadwaita on Linux,
  # which musl Linux's job does not build it for (ci.yml's Build (musl)
  # job). Lota publishes no gem for musl Linux, and LibUI none for musl
  # Linux or Windows on ARM64, so neither app runs there, under
  # <tt>bundle exec</tt> or built.
  NOT_BUILT_ON = {
    "basket" => %w[x86_64-linux-musl aarch64-linux-musl],
    "libui_app" => %w[x86_64-linux-musl aarch64-linux-musl aarch64-mingw-ucrt],
    "lota_pop" => %w[x86_64-linux-musl aarch64-linux-musl],
  }.freeze

  # The platforms an example is built for and no release carries, by
  # folder, each with why. An example is added to DESKTOP, or here with
  # every platform it is built for, before a test lets it be added to
  # examples/ (test/release_examples_test.rb).
  LEFT_OUT = {
    "libui_app" => {
      "x64-mingw-ucrt" => "Focus Timer's app there carries Microsoft's Visual C++ runtime (fledge.yml's windows: visual_c_runtime: local), " \
        "which nothing setdef publishes may carry (decisions, 2026-11-21), so ci.yml builds it outside dist and uploads none of it",
    },
    "lota_pop" => %w[x64-mingw-ucrt aarch64-mingw-ucrt].to_h do |platform|
      [platform, "Delivery does not check Pop there yet: on GitHub's Windows runners, which have no GPU, its window is 0x0 and the game never ends itself (issue 163)"]
    end,
  }.freeze

  # The files of the desktop examples on +platform+, each as the pair of
  # the name CI's Build job leaves it under in +dist+ and the name the
  # release gives it: an archive, and every installer the example's
  # <tt>fledge.yml</tt> lists for the platform (Fledge::Installers).
  def self.desktop(platform, version: Fledge::VERSION, root: ROOT)
    platform = Fledge::Platform.find(platform)
    carried = DESKTOP.reject { |folder| NOT_BUILT_ON.fetch(folder, []).include?(platform.name) || LEFT_OUT.fetch(folder, {}).key?(platform.name) }
    carried.flat_map do |folder|
      app = Fledge::App.at(File.join(root, "examples", folder))
      base = "#{app.name}-#{platform.name}"
      [base + platform.archive_extension, *Fledge::Installers.formats(app, platform).map { |format| Fledge::Installers.file_name(format, base) }].map do |file|
        [file, asset(app.name, version, platform.name, file.delete_prefix(base))]
      end
    end
  end

  # The phone apps of the examples: the apps of the parity check that
  # live under examples/ (tasks/mobile_parity.rb), the ones every phone
  # job builds and runs.
  def self.phones(root: ROOT)
    MobileParity::APPS.select { |app| app.path.start_with?("examples/") }.map do |app|
      [app, Fledge::App.at(File.join(root, app.path)).name]
    end
  end

  # Every file a release of +version+ carries, sorted.
  def self.assets(version: Fledge::VERSION, root: ROOT)
    desktop = Fledge::Platform.names.flat_map { |platform| desktop(platform, version:, root:).map(&:last) }
    phones = phones(root:).flat_map { |_, name| [asset(name, version, "android", ".apk"), asset(name, version, "ios-project", ".tar.gz")] }
    (desktop + phones).sort
  end

  # The name of the file of the app +name+, on +platform+, with +suffix+
  # after it.
  def self.asset(name, version, platform, suffix)
    "#{PREFIX}#{name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')}-#{version}-#{platform}#{suffix}"
  end

  # Copies from +dist+ into +out+, under the release's names, every file
  # of the desktop examples on +platform+. Raises Mismatch, and copies
  # nothing, when +dist+ lacks one.
  def self.stage_desktop(dist, out, platform:, version: Fledge::VERSION, root: ROOT)
    files = desktop(platform, version:, root:)
    missing = files.map(&:first).reject { |file| File.file?(File.join(dist, file)) }
    raise Mismatch, "#{dist} lacks the examples' files for #{platform}: #{missing.join(', ')}" unless missing.empty?

    FileUtils.mkdir_p(out)
    files.each { |file, asset| FileUtils.cp(File.join(dist, file), File.join(out, asset)) }
    files.map(&:last)
  end

  # Copies from +apks+ into +out+ the debug APK of each phone example,
  # which CI's Android job names after the app's identifier
  # (MobileParity::Android::APKS).
  def self.stage_android(apks, out, version: Fledge::VERSION, root: ROOT)
    found = phones(root:).map do |app, name|
      [File.join(apks, "#{app.identifier}.apk"), asset(name, version, "android", ".apk")]
    end
    missing = found.map(&:first).reject { |file| File.file?(file) }
    raise Mismatch, "#{apks} lacks #{missing.join(', ')}" unless missing.empty?

    FileUtils.mkdir_p(out)
    found.map do |file, asset|
      FileUtils.cp(file, File.join(out, asset))
      asset
    end
  end

  # Archives into +out+ the Xcode project that <tt>fledge build ios</tt>
  # wrote for each phone example, found under +projects+ as the folder
  # that holds NAME.xcodeproj, into a <tt>.tar.gz</tt> of the folder.
  def self.stage_ios(projects, out, version: Fledge::VERSION, root: ROOT)
    found = phones(root:).map do |_, name|
      [Dir.glob(File.join(projects, "{*,*/*}", "#{name}.xcodeproj")).map { |path| File.dirname(path) }.first, name]
    end
    missing = found.select { |folder, _| folder.nil? }.map(&:last)
    raise Mismatch, "#{projects} holds no Xcode project of #{missing.join(', ')}" unless missing.empty?

    FileUtils.mkdir_p(out)
    found.map do |folder, name|
      asset(name, version, "ios-project", ".tar.gz").tap { |file| Fledge::Archive.pack(folder, to: File.join(out, file)) }
    end
  end

  # Raises Mismatch unless +folder+ holds exactly the files a release of
  # +version+ carries, and none of them empty.
  def self.check(folder, version: Fledge::VERSION, root: ROOT)
    found = Dir.children(folder).sort
    RuntimePins.check(found, assets(version:, root:))
  rescue RuntimePins::Mismatch => e
    raise Mismatch, e.message.sub("The assets", "The examples")
  else
    empty = found.select { |name| File.size(File.join(folder, name)).zero? }
    raise Mismatch, "Empty examples: #{empty.join(', ')}" unless empty.empty?
  end
end

if $PROGRAM_NAME == __FILE__
  command, *args = ARGV
  begin
    case command
    when "stage-desktop" then puts ReleaseExamples.stage_desktop(args.fetch(0), args.fetch(1), platform: args.fetch(2))
    when "stage-android" then puts ReleaseExamples.stage_android(args.fetch(0), args.fetch(1))
    when "stage-ios" then puts ReleaseExamples.stage_ios(args.fetch(0), args.fetch(1))
    when "check"
      ReleaseExamples.check(args.fetch(0))
      puts Dir.children(args.fetch(0)).sort
    when "names" then puts ReleaseExamples.assets
    else abort "usage: release_examples.rb stage-desktop DIST OUT PLATFORM | stage-android APKS OUT | stage-ios PROJECTS OUT | check FOLDER | names"
    end
  rescue ReleaseExamples::Mismatch => e
    abort "error: #{e.message}"
  end
end
