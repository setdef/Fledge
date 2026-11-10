# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "find"
require_relative "test_helper"
require_relative "../lib/fledge/mobile_project"

# ADR 025 (doc/contributors/design/public-interface.md, "Frozen for
# 1.x", and doc/contributors/design/phones.md, "Host files"): a host
# copies a template's file to replace it at its path, with Fledge's
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
    "ios" => { "project.yml" => %w[APP_ICON EXTENSIONS IDENTIFIER LDFLAGS NAME VERSION] },
    "android" => {
      "build.gradle" => %w[APPLICATION_ID VERSION_CODE VERSION_NAME],
      "settings.gradle" => %w[AGP PROJECT_NAME],
      "src/main/AndroidManifest.xml" => %w[ICON],
      "src/main/java/org/setdef/fledge/host/MainActivity.java" => %w[LOAD_EXTENSIONS],
      "src/main/res/values/strings.xml" => %w[NAME],
    },
  }.freeze

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
      assert_empty PATHS.fetch(system) - files(system), "public-interface.md, \"Frozen for 1.x\", freezes these paths: a host replaces them by name"
    end

    define_method(:"test_every_mark_#{system}_hosts_may_copy_is_still_there") do
      MARKS.fetch(system).each do |path, expected|
        assert_empty expected - marks(system, path), "public-interface.md, \"Frozen for 1.x\", freezes the marks of #{path}"
      end
    end

    # A new mark is compatible, and once a host can copy it, frozen too.
    define_method(:"test_the_snapshot_of_#{system}_marks_is_complete") do
      found = files(system).filter_map { |path| [path, marks(system, path)] unless marks(system, path).empty? }.to_h

      assert_equal MARKS.fetch(system), found, "A mark was added or moved: add it to MARKS, where it is frozen as well"
    end
  end
end
