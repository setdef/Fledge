# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "tmpdir"

# A stand-in for Apple's notary service, at the seam Fledge::Notary
# crosses: an +xcrun+ placed first on +PATH+, which answers
# <tt>notarytool submit</tt>, <tt>notarytool log</tt>, and
# <tt>stapler staple</tt> and <tt>validate</tt> as Apple documents them,
# and records every call, so a test proves what Fledge asks of Apple, in
# which order, without an Apple Developer account (ADR 033, section 6).
#
# Its answers are Apple's own examples: the submission ID, and the log of
# an Invalid submission, from "Customizing the notarization workflow";
# the message notarytool 1.1.4 prints, with exit status 69, for a profile
# the keychain does not hold, as it printed it on macOS 27.0; and
# notarytool's JSON for a submission it waited for, with the keys
# @electron/notarize and Tauri read (id, status, message). +ANSWER+ picks
# one: accepted, invalid, offline, or missing. Any other xcrun tool (the
# real codesign is found without it) runs as it would.
#
# Each call is a line of LOG: the tool, its arguments separated by tabs,
# and, for stapler, the folder it ran in. Each file submitted is copied
# into SUBMITTED, so a test can read what Apple would have received, and
# stapler writes what it would have stapled: to a bundle,
# <tt>Contents/CodeResources</tt>, where stapler puts a bundle's ticket,
# and to a disk image, bytes on its end, so that what is archived after
# stapling shows it.
module StandInNotary
  # Apple's example submission ID.
  ID = "2efe2717-52ef-43a5-96dc-0797e4ca1041"

  # What the stand-in staples, so that a test can find it.
  TICKET = "stand-in notarization ticket"

  XCRUN = <<~'SH'
    #!/bin/sh
    tool=$1
    shift
    case "$tool" in
      notarytool|stapler) ;;
      *) exec /usr/bin/xcrun "$tool" "$@" ;;
    esac
    line="$tool"
    for argument; do line="$line	$argument"; done
    [ "$tool" = stapler ] && line="$line	(in $(pwd))"
    printf '%s\n' "$line" >> "$LOG"
    case "$tool $1" in
      "notarytool submit")
        cp -R "$2" "$SUBMITTED/"
        case "$ANSWER" in
          accepted) printf '{"id":"%s","message":"Processing complete","status":"Accepted"}\n' "$ID" ;;
          invalid) printf '{"id":"%s","message":"Processing complete","status":"Invalid"}\n' "$ID"; exit 1 ;;
          offline) echo "Error: The Internet connection appears to be offline." >&2; exit 1 ;;
          missing)
            echo "Error: No Keychain password item found for profile: $4" >&2
            echo >&2
            echo "Run 'notarytool store-credentials' to create another credential profile." >&2
            exit 69 ;;
        esac ;;
      "notarytool log")
        cat <<JSON
    {
        "archiveFilename": "Hello Window-arm64-darwin.dmg",
        "issues": [
            {
                "message": "The signature of the binary is invalid.",
                "path": "Hello Window-arm64-darwin.dmg/Hello Window.app/Contents/MacOS/Hello Window",
                "severity": "error",
                "docUrl": "https://developer.apple.com/documentation/security/resolving-common-notarization-issues"
            }
        ],
        "jobId": "$ID",
        "logFormatVersion": 1,
        "status": "Invalid",
        "statusSummary": "Archive contains critical validation errors",
        "ticketContents": null,
        "uploadDate": "2021-04-19T16:56:17Z"
    }
    JSON
        ;;
      "stapler staple")
        if [ -d "$2" ]; then printf '%s\n' "$TICKET" > "$2/Contents/CodeResources"
        else printf '%s\n' "$TICKET" >> "$2"
        fi ;;
    esac
  SH

  # Puts the stand-in first on +PATH+, answering +answer+, for the block,
  # and yields a reader of its calls, each an array of the tool and its
  # arguments, and the folder of what was submitted.
  def self.with(answer = "accepted")
    Dir.mktmpdir("fledge-notary-stand-in") do |root|
      bin = File.join(root, "bin")
      submitted = File.join(root, "submitted")
      FileUtils.mkdir_p([bin, submitted])
      File.write(File.join(bin, "xcrun"), XCRUN)
      File.chmod(0o755, File.join(bin, "xcrun"))
      log = File.join(root, "calls")
      saved = ENV.to_h.slice("PATH", "LOG", "SUBMITTED", "ANSWER", "ID", "TICKET")
      ENV.update("PATH" => "#{bin}:#{ENV.fetch('PATH')}", "LOG" => log, "SUBMITTED" => submitted, "ANSWER" => answer, "ID" => ID,
        "TICKET" => TICKET)
      begin
        yield -> { File.file?(log) ? File.readlines(log, chomp: true).map { |line| line.split("\t") } : [] }, submitted
      ensure
        %w[PATH LOG SUBMITTED ANSWER ID TICKET].each { |key| ENV[key] = saved[key] }
      end
    end
  end
end
