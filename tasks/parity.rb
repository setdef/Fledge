# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require "yaml"
require_relative "runtime_builder"
require_relative "../lib/fledge/cli"

# The parity check (ADR 003): an app's Ruby code must see the same Ruby
# under Fledge as under ruby main.rb.
#
# It builds the probe app in test/fixtures/parity with fledge build, from
# this computer's runtime, runs it, then runs the same main.rb with the
# very Ruby the runtime was made from (rv-ruby's, or RubyInstaller's,
# fetched by the pins in runtime/sources.yml and left as it ships), as
# ruby main.rb from the app's folder. Both get the same arguments and the
# same environment: the caller's, without the caller's own Ruby settings,
# plus a GEM_HOME and two markers that stand for a person's. It
# normalizes paths (the app's folder, each Ruby's prefix, the home
# folder, the work folder), and compares every fact.
#
# Every difference is either listed in JUSTIFIED, with the reason it is
# right, or fails the check. On Windows it runs both again under code
# page 437, as a console in the United States starts.
#
# Run it as rake parity, after rake runtime or with FLEDGE_RUNTIME_DIR set.
class Parity
  ROOT = File.expand_path("..", __dir__)
  PROBE = File.join(ROOT, "test", "fixtures", "parity")
  ARGUMENTS = ["one", "two words", "ünïcödé"].freeze

  # One difference parity allows, and why. +reference+ and +app+ are
  # patterns: each element found only in the reference run must match
  # one of +reference+, and each found only in the app must match one of
  # +app+. +platforms+, when given, limits it to those platforms.
  class Justification < Data.define(:fact, :reference, :app, :reason, :platforms)
    def self.new(fact:, reason:, reference: [], app: [], platforms: nil)
      super
    end

    def covers?(fact_name, platform, only_in_reference, only_in_app)
      return false if fact != fact_name
      return false if platforms && !platforms.include?(platform)

      only_in_reference.all? { |element| reference.any? { |pattern| pattern.match?(element) } } &&
        only_in_app.all? { |element| app.any? { |pattern| pattern.match?(element) } }
    end
  end

  # rv-ruby installs two gems a standard Ruby 4.0.9 does not, which a
  # runtime prunes (RuntimeBuilder.prune).
  RV_RUBY_EXTRAS = /\A"(?:bootsnap|msgpack)(?: |"=)/

  JUSTIFIED = [
    *%w[$0 __FILE__ $PROGRAM_NAME].map do |fact|
      Justification.new(fact:, reference: [/\A"main\.rb"\z/], app: [%r{\A"<app>/main\.rb"\z}],
        reason: "ruby main.rb names the script as typed. The launcher runs it by its absolute path, as " \
          "ruby /path/to/app/main.rb would, since a person may start the app from any folder.")
    end,
    Justification.new(fact: "Gem.path", reference: [%r{\A"<work>/person-gems"\z}, %r{\A"<home>/\.(?:gem|local/share/gem)/}],
      reason: "The app's gems are the runtime's alone (ADR 003): the person's GEM_HOME, GEM_PATH, and " \
        "Gem.user_dir never shadow them. Their ENV still reaches the app and its child processes."),
    Justification.new(fact: "Gem.dir", reference: [%r{\A"<work>/person-gems"\z}], app: [%r{\A"<prefix>/lib/ruby/gems/4\.0\.0"\z}],
      reason: "As for Gem.path: RubyGems installs into the runtime's gem folder, never the person's GEM_HOME."),
    Justification.new(fact: "gems", reference: [RV_RUBY_EXTRAS],
      reason: "rv-ruby adds bootsnap and msgpack, which no standard Ruby 4.0.9 installs; runtimes keep " \
        "Ruby's own default and bundled gems."),
    Justification.new(fact: "requireable", reference: [RV_RUBY_EXTRAS], reason: "As for gems."),
    Justification.new(fact: "$LOADED_FEATURES", app: [%r{\A"<prefix>/lib/ruby/4\.0\.0/rubygems/defaults/operating_system\.rb"\z}],
      platforms: %w[arm64-darwin x86_64-linux aarch64-linux],
      reason: "Fledge's RubyGems defaults keep RubyGems to the runtime's gems (ADR 001, section 8); " \
        "rv-ruby ships no such file."),
    Justification.new(fact: "$LOADED_FEATURES", platforms: %w[x64-mingw-ucrt],
      reference: [
        %r{\A"<prefix>/lib/ruby/site_ruby/4\.0\.0/ruby_installer/},
        %r{/rubygems/defaults/operating_system\.rb"\z},
        %r{\A"<prefix>/lib/ruby/4\.0\.0/(?:x64-mingw-ucrt/)?(?:fiddle|win32/|etc|rbconfig|fileutils|tmpdir)},
],
      app: [%r{\A"<prefix>/lib/ruby/4\.0\.0/rubygems/defaults/operating_system\.rb"\z}],
      reason: "Fledge's RubyGems defaults replace RubyInstaller's, which load RubyInstaller's runtime to " \
        "find MSYS2 and write to the gem folder on every start (ADR 001, section 8)."),
  ].freeze

  # A fact that differs between the two runs.
  class Difference < Data.define(:fact, :only_in_reference, :only_in_app, :justification)
    def justified?
      !justification.nil?
    end

    def to_s
      lines = ["#{justified? ? 'justified' : 'DIFFERENT'}: #{fact}"]
      only_in_reference.each { |element| lines << "    ruby main.rb only: #{element}" }
      only_in_app.each { |element| lines << "    built app only:    #{element}" }
      lines << "    order differs" if only_in_reference.empty? && only_in_app.empty?
      lines << "    why: #{justification.reason}" if justification
      lines.join("\n")
    end
  end

  # The JSON report in a probe's standard output.
  def self.report(output)
    line = output.lines.reverse.find { |candidate| candidate.start_with?("FLEDGE-PARITY ") }
    raise "the probe printed no report:\n#{output}" unless line

    JSON.parse(line.delete_prefix("FLEDGE-PARITY "))
  end

  # +report+ with every path it names relative to a placeholder: <app>,
  # <prefix>, <home>, and <work> (+work+), with backslashes as slashes.
  def self.normalize(report, work:)
    paths = report.fetch("paths")
    replacements = {
      paths.fetch("app") => "<app>",
      paths.fetch("prefix") => "<prefix>",
      paths.fetch("home") => "<home>",
      work => "<work>",
    }.flat_map { |path, token| variants(path).map { |variant| [variant, token] } }.sort_by { |path, _| -path.size }
    rewrite(report.except("paths"), replacements)
  end

  def self.variants(path)
    [path, path.tr("\\", "/"), File.realpath(path).tr("\\", "/")].uniq
  rescue SystemCallError
    [path, path.tr("\\", "/")].uniq
  end

  def self.rewrite(value, replacements)
    case value
    when String then replacements.reduce(value.tr("\\", "/")) { |text, (path, token)| text.gsub(path.tr("\\", "/"), token) }
    when Array then value.map { |element| rewrite(element, replacements) }
    when Hash then value.to_h { |key, element| [rewrite(key, replacements), rewrite(element, replacements)] }
    else value
    end
  end

  # A fact as a list of strings to compare: each element of an Array,
  # each KEY=VALUE of a Hash, or the one value of anything else.
  def self.elements(value)
    case value
    when Array then value.map { |element| JSON.generate(element) }
    when Hash then value.map { |key, element| "#{JSON.generate(key)}=#{JSON.generate(element)}" }
    else [JSON.generate(value)]
    end
  end

  # The facts that differ between two normalized reports, each with the
  # justification that covers it, if any.
  def self.compare(reference, app, platform:)
    (reference.keys | app.keys).filter_map do |fact|
      expected = elements(reference[fact])
      actual = elements(app[fact])
      next if expected == actual

      only_in_reference = expected - actual
      only_in_app = actual - expected
      justification = JUSTIFIED.find { |candidate| candidate.covers?(fact, platform, only_in_reference, only_in_app) }
      justification = nil if justification && (expected - only_in_reference) != (actual - only_in_app)
      Difference.new(fact:, only_in_reference:, only_in_app:, justification:)
    end
  end

  attr_reader :platform

  def initialize(platform: Fledge::Platform.local, work: File.join(ROOT, "tmp", "parity"),
    runtimes: ENV.fetch("FLEDGE_RUNTIME_DIR", File.join(ROOT, "tmp", "runtime")), out: $stdout
  )
    @platform = platform
    @work = File.expand_path(work)
    @runtimes = runtimes
    @out = out
    @builder = RuntimeBuilder.new(platform:, downloads: File.join(ROOT, "tmp", "downloads"))
  end

  # Runs the check and returns true when every difference is justified.
  def call
    FileUtils.rm_rf(@work)
    FileUtils.mkdir_p(@work)
    @launcher = build_app
    @ruby = unpack_reference
    @reference_app = File.join(@work, "reference-app")
    FileUtils.cp_r(PROBE, @reference_app)
    results = [check("", nil)]
    results << check(" under code page 437", "437") if platform.windows?
    results.all?
  end

  # Runs both, on Windows under +code_page+ when it is given, reports the
  # differences, and returns whether all are justified.
  private def check(label, code_page)
    env = environment
    reference, app = with_code_page(code_page) do
      [run([@ruby, "main.rb", *ARGUMENTS], @reference_app, env), run([@launcher, *ARGUMENTS], File.join(File.dirname(@launcher), "app"), env)]
    end
    differences = Parity.compare(Parity.normalize(reference, work: @work), Parity.normalize(app, work: @work), platform: platform.name)
    report(label, env, differences)
    differences.all?(&:justified?)
  end

  # Runs the block with the console's code page set to +code_page+, as
  # chcp sets it for a person, and then puts the old one back. Programs
  # this process starts share its console, and Ruby on Windows takes
  # Encoding.default_external from the console's code page.
  private def with_code_page(code_page)
    return yield unless code_page

    original = `chcp.com`[/\d+/] or raise "chcp printed no code page"
    system("chcp.com", code_page, out: File::NULL, exception: true)
    begin
      yield
    ensure
      system("chcp.com", original, out: File::NULL, exception: true)
    end
  end

  private def report(label, env, differences)
    lines = [
      "Parity on #{platform}#{label}: #{differences.count(&:justified?)} justified, " \
        "#{differences.count { |difference| !difference.justified? }} unjustified differences",
      "Both ran with the caller's #{env.size - PERSON.size - 1} variables, less their Ruby settings, " \
        "an empty HOME, and #{PERSON.join(', ')}",
      *differences.map(&:to_s),
    ]
    @out.puts lines
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "```\n#{lines.join("\n")}\n```\n", mode: "a") if summary
  end

  # Settings that stand for a person's own Ruby: an empty GEM_HOME, and
  # RUBY_ and BUNDLE_ variables no Ruby reads.
  PERSON = %w[GEM_HOME RUBY_PARITY_PERSON BUNDLE_PARITY_PERSON].freeze

  # The caller's environment without their own Ruby settings (as for a
  # person who has none), with an empty home folder, so the caller's own
  # gems stay out of both runs, plus PERSON.
  private def environment
    clean = ENV.to_h.reject { |name, _| name.upcase.start_with?("RUBY", "GEM_", "GEMRC", "BUNDLE_", "BUNDLER_") }
    home = File.join(@work, "home")
    person_gems = File.join(@work, "person-gems")
    FileUtils.mkdir_p([home, person_gems])
    clean.merge("HOME" => home, PERSON[0] => person_gems, PERSON[1] => "1", PERSON[2] => "1")
  end

  private def run(command, chdir, env)
    out, err, status = Open3.capture3(env, *command, chdir:, unsetenv_others: true)
    raise "#{command.join(' ')} failed (#{status}):\n#{out}\n#{err}" unless status.success?

    Parity.report(out)
  end

  # Builds the probe with fledge build into the work folder and returns
  # its launcher.
  private def build_app
    out = StringIO.new
    err = StringIO.new
    status = Fledge::CLI::Build.new(out:, err:, env: { "FLEDGE_RUNTIME_DIR" => @runtimes })
      .call(["-t", platform.name, "-o", File.join(@work, "dist"), PROBE])
    raise "fledge build failed: #{err.string}" unless status.zero?

    File.join(@work, "dist", "parity-#{platform}", platform.executable("parity"))
  end

  # Unpacks the pinned Ruby the runtime was made from, as it ships, and
  # returns its ruby program.
  private def unpack_reference
    pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(platform.name)
    archive = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
    into = File.join(@work, "reference")
    FileUtils.mkdir_p(into)
    if platform.windows?
      seven_zip = tool("7z") || [File.join(ENV.fetch("ProgramFiles", "C:/Program Files"), "7-Zip", "7z.exe")].find { |path| File.file?(path) }
      raise "unpacking #{archive} needs 7-Zip" unless seven_zip

      system(seven_zip, "x", "-y", "-bd", "-o#{into}", archive, out: File::NULL, exception: true)
    else
      system("tar", "-xzf", archive, "-C", into, exception: true)
    end
    rubies = Dir.glob(File.join(into, "**", "bin", platform.executable("ruby")))
    raise "#{archive} holds no single ruby: #{rubies}" unless rubies.size == 1

    rubies.first.to_s
  end

  private def tool(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).product(["", ".exe"]).map { |dir, ext| File.join(dir, name + ext) }
      .find { |path| File.file?(path) && File.executable?(path) }
  end
end

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  exit Parity.new(platform:).call
end
