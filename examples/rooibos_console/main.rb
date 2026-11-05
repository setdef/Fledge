# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# Fledge Check: a terminal screen that reads out what a person needs to
# see to know a Fledge-built app works on their computer. It is written
# with Rooibos, a terminal UI framework, and no other gem. It shows the
# operating system, the processor, Ruby, whether the program runs from a
# Fledge app, the settings a Ruby on the person's computer might have
# made, the terminal, a clock and a frame counter that prove it redraws,
# and the last key typed.
#
#   r       writes fledge-check-report.txt in the current folder
#   q       quits, with status 0
#   Ctrl-C  restores the terminal, then raises Interrupt as Ruby does when
#           interrupted, so the shell reports the status of SIGINT
#
# Run it as ruby main.rb or bundle exec ruby main.rb, or as the app
# fledge build makes of it; the screen reads the same except for the
# Fledge lines.

require "etc"
require "io/console"
require "rbconfig"
require "rooibos"

# What the program learns about its computer, with no gem but Rooibos.
module Check
  # The file the r key writes, in the current folder.
  REPORT = "fledge-check-report.txt"
  # The environment variables the report lists.
  WATCHED = %w[RUBYOPT RUBYLIB GEM_HOME GEM_PATH BUNDLE_GEMFILE PATH LANG LC_ALL TERM COLORTERM].freeze

  class << self
    # Whether Ctrl-C ended the app, so Interrupt is raised once the terminal is restored.
    attr_accessor :interrupted

    # The text of a file, or nil when it cannot be read.
    def read(path)
      File.read(path, encoding: "UTF-8")
    rescue SystemCallError
      nil
    end

    # The operating system's name and version, read the way each system keeps them.
    def os
      case RbConfig::CONFIG["host_os"]
      when /darwin/ then macos
      when /mswin|mingw|cygwin/ then windows
      else linux
      end
    end

    # macOS's product name, version, and build, from SystemVersion.plist.
    def macos
      plist = read("/System/Library/CoreServices/SystemVersion.plist").to_s
      pick = -> (key) { plist[%r{<key>#{key}</key>\s*<string>([^<]*)</string>}, 1] }
      "#{pick.call('ProductName') || 'macOS'} #{pick.call('ProductVersion')} (build #{pick.call('ProductBuildVersion')})"
    end

    # Windows' version, as cmd's ver prints it.
    def windows
      ver = `cmd /c ver 2>&1`.strip
      ver.empty? ? "Windows #{Etc.uname[:version]}" : ver
    rescue SystemCallError
      "Windows #{Etc.uname[:version]}"
    end

    # The distribution's name, from os-release.
    def linux
      release = read("/etc/os-release").to_s
      release[/^PRETTY_NAME="?([^"\n]*)"?/, 1] || "Linux #{Etc.uname[:release]}"
    end

    # How many colors the terminal announces.
    def color_depth
      colorterm = ENV.fetch("COLORTERM", "")
      term = ENV.fetch("TERM", "")
      if colorterm.match?(/truecolor|24bit/) then "24-bit (COLORTERM=#{colorterm})"
      elsif term.include?("256") then "256 colors (TERM=#{term})"
      elsif ENV.key?("WT_SESSION") then "24-bit (Windows Terminal)"
      elsif term.empty? then "not announced (no TERM)"
      else "TERM=#{term}"
      end
    end

    # The terminal's columns and rows.
    def terminal_size
      rows, columns = IO.console&.winsize
      rows ? "#{columns} x #{rows}" : "unknown (no terminal)"
    rescue SystemCallError, NotImplementedError
      "unknown"
    end

    # A Fledge app keeps fledge.cfg in the folder above its Ruby (bin/ruby
    # on macOS and Linux, ruby/bin/ruby.exe on Windows); the file's first
    # line says which fledge build wrote it.
    def fledge_line
      config = (1..4).filter_map { |levels| read(File.join(File.dirname(RbConfig.ruby, levels), "fledge.cfg")) }.first
      return "Fledge app: no, this is a Ruby installed on this computer" unless config

      built = config[/fledge build \S+ for [^\s:]+/]
      "Fledge app: yes, #{built || 'fledge.cfg found'}"
    end

    # The label and value of each fact that stays still while the app runs.
    def facts
      uname = Etc.uname
      cfg = RbConfig::CONFIG
      [
        ["Operating system", os],
        ["Kernel", "#{uname[:sysname]} #{uname[:release]}"],
        ["Processor", "#{uname[:machine]} (#{cfg['host_cpu']}), #{Etc.nprocessors} cores"],
        ["Ruby", "#{RUBY_VERSION} #{RUBY_PLATFORM} (patch #{RUBY_PATCHLEVEL})"],
        ["RbConfig.ruby", RbConfig.ruby],
        ["Program", "#{$PROGRAM_NAME} (__dir__ #{__dir__})"],
        ["Gem.dir", Gem.dir],
        ["Rooibos", "#{Rooibos::VERSION} on RatatuiRuby #{RatatuiRuby::VERSION}"],
        [
          "Encodings",
          "external #{Encoding.default_external}, internal #{Encoding.default_internal.inspect}, " \
            "filesystem #{Encoding.find('filesystem')}",
],
        ["Locale", %w[LANG LC_ALL LC_CTYPE].map { |name| "#{name}=#{ENV[name].inspect}" }.join(" ")],
        ["Color depth", color_depth],
        *%w[RUBYOPT RUBYLIB GEM_HOME].map { |name| [name, ENV[name].inspect] },
      ]
    end

    # The plain text report of the facts and the live values in +model+.
    def report(model)
      lines = ["Fledge Check report, #{model.time.strftime('%Y-%m-%d %H:%M:%S %z')}", "", fledge_line]
      lines += facts.map { |label, value| "#{label}: #{value}" }
      lines += [
        "Working folder: #{Dir.pwd}",
        "Terminal: #{terminal_size}",
        "Frames drawn: #{model.frame}",
        "Last key: #{model.key}",
        "",
        "Environment:",
]
      lines += WATCHED.map { |name| "  #{name}=#{ENV[name].inspect}" }
      lines += ["", "Load path (first 12):", *$LOAD_PATH.first(12).map { |path| "  #{path}" }, "", "RbConfig:"]
      lines += %w[bindir libdir rubylibdir arch host_os].map { |key| "  #{key}=#{RbConfig::CONFIG[key]}" }
      "#{lines.join("\n")}\n"
    end

    # Writes the report and returns the line to show for it.
    def write_report(model)
      path = File.expand_path(REPORT)
      File.write(path, report(model), encoding: "UTF-8")
      "Report written to #{path}"
    rescue SystemCallError => e
      "Report not written: #{e.message}"
    end
  end
end

# The Rooibos app: Init, View, and Update, as a Rooibos app has them.
module FledgeCheck
  # The live values: the time, the frame count, the last key, and a status line.
  Model = Data.define(:time, :frame, :key, :status)

  # The first model.
  Init = -> { Model.new(time: Time.now, frame: 0, key: "(none yet)", status: "r writes a report, q quits") }

  # The screen: one bordered paragraph of lines.
  View = lambda { |model, tui|
    text = [
      Check.fledge_line,
      "Clock            #{model.time.strftime('%H:%M:%S')}  frame #{model.frame}",
      "Last key         #{model.key}",
      model.status,
      "Terminal         #{Check.terminal_size}",
      "",
      *Check.facts.map { |label, value| "#{label.ljust(16)} #{value}" },
    ].join("\n")
    tui.paragraph(text:, wrap: true, block: tui.block(title: " Fledge Check ", borders: [:all]))
  }

  # A key changes the model or ends the app; every other frame advances the clock and counter.
  Update = lambda { |message, model|
    case message
    in { type: :key, code: "c", modifiers: ["ctrl"] }
      Check.interrupted = true
      Rooibos::Command.exit
    in { type: :key, code: "q" }
      Rooibos::Command.exit
    in { type: :key, code: "r" }
      model.with(status: Check.write_report(model), key: "r")
    in { type: :key, code:, modifiers: }
      model.with(key: (modifiers + [code]).join("+"))
    else
      model.with(time: Time.now, frame: model.frame + 1)
    end
  }
end

if $PROGRAM_NAME == __FILE__
  Rooibos.run(FledgeCheck, fps: 10, update_every_frame: true)
  raise Interrupt if Check.interrupted
end
