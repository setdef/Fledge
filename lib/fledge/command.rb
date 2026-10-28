# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require_relative "error"

module Fledge
  # Runs one of the tools a build hands its work to.
  #
  # Each platform's app is made with that platform's own tools (ADR 010):
  # tar packs and unpacks archives everywhere, codesign, plutil, and
  # hdiutil make a Mac's bundle and disk image, rcedit and makensis a
  # Windows program and its installer, and mksquashfs a Linux AppImage. A
  # tool that fails says why on its own output, and one that is missing
  # says nothing at all, so a build that only reported "failed" would
  # leave the developer guessing.
  #
  # This module runs a command with arguments as an array, never through
  # a shell, so paths with spaces stay whole. When the tool fails, the
  # Fledge::Error it raises carries the tool's own output; when it is not
  # on this computer, the error says what to install.
  #
  # Use it for every external tool <tt>fledge build</tt> runs.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Command.run("hdiutil", "verify", "MyApp.dmg", install: "It comes with macOS.")
  #   # => "...checksum of ... is VALID\n"
  #--
  # SPDX-SnippetEnd
  #++
  module Command
    # Runs +command+ with +env+ added to the environment, and returns its
    # standard output and error together. Raises Fledge::Error with that
    # output when the command fails, and with +install+, which says how
    # to get the tool, when it is not on this computer.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Command.run("tar", "-tf", "app.tar.gz", install: "Install tar.")
    #--
    # SPDX-SnippetEnd
    #++
    def self.run(*command, install:, env: {})
      output, status = Open3.capture2e(env, *command)
      return output if status.success?

      raise Error, "#{File.basename(command.first.to_s)} failed (#{status}):\n#{output.strip}"
    rescue SystemCallError => e
      raise Error, "fledge build needs #{File.basename(command.first.to_s)}, which it could not run (#{e.message}). #{install}"
    end

    # Runs +command+ as #run does, and returns only its standard output,
    # as bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Command.read("tar", "-xOf", "runtime.tar.gz", "runtime/lib/rbconfig.rb", install: "Install tar.")
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(*command, install:)
      output, error, status = Open3.capture3(*command, binmode: true)
      return output if status.success?

      raise Error, "#{File.basename(command.first.to_s)} failed (#{status}):\n#{error.strip}"
    rescue SystemCallError => e
      raise Error, "fledge build needs #{File.basename(command.first.to_s)}, which it could not run (#{e.message}). #{install}"
    end
  end
end
