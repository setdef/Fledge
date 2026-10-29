# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"
require_relative "archive"
require_relative "assembly"
require_relative "entry"
require_relative "error"
require_relative "mobile_platform"

module Fledge
  # Puts one app into a phone's runtime: an Xcode project or a Gradle
  # project that builds the app for iPhones and iPads, or for Android.
  #
  # A phone runs no launcher of Fledge's: Ruby is a library linked into an
  # app that Xcode or Gradle builds and the developer signs (ADR 011). So a
  # phone's build is not an app but the project that builds one, as
  # Briefcase's <tt>create iOS</tt> and <tt>create android</tt>, Flutter's
  # and React Native's templates, and Tauri's <tt>ios init</tt> and
  # <tt>android init</tt> write one, around the runtime's XCFramework or
  # AAR (ADR 012). The app inside it is what the desktop's built app holds
  # beside its launcher, in a folder named ROOT: Assembly::CONFIG, the
  # project in +app+, and the app's gems in Ruby's gem folder, which the
  # build puts beside the runtime's Ruby and the embedding API's
  # <tt>fledge_ruby_run_app</tt> runs as the launcher would.
  #
  # This class does what both projects share: it unpacks the runtime with
  # tar, copies the project's template (<tt>lib/fledge/templates/</tt>),
  # fills in the app's identity where the template marks it
  # (<tt>@@NAME@@</tt>), and writes ROOT, with the runtime's notices, so
  # the app carries them. Fledge::MobileProject::IOS and
  # Fledge::MobileProject::Android place the runtime and the icons as each
  # system's tools expect, and IOS has XcodeGen write the Xcode project.
  # It writes <tt>OUT/NAME-ios/</tt> or <tt>OUT/NAME-android/</tt>,
  # replacing an earlier one, refuses to let an added file replace one of
  # the runtime's, and removes what it wrote if the build fails.
  #
  # Use it once in <tt>fledge build ios</tt> or <tt>fledge build
  # android</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   platform = Fledge::MobilePlatform.find("android")
  #   Fledge::MobileProject.for(platform).new(
  #     app: Fledge::App.at("examples/hello"),
  #     runtime: Fledge::Runtimes.new.archive(platform),
  #     out: File.expand_path("dist")
  #   ).call
  #   # => "/path/to/dist/Hello-android"
  #--
  # SPDX-SnippetEnd
  #++
  class MobileProject
    # Where the projects' templates are, a folder for each system.
    TEMPLATES = File.join(File.dirname(__FILE__), "templates")

    # The project's folder that becomes the app's Ruby root on the phone,
    # with Ruby's library beside it.
    ROOT = "fledge"

    # A mark in a template's file for a value of the app's.
    TOKEN = /@@([A-Z_]+)@@/

    # The writer of +platform+'s project: IOS or Android.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileProject.for(Fledge::MobilePlatform.find("ios")) # => Fledge::MobileProject::IOS
    #--
    # SPDX-SnippetEnd
    #++
    def self.for(platform)
      (platform.name == "ios") ? IOS : Android
    end

    # Creates the writer.
    #
    # [app] The Fledge::App to ship.
    # [runtime] The path of the phone's runtime archive.
    # [out] The folder builds go to, as an absolute path.
    # [app_files] Contents for files in the app's folder, by path relative
    #             to it, in place of the project's own file at that path or
    #             beside the rest.
    # [files] More entries for ROOT, such as the app's gems, with paths
    #         relative to it, which may not replace anything the runtime
    #         holds.
    def initialize(app:, runtime:, out:, app_files: {}, files: [])
      @app = app
      @runtime = runtime
      @out = out
      @app_files = app_files
      @files = files
    end

    # The project's folder name: <tt>NAME-ios</tt> or <tt>NAME-android</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   project.base_name # => "Hello-ios"
    #--
    # SPDX-SnippetEnd
    #++
    def base_name
      "#{@app.name}-#{system}"
    end

    # Writes the project and returns its folder. Raises Fledge::Error when
    # the app has no identifier, or one the system cannot take, an icon
    # file is missing, the runtime is not the phone's, an added file would
    # replace one of the runtime's, or a tool fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   project.call # => "/path/to/dist/Hello-ios"
    #--
    # SPDX-SnippetEnd
    #++
    def call
      identifier
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(@out)
      Dir.mktmpdir(".fledge-build-", @out) do |work|
        project = File.join(work, base_name)
        build(runtime_tree(work), project)
        FileUtils.mv(project, folder)
      end
      folder
    rescue
      FileUtils.rm_rf(folder)
      raise
    end

    private def build(tree, project)
      FileUtils.cp_r(File.join(TEMPLATES, system), project, preserve: true)
      place_runtime(tree, project)
      root = File.join(project, ROOT)
      FileUtils.mkdir_p(root)
      File.write(File.join(root, Assembly::CONFIG), Assembly.launch_config(@app))
      FileUtils.cp_r(File.join(tree, "notices"), root)
      [*Assembly.app_entries(@app, @app_files, skip: [@out]), *@files].each { |entry| add(project, root, entry) }
      template_files.each { |path| fill(File.join(project, path)) }
      place_icons(project)
      finish(project)
    end

    # The runtime archive, unpacked into +work+: its one top folder.
    private def runtime_tree(work)
      into = File.join(work, "runtime")
      Archive.unpack(@runtime, into:)
      Dir.glob(File.join(into, "*")).first || raise(Error, "#{@runtime} holds no runtime")
    end

    # Writes +entry+ under ROOT, refusing one that would replace a file of
    # ROOT's or of the runtime's Ruby in +project+ (#ruby_root), which the
    # app's Ruby is ROOT merged into; a folder may be one of theirs.
    private def add(project, root, entry)
      taken = [File.join(root, entry.path), File.join(ruby_root(project), entry.path)].any? do |path|
        File.symlink?(path) || (File.exist?(path) && !(entry.type == :directory && File.directory?(path)))
      end
      raise Error, "#{entry.path} is in #{@runtime} already, so the build can't add its own" if taken

      entry.write_into(root)
    end

    # Replaces each TOKEN in the file at +path+ with the app's value
    # (#tokens). Raises KeyError for a token the template has and
    # the writer does not fill.
    private def fill(path)
      values = tokens
      text = File.read(path)
      File.write(path, text.gsub(TOKEN) { values.fetch(::Regexp.last_match(1).to_s) })
    end

    # The app's identifier, which each phone requires. Raises Fledge::Error
    # when fledge.yml gives none.
    private def identifier
      @app.identity.identifier || raise(Error, "#{File.join(@app.root, Config::FILE)}: #{platform_title} needs an identifier, " \
        "the reverse-DNS name the system and its store know the app by, such as identifier: " \
        "com.example.#{@app.name.gsub(/[^A-Za-z0-9]/, '')}")
    end

    # What each system's writer says: its name, as MobilePlatform names
    # it; the files of its template with marks (TOKEN) in them; the values
    # of the marks; where the runtime's library and Ruby go in the
    # project, and where that Ruby is once there; where the app's icon
    # goes; and what finishes the project.
    private def system
      raise(NotImplementedError, "#{self.class} names no system")
    end

    private def template_files
      raise(NotImplementedError, "#{self.class} names no template files")
    end

    private def tokens
      raise(NotImplementedError, "#{self.class} fills no marks")
    end

    private def place_runtime(_tree, _project)
      raise(NotImplementedError, "#{self.class} places no runtime")
    end

    private def ruby_root(_project)
      raise(NotImplementedError, "#{self.class} has no Ruby")
    end

    private def place_icons(_project)
      raise(NotImplementedError, "#{self.class} places no icons")
    end

    private def finish(_project)
      raise(NotImplementedError, "#{self.class} finishes nothing")
    end

    private def platform_title
      (system == "ios") ? "an iOS app" : "an Android app"
    end

    private def folder
      File.join(@out, base_name)
    end
  end
end

require_relative "mobile_project/ios"
require_relative "mobile_project/android"
