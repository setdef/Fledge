# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # The NOTICES file a runtime ships, written from the audit's Report:
  # every component, its license, how it ships and where its source is;
  # for each LGPL library, what its recipient may do and where its exact
  # source is; then the full text of every license.
  #
  # A license text comes from the component's folder in runtime/notices/,
  # from the license files a bundled gem ships in its own folder, or, for
  # a default gem, from Ruby's own COPYING and LEGAL. #missing lists the
  # components whose text none of these holds.
  class Notices
    NOTICES = File.join(ROOT, "runtime", "notices")
    RELEASES = "https://github.com/setdef/Fledge/releases/download"
    LICENSE_FILE = /\A(?:LICEN[CS]E|COPYING|BSDL|MIT-LICENSE|PSFL|LEGAL|license_of_)/i
    RUBY_LICENSES = ["Ruby", "Ruby OR BSD-2-Clause", "BSD-2-Clause OR Ruby"].freeze

    attr_reader :missing

    def initialize(report, version:, map:)
      @report = report
      @version = version
      @map = map
      @missing = []
      @legal = File.read(File.join(NOTICES, "ruby", "LEGAL"))
    end

    def text
      present = @report.present.sort_by { |component| [component.first_party ? 0 : 1, component.gem_dir ? 1 : 0, component.name.downcase] }
      [
        header,
        "COMPONENTS",
        "",
        *present.map { |component| entry(component) },
        *lgpl(present),
        "LICENSE TEXTS",
        "",
        *texts(present),
      ].join("\n")
    end

    # The file name of the LGPL source bundle for +platform+ at +version+,
    # a release asset beside the runtime.
    def self.source_bundle(version, platform)
      "fledge-runtime-#{version}-#{platform}-lgpl-sources.tar.gz"
    end

    private def header
      <<~HEADER
        Third-party software in this app

        This app was built with Fledge (https://github.com/setdef/Fledge), which
        copied a Ruby runtime into it. The runtime is the work of the people
        below, under the licenses named. The full text of each license is at
        the end of this file. notices/sbom.spdx.json lists every file.

      HEADER
    end

    private def entry(component)
      text_at = license_text(component)
      @missing << component.id unless text_at
      <<~ENTRY
        #{component.name}
          Version: #{component.version}
          License: #{component.license}
          Ships as: #{component.ships}
          Source: #{component.download}
          License text: #{text_at || 'MISSING'}
      ENTRY
    end

    private def license_text(component)
      return "notices/#{component.notice}/ (below)" if component.notice
      return gem_text(component) if component.gem_dir
      return "none required (#{component.license})" if component.license.include?(" WITH ")

      nil
    end

    private def gem_text(component)
      files = gem_license_files(component)
      return files.join(", ") unless files.empty?

      name = component.name[/\A\S+/].to_s
      override = @map.fetch("gems", {}).fetch(name, {})
      return "notices/#{override['notice']}/ (below)" if override["notice"]
      return "#{component.gem_dir}/#{override['text']}" if override["text"]
      return "Ruby's COPYING, in notices/ruby/ (below)" if RUBY_LICENSES.include?(component.license)
      return "Ruby's LEGAL, in notices/ruby/ (below)" if @legal.match?(%r{^\[(?:lib|ext)/#{Regexp.escape(name)}(?:\.rb)?\]})

      nil
    end

    private def gem_license_files(component)
      directory = File.join(@report.tree, component.gem_dir)
      return [] unless File.directory?(directory)

      Dir.children(directory).grep(LICENSE_FILE).sort.map { |file| "#{component.gem_dir}/#{file}" }
    end

    private def lgpl(present)
      libraries = present.select { |component| component.kind == "shared_library" && component.license.include?("LGPL") }
      return [] if libraries.empty?

      bundle = "#{RELEASES}/v#{@version}/#{Notices.source_bundle(@version, @report.platform)}"
      [
        "LIBRARIES UNDER THE GNU LESSER GENERAL PUBLIC LICENSE",
        "",
        *libraries.map { |library| lgpl_entry(library, bundle) },
      ]
    end

    private def lgpl_entry(library, bundle)
      files = @report.owned(library).map { |path| "  #{path}" }.join("\n")
      <<~LGPL
        #{library.name}, version #{library.version}, is licensed under
        #{library.license}.
        It is not part of this app's own code: it ships as its own shared
        library, which the app loads when it starts:

        #{files}

        You may replace that file with another build of the library, including
        one you modified, as long as it keeps the same interface, and the app
        will use it. The library's complete corresponding source code, and
        how this copy was built from it, are at

          #{bundle}

        and its authors publish it at #{library.download}.

      LGPL
    end

    private def texts(present)
      folders = present.filter_map(&:notice).uniq.sort
      gem_folders = present.filter_map { |component| component.gem_dir && @map.fetch("gems", {}).dig(component.name[/\A\S+/], "notice") }
      (folders + gem_folders).uniq.flat_map do |folder|
        notice_files(folder).map { |path| "=== notices/#{folder}/#{File.basename(path)}\n\n#{File.read(path).strip}\n" }
      end
    end

    private def notice_files(folder)
      return [File.join(ROOT, "LICENSES", "AGPL-3.0-or-later.txt")] if folder == "fledge"

      Dir.glob(File.join(NOTICES, folder, "*"))
    end
  end
end
