# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"
require_relative "../app"
require_relative "../app_gems"
require_relative "../assembly"
require_relative "../bundle"
require_relative "../error"
require_relative "../gem_fetcher"
require_relative "../git_checkout"
require_relative "../installers"
require_relative "../native_build"
require_relative "../platform"
require_relative "../runtime_contents"
require_relative "../runtimes"
require_relative "build/options"

module Fledge
  class CLI
    # The <tt>fledge build</tt> command.
    #
    # Shipping an app means copying it into a runtime for each platform
    # you want it to run on, and archiving each result (Plan 001). Doing
    # that by hand means knowing where each runtime lives, renaming its
    # launcher, and archiving without losing an executable bit.
    #
    # This command builds for the computer it runs on, as Tauri's and
    # Briefcase's builds do, since each platform's app is made with that
    # platform's own tools (ADR 010). It reads <tt>--out</tt> and the
    # program to ship from its arguments (Fledge::App), finds this
    # platform's runtime through Fledge::Runtimes, adds the gems the app's
    # Gemfile.lock locks for it (Fledge::Bundle and Fledge::AppGems),
    # compiling those that need it (Fledge::NativeBuild) in a work folder
    # it removes afterwards, builds the app with Fledge::Assembly, and
    # prints the path of its archive and of each installer
    # (Fledge::Installers) it wrote, one per line, the archive first. A failed build becomes
    # lines beginning <tt>fledge build:</tt> on the error stream and exit
    # status 1; a mistake in its arguments raises Fledge::UsageError,
    # which Fledge::CLI turns into the usage and exit status 2.
    #
    # Use it through the +fledge+ executable, or through Fledge::CLI.
    #
    # === Examples
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # From a terminal:
    #   #   $ fledge build examples/my_cool_app/exe/my_cool_app
    #   #   dist/MyCoolApp-x86_64-linux.tar.gz
    #
    #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["examples/hello"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    class Build
      # The output folder when you give no <tt>--out</tt>.
      DEFAULT_OUT = "dist"

      # Creates the command.
      #
      # [out] Where results go, such as <tt>$stdout</tt>.
      # [err] Where errors and progress go, such as <tt>$stderr</tt>.
      # [env] The environment Fledge::Runtimes reads (default: +ENV+).
      # [host] The Gem::Platform of the computer it builds for (default:
      #        Gem::Platform.local).
      def initialize(out:, err:, env: ENV, host: Gem::Platform.local)
        @out = out
        @err = err
        @env = env
        @host = host
      end

      # Runs the command with the arguments after +build+, and returns
      # the exit status: 0 when every target built, 1 otherwise. Raises
      # Fledge::UsageError for arguments it cannot make sense of.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["--out", "/tmp/builds", "my_app"]) # => 0
      #--
      # SPDX-SnippetEnd
      #++
      def call(argv)
        options = Options.parse(argv)
        app = App.at(options.path)
        build(app, Platform.local(@host), options.out)
        0
      rescue UsageError
        raise
      rescue Error => e
        e.message.each_line { |line| @err.puts "fledge build: #{line.chomp}" }
        1
      end

      private def build(app, platform, out)
        out_dir = File.expand_path(out)
        raise Error, "--out can't be the app's own folder, #{out}" if out_dir == app.root

        runtimes = Runtimes.new(env: @env, log: @err)
        Dir.mktmpdir("fledge-build") do |work|
          gems = gems_for(app, runtimes, work)
          app_files = gems ? gems.app_files : {} # : Hash[String, String]
          runtime = runtimes.archive(platform)
          files = gems ? gems.for(platform, runtime: RuntimeContents.read(runtime)) : [] # : Array[Entry]
          makensis = Installers.formats(app, platform).include?("nsis") ? makensis(runtimes) : nil
          assembly = Assembly.new(app:, platform:, runtime:, out: out_dir, app_files:, files:, makensis:)
          [assembly.call, *assembly.installers].each { |path| @out.puts File.join(out, File.basename(path)) }
        end
      end

      # The app's gems, for an app with a Gemfile: Fledge keeps the gems it
      # downloads beside its runtimes, in <tt>~/.cache/fledge/gems</tt>,
      # and the git repositories it fetches in <tt>~/.cache/fledge/git</tt>,
      # and compiles gems for the platform it runs on.
      private def gems_for(app, runtimes, work)
        return nil unless app.gemfile

        cache = File.dirname(runtimes.cache)
        fetcher = GemFetcher.new(cache: File.join(cache, "gems"), project: app.root, log: @err)
        checkouts = GitCheckout.new(cache: File.join(cache, "git"), work:, log: @err)
        AppGems.new(app:, bundle: Bundle.new(app), fetcher:, checkouts:, compiler: compiler(runtimes, work))
      end

      # The NSIS compiler for this computer, which Fledge downloads beside
      # its runtimes (Runtimes#makensis).
      private def makensis(runtimes)
        @makensis ||= runtimes.makensis(Platform.local(@host))
      rescue Error => e
        raise Error, "#{e.message}\nAn NSIS installer needs makensis for this computer; set installers in fledge.yml to build without one."
      end

      private def compiler(runtimes, work)
        NativeBuild.new(platform: Platform.local(@host), runtimes:, work:, log: @err, env: @env)
      end
    end
  end
end
