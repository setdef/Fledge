# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "download_cache"
require_relative "parity"
require_relative "ruby_spec/results"

# The ruby/spec comparison: ruby/spec, run by MSpec, on stock Ruby and in
# a built app, with every example that fails on one side only either
# justified in JUSTIFIED or failing the check (ADR 003, section 4; AGENTS.md,
# Design precedence 2).
#
# It downloads ruby/spec and MSpec at their pinned commits (SOURCES),
# each checked against its SHA-256, and writes a project of
# tasks/ruby_spec/main.rb with the two beside it. Stock Ruby is the Ruby
# this computer's runtime was made from, unpacked as it ships, as the
# parity check runs it (Parity#unpack_reference), running ruby main.rb
# in one copy of the project; the built app is another copy, built by
# fledge build from the runtime. Each runs mspec-run over DIRECTORIES,
# one process per directory, in the same clean environment: a PATH with
# no Ruby on it, an empty home folder, and no locale, as a desktop starts
# an app. A person's hostile Ruby settings are not part of it: they reach
# the child Rubies the specs start through RbConfig.ruby, as they would
# under ruby main.rb (ADR 003, Consequences), and stock Ruby would read
# them at its own boot, where the launcher hides them.
#
# Each run's output is kept in the output folder, with a summary that
# also goes to the job summary in CI. The spec files are data downloaded
# for the run: nothing of ruby/spec or MSpec is committed or shipped.
#
# Run it as rake ruby_spec, after rake runtime or with FLEDGE_RUNTIME_DIR
# set; RUBY_SPEC_OUT names the output folder (default tmp/ruby-spec).
class RubySpec
  ROOT = File.expand_path("..", __dir__)

  # ruby/spec's directories that CRuby's own make test-spec runs.
  DIRECTORIES = %w[language core library command_line security].freeze

  # A repository of the ruby organization at a commit, as GitHub archives
  # it, and the SHA-256 of that archive.
  class Source < Data.define(:name, :commit, :sha256)
    def url
      "https://github.com/ruby/#{name}/archive/#{commit}.tar.gz"
    end

    # The host the archive URL redirects to, which serves the same bytes.
    def mirror
      "https://codeload.github.com/ruby/#{name}/tar.gz/#{commit}"
    end
  end

  # ruby/spec and MSpec, both MIT-licensed, at the commits the
  # experiment/ruby-spec spike ran (run 41776558621).
  SOURCES = [
    Source.new(name: "spec", commit: "47b10f1d7b1c29bda01d6903cceddd5b0b4c857d",
      sha256: "7587318e196940fe39bcb4eff27c54fdf17410d64786e313db6a3a1fffb7ae8a"),
    Source.new(name: "mspec", commit: "521207f313abfaffd56dca274475c56012f90221",
      sha256: "71c4b12fdaf37b06834fb568dccb11f355942d48e0cd97c4f6120759f5bf64f9"),
  ].freeze

  # Examples left out of both runs, by platform, each because it stops
  # the process for stock Ruby and the app alike (mspec-run -E).
  EXCLUDED = %w[x86_64-linux-musl aarch64-linux-musl].to_h do |platform|
    # CRuby 4.0.9 on musl crashes setting the name of a thread that has
    # ended (pthread_setname_np on a thread musl has freed), at
    # core/thread/to_s_spec.rb line 18, and the whole core run stops.
    [platform, ["Thread#to_s returns a description including a thread name if given any"]]
  end.freeze

  JUSTIFIED = [
    Justification.new(
      example: /\Acore: (?:Dir\.chdir|File\.readlink|File\.realpath) accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters/,
      side: :stock, platforms: %w[arm64-darwin],
      reason: "With no locale, stock Ruby takes the C locale and reads paths as US-ASCII, and these macOS-only " \
        "examples fail converting one; the built app's launcher takes a UTF-8 locale in place of a bare C one " \
        "(ADR 026, section 1; Parity::JUSTIFIED), so they pass there.",
    ),
  ].freeze

  attr_reader :platform

  def initialize(platform: Fledge::Platform.local, work: File.join(ROOT, "tmp", "ruby-spec-work"),
    out: ENV.fetch("RUBY_SPEC_OUT", File.join(ROOT, "tmp", "ruby-spec")),
    runtimes: ENV.fetch("FLEDGE_RUNTIME_DIR", File.join(ROOT, "tmp", "runtime")), log: $stdout
  )
    @platform = platform
    @work = File.expand_path(work)
    @out = File.expand_path(out)
    @runtimes = runtimes
    @log = log
    @downloads = DownloadCache.new(File.join(ROOT, "tmp", "downloads"))
  end

  # Runs the comparison and returns true when every difference is
  # justified.
  def call
    FileUtils.rm_rf([@work, @out])
    FileUtils.mkdir_p([@work, @out])
    sources = SOURCES.to_h { |source| [source.name, unpack(source)] }
    parity = Parity.new(platform:, work: File.join(@work, "parity"), runtimes: @runtimes, out: @log)
    FileUtils.mkdir_p(File.join(@work, "parity"))
    ruby = parity.unpack_reference
    app = parity.build_app(project(File.join(@work, "build", "ruby_spec"), sources), "RubySpec")
    stock = run("stock", [ruby, "main.rb"], project(File.join(@work, "reference", "ruby_spec"), sources))
    built = run("app", [app], @work)
    differences = Results.compare(stock, built, platform: platform.name)
    report(stock, built, differences)
    differences.all?(&:justified?)
  end

  # Downloads +source+ into the download cache, checked against its
  # SHA-256, unpacks it into the work folder with the computer's own tar
  # (Fledge::Archive), and returns its folder.
  private def unpack(source)
    archive = @downloads.fetch(source.url, source.sha256, mirrors: [source.mirror])
    into = File.join(@work, "sources")
    FileUtils.mkdir_p(into)
    Fledge::Archive.unpack(archive, into:)
    File.join(into, "#{source.name}-#{source.commit}")
  end

  # A project in the new folder +into+: main.rb, with ruby/spec and MSpec
  # beside it as spec/ and mspec/, without their repositories' own files
  # or MSpec's own specs, and a fledge.yml naming the app.
  private def project(into, sources)
    FileUtils.mkdir_p(into)
    FileUtils.cp(File.join(__dir__, "ruby_spec", "main.rb"), into)
    sources.each { |name, folder| FileUtils.cp_r(folder, File.join(into, name)) }
    FileUtils.rm_rf(Dir.glob(File.join(into, "{spec,mspec}", ".git*")) + [File.join(into, "mspec", "spec")])
    File.write(File.join(into, "fledge.yml"), "name: RubySpec\n")
    into
  end

  # Runs +command+ once per directory of DIRECTORIES from +chdir+, in the
  # clean environment, writes each output to the output folder under
  # +label+, and returns the Results::Run of each.
  private def run(label, command, chdir)
    env = environment(label)
    folder = File.join(@out, label)
    FileUtils.mkdir_p(folder)
    options = ["--timeout", "300", *EXCLUDED.fetch(platform.name, []).flat_map { |example| ["-E", example] }]
    DIRECTORIES.map do |directory|
      file = File.join(folder, "#{directory}.out")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = Process.spawn(env, *command, *options, directory, chdir:, unsetenv_others: true, out: file, err: %i[child out],
        in: File::NULL)
      Process.wait(pid)
      Results.read(directory, File.binread(file)).tap do |result|
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        @log.puts format("%-5s %-12s %4.0fs  %s", label, directory, seconds, result.totals || "did not finish")
      end
    end
  end

  # The environment both sides run in: a PATH with no Ruby, an empty home
  # folder of +label+'s own, a short folder for MSpec's temporary files
  # (a UNIX socket's path may hold no more than 104 bytes on macOS), and
  # no locale. On Windows, what a Windows program needs to start programs
  # (ComSpec, PATHEXT) and to find its folders.
  private def environment(label)
    home = File.join(@work, "home-#{label}")
    temporary = platform.windows? ? File.join(@work, "t-#{label}") : "/tmp/fledge-rs-#{label}"
    FileUtils.rm_rf([home, temporary])
    FileUtils.mkdir_p([home, temporary])
    return { "PATH" => path_without_ruby, "HOME" => home, "SPEC_TEMP_DIR" => temporary } unless platform.windows?

    system_root = ENV.fetch("SystemRoot")
    temp = File.join(@work, "temp-#{label}").tr("/", "\\")
    FileUtils.mkdir_p(temp)
    path = ["\\System32", "", "\\System32\\Wbem", "\\System32\\WindowsPowerShell\\v1.0"].map { |dir| "#{system_root}#{dir}" }
    {
      "SystemRoot" => system_root,
      "SystemDrive" => ENV.fetch("SystemDrive"),
      "windir" => system_root,
      "ComSpec" => ENV.fetch("ComSpec"),
      "PATHEXT" => ENV.fetch("PATHEXT"),
      "PATH" => path.join(";"),
      "USERPROFILE" => home,
      "TEMP" => temp,
      "TMP" => temp,
      "SPEC_TEMP_DIR" => temporary,
    }
  end

  # A folder of links to the system's programs, less any Ruby and its
  # tools, for PATH.
  private def path_without_ruby
    folder = File.join(@work, "path")
    return folder if File.directory?(folder)

    FileUtils.mkdir_p(folder)
    %w[/usr/local/bin /usr/bin /bin /usr/sbin /sbin].each do |dir|
      Dir.glob(File.join(dir, "*")).each do |program|
        name = File.basename(program)
        next if name.match?(/\A(?:ruby|gem|irb|erb|rake|rdoc|ri|bundle|bundler|rbs|typeprof|racc)[\d.]*\z/)

        link = File.join(folder, name)
        File.symlink(program, link) unless File.exist?(link) || File.symlink?(link)
      end
    end
    folder
  end

  private def report(stock, built, differences)
    lines = [
      "ruby/spec on #{platform}: #{differences.count(&:justified?)} justified, " \
        "#{differences.count { |difference| !difference.justified? }} unjustified differences",
      *stock.zip(built).map { |reference, app| "  #{reference.directory}: stock #{reference.totals || 'did not finish'}; app #{app.totals || 'did not finish'}" },
      *differences.map(&:to_s),
    ]
    @log.puts lines
    File.write(File.join(@out, "summary.txt"), "#{lines.join("\n")}\n")
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "```\n#{lines.join("\n")}\n```\n", mode: "a") if summary
  end
end

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  exit RubySpec.new(platform:).call
end
