# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module MarkdownToHtml
  # How a program with no window tells the person what it could not do,
  # as each system tells it of an app of that kind: a notification on
  # macOS and Linux, and a message box on Windows. A file written is not
  # told, since the page beside the file says so. A system without the
  # tool for it shows nothing, and the message stays on standard error,
  # where a terminal shows it.
  module Notice
    # The command that shows +message+ under +title+. The text reaches
    # the command as an argument or an environment variable, never as
    # code, so a file's name cannot run anything.
    def self.command(title, message, platform: RUBY_PLATFORM)
      case platform
      when /darwin/
        [
          "osascript",
          "-e",
          "on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv)\nend run",
          title,
          message,
        ]
      when /mingw|mswin/
        [
          "powershell.exe",
          "-NoProfile",
          "-NonInteractive",
          "-WindowStyle",
          "Hidden",
          "-Command",
          "Add-Type -AssemblyName PresentationFramework; " \
            "[void][System.Windows.MessageBox]::Show($env:NOTICE_MESSAGE, $env:NOTICE_TITLE)",
        ]
      else
        ["notify-send", "--app-name", title, "--", title, message]
      end
    end

    # Shows +message+ and leaves the command running.
    def self.show(title, message, platform: RUBY_PLATFORM)
      env = { "NOTICE_TITLE" => title, "NOTICE_MESSAGE" => message }
      Process.detach(Process.spawn(env, *command(title, message, platform:), %i[out err] => File::NULL))
    rescue SystemCallError
      nil
    end
  end
end
