# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../error"
require_relative "android_libraries"
require_relative "android_linkage"
require_relative "android_packaging"
require_relative "../platform"
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
    # <tt>FledgeRuby.aar</tt> is in <tt>libs/</tt>; its <tt>lib/</tt>,
    # <tt>libexec/</tt>, and Ruby's headers in <tt>include/</tt>, which
    # mkmf looks for as on a desktop, are in ROOT, which the build stores as the asset
    # <tt>fledge.zip</tt> that <tt>org.setdef.fledge.FledgeRuby</tt>
    # unpacks (doc/contributors/design/phone-runtimes.md, "The Java class"). The
    # app's identifier is its <tt>applicationId</tt>, its name its
    # label, its version its
    # <tt>versionName</tt> and, as a number, its <tt>versionCode</tt>
    # (#version_code); and when <tt>fledge.yml</tt> names an icon,
    # <tt>ICON-48.png</tt> to <tt>ICON-192.png</tt> are its launcher icon
    # in each density's <tt>mipmap-</tt> folder.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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

      # The name of the library that holds the app's gems' extensions
      # that are linked in and their registration, <tt>libfledgeext.so</tt>
      # (doc/contributors/design/phone-projects.md, "Linking extensions
      # on Android").
      EXTENSIONS = "fledgeext"

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
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
        %w[
          settings.gradle
          build.gradle
          src/main/AndroidManifest.xml
          src/main/res/values/strings.xml
          src/main/java/org/setdef/fledge/host/MainActivity.java
]
      end

      # The values for the templates' marks, each written as the file that
      # holds it reads it: Groovy's single-quoted strings in the Gradle
      # files, and an Android string resource in XML for the name.
      # LOAD_EXTENSIONS is empty: the runtime loads the extensions'
      # library itself, and the mark stays for a host's copy that holds it.
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
          "LOAD_EXTENSIONS" => "",
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
        %w[lib libexec bin].each { |folder| FileUtils.mv(File.join(tree, folder), root) if File.directory?(File.join(tree, folder)) }
        FileUtils.mkdir_p(File.join(root, "include"))
        Dir.glob(File.join(tree, "include", "ruby-*")).each { |headers| FileUtils.mv(headers, File.join(root, "include")) }
        FileUtils.mv(File.join(tree, AAR), File.join(project, "libs"))
      end

      # Where ROOT keeps RubyGems' wrapper of each gem's command, which
      # the app's Ruby reads in place of <tt>bin/NAME</tt>
      # (runtime/mobile/android.c, FLEDGE_COMMANDS).
      COMMANDS = "libexec/commands"

      # The runtime's ruby program, as the package installer extracts it
      # into the app's native library folder.
      PROGRAM = "libfledgerubyexe.so"

      # Moves each gem's command in ROOT's <tt>bin/</tt>, the runtime's
      # and the app's gems', RubyGems' wrapper as a desktop has it, into
      # COMMANDS, and adds the lines of AndroidLibraries::LINKS that make
      # <tt>bin/NAME</tt> a link to PROGRAM for each ABI as the app
      # starts. Android lets an app run only what its package installer
      # extracts, its native libraries, so the wrapper in the app's files
      # can be read but not run; the program run as NAME runs Ruby on
      # the wrapper, and Ruby reads the wrapper wherever it reads
      # <tt>bin/NAME</tt> (doc/contributors/design/phone-runtimes.md,
      # "Gem commands on Android").
      private def place_commands(root)
        bin = File.join(root, "bin")
        return unless File.directory?(bin)

        names = Dir.children(bin).sort
        FileUtils.mkdir_p(File.join(root, COMMANDS))
        names.each { |name| FileUtils.mv(File.join(bin, name), File.join(root, COMMANDS, name)) }
        FileUtils.rmdir(bin)
        lines = MobileExtensions::Targets::ANDROID_ABIS.values.sort.flat_map { |abi| names.map { |name| "#{abi}\t#{PROGRAM}\tbin/#{name}\n" } }
        File.write(File.join(root, AndroidLibraries::LINKS), lines.join, mode: "a")
      end

      # Links the extensions not built as files into a shared library for
      # each ABI, <tt>libfledgeext.so</tt>, against the runtime's
      # <tt>libfledgeruby.so</tt>, in <tt>src/main/jniLibs/</tt>, where
      # Gradle's plugin packs it into the APK aligned for 16 KB pages, and
      # which the runtime opens before Ruby boots, with the shared
      # libraries the extensions link from their own folders. It is
      # linked whenever the app has a compiled extension, with nothing in
      # it but a registration of none when every one is a file, since a
      # framework's host may load it by name
      # (doc/contributors/design/phone-projects.md, "Linking extensions
      # on Android"). The registration unit is kept in
      # <tt>extensions/</tt> for whoever reads the project.
      #
      # An extension built as a file (MobileExtensions::Library) and a
      # library a Rakefile built for Ruby's ffi
      # (MobileExtensions::FfiLibrary) each go to <tt>jniLibs/</tt> on
      # their own, linked from where a desktop has the file as the app
      # starts (AndroidLibraries). Once all of them and
      # <tt>libfledgeext.so</tt> are in place, the NDK's shared C++
      # runtime goes beside them where one of them needs it, as every one
      # with C++ does (AndroidLibraries#carry_cxx_runtime).
      private def place_extensions(project)
        built = @built or return
        compiler = @extensions or return
        libraries = AndroidLibraries.new(built)
        libraries.call(project, ruby_root: ruby_root(project))
        @judged = libraries.judged
        source = File.join(project, "extensions", "fledge_extensions.c")
        FileUtils.mkdir_p(File.dirname(source))
        File.write(source, MobileExtensions.registration_source(built.registrations))
        built.targets.each_value do |build|
          into = File.join(project, "src", "main", "jniLibs", build.target.abi.to_s, "lib#{EXTENSIONS}.so")
          compiler.shared_library(built, build, registration: source, into:)
          abi = build.target.abi.to_s
          [into, *MobileExtensions::Linking.carry_shared_libraries(build.flags, into: File.dirname(into))].each do |path|
            @judged << [abi, File.basename(path), "the app", "lib/#{abi}/#{File.basename(path)}"]
          end
        end
        libraries.carry_cxx_runtime(project, ruby_root: ruby_root(project))
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

      # Refuses the project when a native library Fledge put in it needs
      # one that neither Android, nor the runtime, nor the app carries
      # (AndroidLinkage), or when its <tt>build.gradle</tt> keeps the
      # extensions built as files from being extracted (AndroidPackaging),
      # read once the host's files are in place, since a host may carry a
      # library, or its own <tt>build.gradle</tt>, too. The rest is
      # Gradle's to build.
      private def finish(project)
        judged = @judged or return

        found = [*packaging_problem(project), *AndroidLinkage.new(readers:).problems(project, judged)]
        raise Error, "#{@app.name} can't ship for android:\n#{found.map { |problem| "  #{problem}" }.join("\n")}" unless found.empty?
      end

      # The refusal AndroidPackaging gives the project's
      # <tt>build.gradle</tt>, named as the host's file where the host
      # replaced Fledge's, after saying its warning, if any.
      private def packaging_problem(project)
        libraries = (@built&.targets || {}).values.flat_map(&:libraries)
        extensions = libraries.map { |library| [library.gem, library.feature] } # : Array[[String, String]]
        packaging = AndroidPackaging.new(extensions.uniq)
        text = File.read(File.join(project, "build.gradle"))
        host = @app.config.android&.host
        shown = (host && File.file?(File.join(@app.root, host, "build.gradle"))) ? "#{host}/build.gradle" : "build.gradle"
        warning = packaging.warning(text, shown:)
        @log&.puts warning if warning
        packaging.refusal(text, shown:)
      end

      # The tools that read the app's libraries: the NDK's, or, for a
      # build with no NDK, as in a test, this computer's own.
      private def readers
        ndk = @built&.ndk
        ndk ? Binary::Readers.llvm(ndk.bin) : Binary::Readers.local(Platform.local.os)
      end
    end
  end
end
