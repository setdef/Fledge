# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "../error"
require_relative "../icon"
require_relative "../mac_bundle"

module Fledge
  class MobileProject
    # An app's Gradle project for Android, as Fledge::MobileProject
    # describes it (ADR 012).
    #
    # The project is one Android app module, with Gradle's own wrapper,
    # pinned to the Gradle Fledge's runtime is built with, as Briefcase's,
    # Tauri's, and React Native's Android projects carry one, so
    # <tt>./gradlew assembleDebug</tt> builds it with nothing but a JDK
    # and the Android SDK, and Android Studio opens it. The runtime's
    # <tt>FledgeRuby.aar</tt> is in <tt>libs/</tt>; its <tt>lib/</tt> and
    # <tt>libexec/</tt> are in ROOT, which the build stores as the asset
    # <tt>fledge.zip</tt> that <tt>org.setdef.fledge.FledgeRuby</tt>
    # unpacks (ADR 011, section 2). The app's identifier is its
    # <tt>applicationId</tt>, its name its label, its version its
    # <tt>versionName</tt> and, as a number, its <tt>versionCode</tt>
    # (#version_code); and when <tt>fledge.yml</tt> names an icon,
    # <tt>ICON-48.png</tt> to <tt>ICON-192.png</tt> are its launcher icon
    # in each density's <tt>mipmap-</tt> folder.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileProject::Android.new(app:, runtime:, out:).call # => "/path/to/dist/Hello-android"
    #--
    # SPDX-SnippetEnd
    #++
    class Android < MobileProject
      # The Android Gradle plugin's version, the one Fledge's runtime is
      # built and checked with (<tt>runtime/sources.yml</tt>).
      AGP = "9.4.1"

      # An identifier Android takes as an <tt>applicationId</tt>: two or
      # more parts between dots, each a letter and then letters, digits,
      # and underscores.
      APPLICATION_ID = /\A[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+\z/

      # The largest <tt>versionCode</tt> Google Play takes.
      VERSION_CODE_MAX = 2_100_000_000

      # The runtime's files the project takes: the library, in +libs+, and
      # Ruby, in ROOT.
      AAR = "FledgeRuby.aar"

      # The <tt>versionCode</tt> for +version+: each of its first three
      # numbers in three digits, as Briefcase pads a version's parts into
      # one, so that each later version has a greater code, and 1 for
      # 0.0.0, since Android takes no code below 1. Raises Fledge::Error for
      # a version whose second or third number is above 999, or whose code
      # would be above VERSION_CODE_MAX.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::Android.version_code("1.2.3")       # => 1002003
      #   Fledge::MobileProject::Android.version_code("0.1.0.pre.1") # => 1000
      #   Fledge::MobileProject::Android.version_code("0.0.0")       # => 1
      #--
      # SPDX-SnippetEnd
      #++
      def self.version_code(version)
        major, minor, patch = MacBundle.bundle_version(version).split(".").map(&:to_i)
        code = (major.to_i * 1_000_000) + (minor.to_i * 1000) + patch.to_i
        if minor.to_i > 999 || patch.to_i > 999 || code > VERSION_CODE_MAX
          raise Error, "Android needs a whole-number versionCode no greater than #{VERSION_CODE_MAX}, which Fledge makes from " \
            "the version's numbers, three digits each, and #{version} does not fit"
        end

        [code, 1].max
      end

      # Where the runtime's Ruby is in its archive, for
      # Fledge::RuntimeContents.read: at its top, one tree for both ABIs.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::Android.ruby_under # => ""
      #--
      # SPDX-SnippetEnd
      #++
      def self.ruby_under
        ""
      end

      private def system
        "android"
      end

      private def template_files
        %w[settings.gradle build.gradle src/main/AndroidManifest.xml src/main/res/values/strings.xml]
      end

      # The values for the templates' marks, each written as the file that
      # holds it reads it: Groovy's single-quoted strings in the Gradle
      # files, and an Android string resource in XML for the name.
      private def tokens
        version = @app.identity.version
        {
          "AGP" => AGP,
          "PROJECT_NAME" => groovy(@app.name),
          "APPLICATION_ID" => application_id,
          "VERSION_CODE" => Android.version_code(version).to_s,
          "VERSION_NAME" => groovy(version),
          "NAME" => string_resource(@app.name),
          "ICON" => @app.identity.icon ? ' android:icon="@mipmap/ic_launcher"' : "",
        }
      end

      private def application_id
        id = identifier
        return id if id.match?(APPLICATION_ID)

        raise Error, "#{File.join(@app.root, Config::FILE)}: Android takes #{id} for no applicationId: each part between its dots " \
          "must begin with a letter and hold only letters, digits, and underscores, such as #{id.tr('-', '_').gsub(/\.(?=\d)/, '.a')}"
      end

      private def groovy(text)
        text.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      end

      # +text+ as an Android string resource reads it: its backslashes and
      # quotation marks escaped, a leading <tt>@</tt> or <tt>?</tt> too,
      # and XML's own characters as entities.
      private def string_resource(text)
        escaped = text.gsub(/[\\'"]/) { |character| "\\#{character}" }
        escaped = "\\#{escaped}" if escaped.start_with?("@", "?")
        escaped.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      private def place_runtime(tree, project)
        root = File.join(project, ROOT)
        FileUtils.mkdir_p([root, File.join(project, "libs")])
        %w[lib libexec].each { |folder| FileUtils.mv(File.join(tree, folder), root) }
        FileUtils.mv(File.join(tree, AAR), File.join(project, "libs"))
      end

      private def ruby_root(project)
        File.join(project, ROOT)
      end

      private def place_icons(project)
        icon = @app.identity.icon or return

        Icon::ANDROID.each do |density, size|
          folder = File.join(project, "src", "main", "res", "mipmap-#{density}")
          FileUtils.mkdir_p(folder)
          FileUtils.cp(icon.png(size, "android"), File.join(folder, "ic_launcher.png"))
        end
      end

      # Nothing: the project is Gradle's to build.
      private def finish(_project)
        nil
      end
    end
  end
end
