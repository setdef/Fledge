# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module MarkdownPreview
  # Opens a page in the person's browser: the one BROWSER names, as
  # Python's webbrowser module and xdg-open read it (the first of a
  # list, separated as PATH is), or else whatever the system opens an
  # HTML file with.
  module Browser
    # The command that opens the page at +path+.
    def self.command(path, env: ENV, platform: RUBY_PLATFORM)
      browser = env.fetch("BROWSER", "").split(File::PATH_SEPARATOR).first
      return [browser, path] if browser

      case platform
      when /darwin/ then ["open", path]
      # explorer.exe, a windowed program, opens a file as a double-click
      # does, where cmd.exe's start would flash a console.
      when /mingw|mswin/ then ["explorer.exe", path.tr("/", "\\")]
      else ["xdg-open", path]
      end
    end

    # Opens the page at +path+ and leaves the browser running. A system
    # with nothing to open it with leaves the page where it is.
    def self.open(path)
      Process.detach(Process.spawn(*command(path), %i[out err] => File::NULL))
    rescue SystemCallError
      nil
    end
  end
end
