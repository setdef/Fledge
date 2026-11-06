# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"
require_relative "version"
require_relative "windows_resources"

module Fledge
  # The notice a Windows app carries, in <tt>notices/MODIFIED.txt</tt>,
  # of the programs <tt>fledge build</tt> changed.
  #
  # Each of an app's programs is a copy of Fledge's launcher, which is
  # under the GNU Affero General Public License, version 3 or later. On
  # Windows the build has rcedit write the app's version information and
  # icon into the copy (Fledge::WindowsResources), which makes it a
  # modified version of the launcher; section 5(a) asks that a modified
  # work "carry prominent notices stating that you modified it, and giving
  # a relevant date", and section 6 that its object code come with its
  # Corresponding Source, "including scripts to control those activities".
  # This notice names each program, everything rcedit wrote into it, the
  # date of the build, and where the launcher's source and the steps that
  # changed it are (ADR 004, section 10).
  #
  # Elsewhere a program is the launcher copied and renamed, with nothing
  # written into it, so it is no modification and has no notice.
  #
  # Use it through Fledge::Assembly.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   notice = Fledge::ModificationNotice.new(programs: { "Hello.exe" => identity }, date: Fledge::ModificationNotice.date(ENV))
  #   notice.text("dist/Hello-x64-mingw-ucrt/app").lines.first # => "Programs fledge build changed\n"
  #--
  # SPDX-SnippetEnd
  #++
  class ModificationNotice < Data.define(:programs, :date)
    ##
    # :attr_reader: programs
    # The Fledge::Identity each changed program was given, by the
    # program's file name, such as <tt>Hello.exe</tt>.

    ##
    # :attr_reader: date
    # The Time of the build that changed them.

    # Where the notice is, relative to the app's folder: beside
    # NOTICES.txt, which names it.
    PATH = "notices/MODIFIED.txt"

    # Where the source of Fledge's own files is, at a version's tag.
    SOURCE = "https://github.com/setdef/Fledge/tree/v"

    # The time of the build: SOURCE_DATE_EPOCH, as reproducible-builds.org
    # specifies it, when +env+ sets it, and as the runtime's SBOM takes it,
    # or else now. Raises Fledge::Error when it is not a whole number of
    # seconds, as the specification asks.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::ModificationNotice.date({ "SOURCE_DATE_EPOCH" => "0" }) # => 1970-01-01 00:00:00 UTC
    #--
    # SPDX-SnippetEnd
    #++
    def self.date(env)
      epoch = env["SOURCE_DATE_EPOCH"]
      return Time.now.utc unless epoch
      raise Error, "SOURCE_DATE_EPOCH is #{epoch.inspect}, which is not a count of seconds since 1970" unless epoch.match?(/\A\d+\z/)

      Time.at(Integer(epoch, 10)).utc
    end

    # The notice's text, for an app whose project is in the folder +app+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   notice.text("dist/Hello-x64-mingw-ucrt/app").lines.last
    #   # => "  https://github.com/setdef/Fledge/tree/v0.6.0\n"
    #--
    # SPDX-SnippetEnd
    #++
    def text(app)
      <<~TEXT
        Programs fledge build changed

        Each program below is a copy of Fledge's launcher, which is under the
        GNU Affero General Public License, version 3 or later (its text is in
        NOTICES.txt, beside this file), that Fledge #{VERSION}'s fledge build
        changed on #{date.utc.strftime('%Y-%m-%d')}: it renamed the copy for this app, and had rcedit
        write this version information and icon into the copy's resources,
        from the app's fledge.yml. Nothing else in them was changed.

        #{programs.map { |file_name, identity| program(file_name, identity, app) }.join("\n")}
        Their source is Fledge's, at the tag of the version that built this app,
        where runtime/launcher/ holds the launcher's C, and
        lib/fledge/windows_resources.rb the steps that wrote these resources,
        with rcedit, from what is listed above:

          #{SOURCE}#{VERSION}
      TEXT
    end

    # What rcedit wrote into the program +file_name+, whose identity is
    # +identity+, as WindowsResources.apply writes it.
    private def program(file_name, identity, app)
      strings = WindowsResources.strings(identity, file_name).sort.map { |key, value| "    #{key}: #{value}" }
      ["  #{file_name}", "    FileVersion and ProductVersion: #{identity.version}", *strings, "    Icon: #{icon(identity, app)}", ""].join("\n")
    end

    # The icon of +identity+, and where it is, when the app's project
    # folder +app+ holds it.
    private def icon(identity, app)
      icon = identity.icon
      return "none" unless icon

      name = "#{icon.name}.ico"
      root = File.expand_path(app)
      held = File.expand_path(name, root)
      return "#{name}, which this app holds as app/#{held.delete_prefix("#{root}/")}" if held.start_with?("#{root}/") && File.file?(held)

      "#{name}, from the project that built this app, which this app does not hold"
    end
  end
end
