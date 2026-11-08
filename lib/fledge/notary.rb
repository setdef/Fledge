# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "open3"
require "tmpdir"
require_relative "command"
require_relative "error"
require_relative "mac_bundle"

module Fledge
  # Has Apple's notary service notarize a signed macOS app, through
  # notarytool, and staples the ticket it issues, through stapler.
  #
  # Gatekeeper opens an app downloaded from the internet without a
  # warning only when Apple has notarized it: checked its Developer ID
  # signature, its hardened runtime, and its timestamps, and issued a
  # ticket for it. A ticket stapled to the disk image or the bundle lets
  # Gatekeeper find it with no network. Signing with
  # <tt>fledge build --sign</tt> (Fledge::MacSigning) makes what the notary
  # service asks for; this class sends it and staples what comes back
  # (ADR 033).
  #
  # It runs <tt>xcrun notarytool submit FILE --keychain-profile PROFILE
  # --wait --output-format json</tt>, as Apple's "Customizing the
  # notarization workflow" and @electron/notarize do, with the credentials
  # the developer stored once in their keychain with <tt>xcrun notarytool
  # store-credentials PROFILE</tt>: Fledge never sees an Apple ID, a
  # password, or an App Store Connect key, and passes none on a command
  # line. When Apple does not accept the file, it fetches the
  # submission's log with <tt>notarytool log</tt> and fails the build with
  # each issue the log names. Then it runs <tt>xcrun stapler staple</tt>
  # and <tt>xcrun stapler validate</tt> on each file a ticket can be
  # stapled to: a disk image and a bundle, but not a zip archive or a lone
  # program, which Apple says cannot hold one.
  #
  # Use it through Fledge::MacSigning, which <tt>fledge build --sign
  # IDENTITY --notarize PROFILE</tt> gives one.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   notary = Fledge::Notary.new("fledge-notary", log: $stderr)
  #   notary.notarize("dist/Hello Window-arm64-darwin", bundle: "dist/Hello Window-arm64-darwin/Hello Window.app",
  #     image: "dist/Hello Window-arm64-darwin.dmg")
  #   notary.notarize("dist/Hello-arm64-darwin")
  #--
  # SPDX-SnippetEnd
  #++
  class Notary
    # Where notarytool and stapler come from.
    INSTALL = "They come with Xcode, and with its Command Line Tools (xcode-select --install)."

    # The exit status of notarytool when the keychain holds no profile of
    # the name it was given, EX_UNAVAILABLE in <sysexits.h>.
    NO_PROFILE = 69

    # The statuses notarytool's --wait ends on (notarytool(1), "wait"),
    # of which only Accepted means notarized.
    ACCEPTED = "Accepted"

    # The name of the keychain profile notarytool reads its credentials
    # from, as <tt>xcrun notarytool store-credentials</tt> saved it.
    attr_reader :profile

    # Creates the notary for the keychain profile +profile+, which says
    # what it is doing on +log+, such as standard error, or nowhere when
    # +log+ is +nil+.
    def initialize(profile, log: nil)
      @profile = profile
      @log = log
    end

    # Notarizes the app built in +folder+ and staples its tickets, after
    # it has been signed: the disk image +image+ when there is one, which
    # holds the bundle +bundle+, as Apple asks of nested containers
    # (notarize the outermost only); else the bundle, or else the whole
    # folder of a console app, each in a zip archive, as ditto makes one
    # for the notary service. Staples +image+ and +bundle+, since the
    # service issues a ticket for each file nested in what it notarizes,
    # and staples nothing to a console app, whose programs cannot hold a
    # ticket; Gatekeeper finds theirs online. Raises Fledge::Error when
    # Apple does not accept the app, or a tool fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Notary.new("fledge-notary").notarize("dist/Hello-arm64-darwin")
    #--
    # SPDX-SnippetEnd
    #++
    def notarize(folder, bundle: nil, image: nil)
      image ? submit(image) : submit_zip(bundle || folder)
      [image, bundle].compact.each { |path| staple(path) }
    end

    # Sends the file at +path+, a disk image or a zip archive, to Apple's
    # notary service and waits for its answer, and returns the
    # submission's ID when Apple accepted it. Raises Fledge::Error with
    # the issues the submission's log names when Apple did not, and with
    # notarytool's own words when it could not ask, saying how to store a
    # profile when the keychain has none of that name.
    def submit(path)
      name = File.basename(path)
      @log&.puts "Notarizing #{name} with Apple's notary service, with the keychain profile #{@profile}; this takes minutes"
      output, error, status = notarytool("submit", path, "--keychain-profile", @profile, "--wait", "--output-format", "json")
      result = submission(output)
      raise Error, failure(name, error.empty? ? output : error, status) unless result

      id = result["id"].to_s
      return accepted(name, id) if result["status"] == ACCEPTED

      raise Error, rejected(name, id, result)
    end

    # Puts the ticket Apple issued for the disk image or bundle at +path+
    # on it, and checks it there, with stapler, run from the folder that
    # holds it as @electron/notarize and Tauri run it.
    def staple(path)
      name = File.basename(path)
      @log&.puts "Stapling Apple's ticket to #{name}"
      %w[staple validate].each { |action| Command.run("xcrun", "stapler", action, name, install: INSTALL, chdir: File.dirname(path)) }
    end

    # Submits the bundle or folder at +path+ in a zip archive, which the
    # notary service takes as it does not take a folder, made with ditto
    # as Apple's "Customizing the notarization workflow" makes one, with
    # --sequesterRsrc, as Briefcase, Tauri, and @electron/notarize add, so
    # that extended attributes travel in the archive's own __MACOSX folder
    # and not as files inside the bundle.
    private def submit_zip(path)
      Dir.mktmpdir("fledge-notary") do |work|
        zip = File.join(work, "#{File.basename(path)}.zip")
        Command.run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", path, zip, install: MacBundle::INSTALL)
        submit(zip)
      end
    end

    # Runs <tt>xcrun notarytool</tt> with +arguments+, and returns its
    # standard output, its standard error, and its status.
    private def notarytool(*)
      Open3.capture3("xcrun", "notarytool", *)
    rescue SystemCallError => e
      raise Error, "fledge build --notarize needs xcrun, which it could not run (#{e.message}). #{INSTALL}"
    end

    # The submission notarytool's JSON +output+ describes, or +nil+ when
    # it describes none, as when notarytool could not reach Apple.
    private def submission(output)
      result = JSON.parse(output) # : Hash[String, String] | Array[String] | String | nil
      result if result.is_a?(Hash) && result["id"]
    rescue JSON::ParserError
      nil
    end

    # Logs that Apple accepted the submission +id+ of +name+, and returns
    # +id+.
    private def accepted(name, id)
      @log&.puts "Apple accepted #{name} (submission #{id})"
      id
    end

    # What to say when notarytool could not submit +name+, with its own
    # words, +said+, and its exit +status+.
    private def failure(name, said, status)
      words = said.dup.force_encoding(Encoding::UTF_8).scrub.strip
      hint = if status.exitstatus == NO_PROFILE
        "\nStore your credentials under that name once, with xcrun notarytool store-credentials #{@profile} " \
          "(doc/desktop_apps.md, \"Sign your app\")."
      end
      "notarytool could not notarize #{name} (#{status}):\n#{words}#{hint}"
    end

    # What to say when Apple's notary service did not accept the
    # submission +id+ of +name+, whose answer is +result+: the issues its
    # log names, which notarytool fetches.
    private def rejected(name, id, result)
      status = result["status"] || "no answer"
      lines = ["Apple did not notarize #{name}: #{status} (submission #{id}).", *issues(id)]
      lines << "Read the whole log with: xcrun notarytool log #{id} --keychain-profile #{@profile}"
      lines.join("\n")
    end

    # Each issue the log of the submission +id+ names, one per line, or
    # what the log says in their place.
    private def issues(id)
      output, _error, status = notarytool("log", id, "--keychain-profile", @profile)
      return [] unless status.success?

      log = JSON.parse(output) # : Hash[String, String | Array[Hash[String, String]]]
      summary = log["statusSummary"]
      found = log["issues"]
      lines = found.is_a?(Array) ? found.map { |issue| issue_line(issue) } : [] # : Array[String]
      summary.is_a?(String) ? [summary, *lines] : lines
    rescue JSON::ParserError
      []
    end

    # One issue of a submission's log, as Apple's log describes it: its
    # severity, the path of the file, what is wrong, and where Apple's
    # documentation says more.
    private def issue_line(issue)
      ["  #{issue['severity']}: #{issue['path']}: #{issue['message']}", issue["docUrl"]].compact.join(" ")
    end
  end
end
