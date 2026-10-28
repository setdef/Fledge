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
require_relative "parity/difference"
require_relative "parity/justification"
require_relative "parity/reports"

# The parity check (ADR 003 and ADR 005): an app's Ruby code must see the
# same Ruby under Fledge as it does run as its developer runs it.
#
# It builds the probe app in test/fixtures/parity with fledge build, from
# this computer's runtime, runs it, then runs the same main.rb with the
# very Ruby the runtime was made from (rv-ruby's, or RubyInstaller's,
# fetched by the pins in runtime/sources.yml and left as it ships), as
# ruby main.rb from the app's folder. Then it does the same for a
# gem-shaped app: examples/my_cool_app with the probe as its
# exe/my_cool_app, built with its locked gems, against bundle exec ruby
# exe/my_cool_app on the same Ruby, with the bundle installed there as
# its developer would install it (bundle install, into GEM_HOME). Each
# pair gets the same arguments and the same environment: the caller's,
# without the caller's own Ruby settings, plus a GEM_HOME, a RUBYOPT, and
# two markers that stand for a person's. It normalizes paths (the app's
# folder, its project's root, each Ruby's prefix, the home folder, the
# work folder), and compares every fact.
#
# Every difference is either listed in JUSTIFIED, with the reason it is
# right, or fails the check. On Windows it runs the script check again
# under code page 437, as a console in the United States starts.
#
# Run it as rake parity, after rake runtime or with FLEDGE_RUNTIME_DIR set.
class Parity
  ROOT = File.expand_path("..", __dir__)
  PROBE = File.join(ROOT, "test", "fixtures", "parity")
  # The gem-shaped app whose exe/my_cool_app the probe stands in for.
  GEM_APP = File.join(ROOT, "examples", "my_cool_app")
  ARGUMENTS = ["one", "two words", "ünïcödé"].freeze

  # rv-ruby installs two gems a standard Ruby 4.0.9 does not, which a
  # runtime prunes (RuntimeBuilder::Pruning.prune).
  RV_RUBY_EXTRAS = /\A"(?:bootsnap|msgpack)(?: |"=)/

  # Where bundle install puts a gem's files for the person, and where
  # fledge build puts them in the app.
  PERSON_GEMS = %r{<work>/person-gems}
  APP_GEMS = %r{<prefix>/lib/ruby/gems/4\.0\.0}

  # The variables Bundler sets for the bundle it set up, whose values
  # name where the gems are (ADR 005).
  BUNDLE_LOCATIONS = /\A"(?:GEM_HOME|PATH)"=/

  JUSTIFIED = [
    *%w[$0 __FILE__ $PROGRAM_NAME].map do |fact|
      Justification.new(fact:, reference: [/\A"main\.rb"\z/], app: [%r{\A"<app>/main\.rb"\z}], checks: %i[script],
        reason: "ruby main.rb names the script as typed. The launcher runs it by its absolute path, as " \
          "ruby /path/to/app/main.rb would, since a person may start the app from any folder.")
    end,
    *%w[$0 __FILE__ $PROGRAM_NAME].map do |fact|
      Justification.new(fact:, reference: [%r{\A"exe/my_cool_app"\z}], app: [%r{\A"<app>/my_cool_app"\z}], checks: %i[bundle],
        reason: "bundle exec ruby exe/my_cool_app names the program as typed. The launcher runs it by its absolute " \
          "path, since a person may start the app from any folder.")
    end,
    Justification.new(fact: "$LOAD_PATH", reference: [%r{\A"#{PERSON_GEMS}/gems/}], app: [%r{\A"#{APP_GEMS}/gems/}], checks: %i[bundle],
      reason: "bundle install put the gems in the person's GEM_HOME; fledge build put the same gems in the runtime's gem " \
        "folder, beside Ruby's own (ADR 005). Bundler sets up the same gems, in the same order, from each."),
    Justification.new(fact: "$LOAD_PATH", reference: [%r{\A"#{PERSON_GEMS}/gems/rake-}], checks: %i[bundle],
      reason: "A built app leaves out the Gemfile's development and test groups, as Warbler does, and its Bundler " \
        "sets up the rest (ADR 005); bundle exec on the developer's computer sets up all of them."),
    Justification.new(fact: "gems", reference: [/\A"rake /], checks: %i[bundle], reason: "As for $LOAD_PATH: rake is a development gem."),
    Justification.new(fact: "requireable", reference: [/\A"rake"=/], checks: %i[bundle], reason: "As for gems."),
    *["ENV", "child ENV"].map do |fact|
      Justification.new(fact:, reference: [BUNDLE_LOCATIONS], app: [BUNDLE_LOCATIONS], checks: %i[bundle],
        reason: "Bundler points GEM_HOME and PATH at the bundle's gems, as bundle exec does: the person's GEM_HOME on " \
          "their computer, the runtime's gem folder in the app. Everything else Bundler sets, it sets over the " \
          "person's own values in both, and records theirs as BUNDLER_ORIG_*.")
    end,
    Justification.new(fact: "$VERBOSE", reference: [/\Anull\z/], app: [/\Afalse\z/],
      reason: "The person's RUBYOPT (-W0 here) is hidden from the app's boot (AGENTS.md, Design precedence 1; ADR 003), " \
        "so it cannot change how the app runs; it still reaches the app's ENV and every program the app starts."),
    Justification.new(fact: "$LOADED_FEATURES", app: [%r{\A"<prefix>/lib/ruby/4\.0\.0/rubygems/yaml_serializer\.rb"\z}],
      checks: %i[bundle],
      reason: "Bundler reads the app's .bundle/config, where fledge build records the app's bundle as frozen and " \
        "without the development and test groups, as bundle config set --local would (ADR 005). Reading a " \
        "configuration file loads RubyGems' YAML serializer."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"<prefix>/lib/ruby/4\.0\.0/bundler/feature_flag\.rb"\z}],
      checks: %i[bundle],
      reason: "With no setting that says where the bundle's gems are, Bundler asks its feature flags whether to use " \
        "Ruby's own gem folder; the app's .bundle/config says so (path.system, as Warbler's does), so it never asks."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"<project>/lib/my_cool_app/version\.rb"\z}], checks: %i[bundle],
      reason: "Bundler evaluates the project's gemspec as it sets up the bundle, and this one requires its version file. " \
        "A built app ships the gemspec evaluated, as Bundler caches a git gem's (ADR 005), so that one that runs git " \
        "needs no git; the version file loads when the app requires it, as every other file of the app does."),
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
        %r{\A"<prefix>/lib/ruby/4\.0\.0/x64-mingw-ucrt/(?:enc/|win32/dll_directory\.so"\z)},
      ],
      reason: "Fledge's RubyGems defaults replace RubyInstaller's (ADR 001, section 8), which load " \
        "RubyInstaller's runtime to look for MSYS2, and with it win32/dll_directory and the " \
        "encodings its messages use. Ruby loads an encoding when code first needs it, so an app " \
        "that uses one finds it either way."),
  ].freeze

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
    results << check_bundle
    results.all?
  end

  # The gem-shaped check: the probe as examples/my_cool_app's program,
  # built with its locked gems, against bundle exec ruby
  # exe/my_cool_app, with the bundle installed into the person's GEM_HOME.
  private def check_bundle
    env = environment
    project = gem_project("gem-app")
    reference = gem_project("reference-gem-app")
    bundle = File.join(File.dirname(@ruby), "bundle")
    install = [@ruby, bundle, "install", "--quiet"]
    system(env.merge("BUNDLE_FROZEN" => "true"), *install, chdir: reference, unsetenv_others: true, exception: true)
    launcher = build_app(File.join(project, "exe", "my_cool_app"), "MyCoolApp")
    expected = run([@ruby, bundle, "exec", @ruby, "exe/my_cool_app", *ARGUMENTS], reference, env)
    actual = run([launcher, *ARGUMENTS], File.join(File.dirname(launcher), "app"), env)
    differences = Reports.compare(Reports.normalize(expected, work: @work), Reports.normalize(actual, work: @work),
      platform: platform.name, check: :bundle)
    report(" of a gem-shaped app with bundle exec", env, differences)
    differences.all?(&:justified?)
  end

  # A copy of examples/my_cool_app in the work folder, named +name+, with
  # the probe as its exe/my_cool_app.
  private def gem_project(name)
    Parity.gem_probe(File.join(@work, name))
  end

  # Writes the gem-shaped probe into the new folder +project+: a copy of
  # examples/my_cool_app, without the developer's .bundle, with the probe
  # as its exe/my_cool_app, and with +name+, when given, as the app's name
  # in its fledge.yml. Returns +project+. CI builds one for Delivery, and
  # test/built_app_test.rb for the built app's tests.
  def self.gem_probe(project, name: nil)
    FileUtils.cp_r(GEM_APP, project)
    FileUtils.rm_rf(File.join(project, ".bundle"))
    FileUtils.cp(File.join(PROBE, "main.rb"), File.join(project, "exe", "my_cool_app"))
    File.write(File.join(project, "fledge.yml"), "name: #{name}\n") if name
    project
  end

  # Runs both, on Windows under +code_page+ when it is given, reports the
  # differences, and returns whether all are justified.
  private def check(label, code_page)
    env = environment
    reference, app = with_code_page(code_page) do
      [run([@ruby, "main.rb", *ARGUMENTS], @reference_app, env), run([@launcher, *ARGUMENTS], File.join(File.dirname(@launcher), "app"), env)]
    end
    differences = Reports.compare(Reports.normalize(reference, work: @work), Reports.normalize(app, work: @work), platform: platform.name)
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

  # Settings that stand for a person's own Ruby: an empty GEM_HOME, a
  # RUBYOPT that only quiets warnings, and RUBY_ and BUNDLE_ variables no
  # Ruby reads.
  PERSON = %w[GEM_HOME RUBYOPT RUBY_PARITY_PERSON BUNDLE_PARITY_PERSON].freeze

  # The caller's environment without their own Ruby settings (as for a
  # person who has none), with an empty home folder, so the caller's own
  # gems stay out of both runs, plus PERSON.
  private def environment
    clean = ENV.to_h.reject { |name, _| name.upcase.start_with?("RUBY", "GEM_", "GEMRC", "BUNDLE_", "BUNDLER_") }
    home = File.join(@work, "home")
    person_gems = File.join(@work, "person-gems")
    FileUtils.mkdir_p([home, person_gems])
    clean.merge("HOME" => home, PERSON[0] => person_gems, PERSON[1] => "-W0", PERSON[2] => "1", PERSON[3] => "1")
  end

  private def run(command, chdir, env)
    out, err, status = Open3.capture3(env, *command, chdir:, unsetenv_others: true)
    raise "#{command.join(' ')} failed (#{status}):\n#{out}\n#{err}" unless status.success?

    Reports.report(out)
  end

  # Builds +path+ (default: the probe) with fledge build into the work
  # folder and returns its launcher, the program +name+.
  private def build_app(path = PROBE, name = "Parity")
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => @runtimes)
    status = Fledge::CLI::Build.new(out:, err:, env:).call(["-o", File.join(@work, "dist"), path])
    raise "fledge build failed: #{err.string}" unless status.zero?

    File.join(@work, "dist", "#{name}-#{platform}", platform.executable(name))
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
