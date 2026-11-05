# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/fledge"
require_relative "../lib/fledge/mobile_platform"
require_relative "../lib/fledge/runtime_gem"

# Installs a release's gems (ReleaseGems) as a developer would, offline,
# and builds hello from them (rake gems:check, and the Gems workflow, on
# each platform; ADR 030). Run it with no Bundler around it
# (Bundler.with_unbundled_env), or as a script:
#
#   ruby tasks/gems_check.rb DIR [PHONE]
#
# On a desktop platform it installs twice: with RubyGems, fledge and this
# computer's runtime gem into an empty GEM_HOME; and with Bundler, a
# project whose Gemfile names fledge and whose vendor/cache holds every
# gem, installed with bundle install --local, which picks this computer's
# runtime gem as it would from RubyGems.org. Each fledge then prints its
# version and builds hello with an empty cache and every download sent to
# a closed port, so the runtime can come only from an installed gem, and
# the built hello runs with an environment that has no Ruby in it. With
# a PHONE, it installs fledge and that phone's runtime gem with RubyGems
# and writes hello's project for the phone the same way.
class GemsCheck
  # The gems did not install, or the fledge they installed did not build
  # hello from its runtime gem alone.
  class Failure < StandardError; end

  # A port nothing listens on: every download goes there and fails.
  CLOSED = "http://127.0.0.1:9"

  HELLO = File.expand_path("../examples/hello", __dir__)

  # [dir] The folder of built gems.
  # [log] Where to say what each built hello printed.
  # [phone] A Fledge::MobilePlatform to write hello's project for, or
  #         +nil+ for this computer's own app.
  # [platform] The Fledge::Platform of this computer.
  def initialize(dir:, log:, phone: nil, platform: Fledge::Platform.local)
    @dir = dir
    @log = log
    @phone = phone
    @platform = platform
    @version = Fledge::VERSION
  end

  # Installs the gems and builds hello from them, in a folder of its own.
  # Raises Failure.
  def call
    Dir.mktmpdir("fledge-gems") do |work|
      home = File.join(work, "home")
      FileUtils.mkdir_p(home)
      env = clean(home)
      if @phone
        project(with_rubygems(env, work, Fledge::RuntimeGem.for(@phone)), work)
      else
        hello(*with_rubygems(env, work, Fledge::RuntimeGem.for(@platform)), work, "gem")
        hello(*with_bundler(env, work), File.join(work, "project"), "bundle")
      end
    end
  end

  private def clean(home)
    {
      "HOME" => home,
      "USERPROFILE" => home,
      "XDG_CACHE_HOME" => nil,
      "RUBYLIB" => nil,
      "RUBYOPT" => nil,
      "BUNDLE_GEMFILE" => nil,
      "BUNDLE_BIN_PATH" => nil,
      "FLEDGE_RUNTIME_DIR" => nil,
      "http_proxy" => CLOSED,
      "https_proxy" => CLOSED,
      "HTTP_PROXY" => CLOSED,
      "HTTPS_PROXY" => CLOSED,
    }
  end

  # A command of the Ruby running this check, such as +gem+ or +bundle+,
  # run by that Ruby, which works on Windows too, where the command
  # beside it is a batch file.
  private def ruby_command(name)
    [RbConfig.ruby, File.join(RbConfig::CONFIG["bindir"], name)]
  end

  # RubyGems' local source, the .gem files in the current folder, picks a
  # gem by name and version alone, whatever its platform
  # (Gem::Source::Local#find_gem), where a gem server's index picks by
  # platform, so the folder it installs from holds only the gems a gem
  # server would offer this computer: fledge, this computer's runtime
  # gem, and +gem+ when it is a phone's. Returns the environment and the
  # command that run the installed fledge.
  private def with_rubygems(env, work, gem)
    gem_home = File.join(work, "gem-home")
    env = env.merge("GEM_HOME" => gem_home, "GEM_PATH" => gem_home)
    wanted = [Fledge::RuntimeGem.for(@platform), gem].uniq.map { |runtime| file_base(runtime) } << "fledge-#{@version}"
    offered = File.join(work, "offered")
    FileUtils.mkdir_p(offered)
    FileUtils.cp(wanted.map { |name| File.join(@dir, "#{name}.gem") }, offered)
    install = [*ruby_command("gem"), "install", "--local", "--no-document", "--install-dir", gem_home]
    run(env, offered, *install, "fledge-#{@version}.gem")
    run(env, offered, *install, "#{file_base(gem)}.gem") unless gem.desktop?
    installed = Dir.children(File.join(gem_home, "gems")).sort
    raise Failure, "RubyGems installed #{installed.join(', ')}, not #{wanted.join(', ')}" unless installed == wanted.sort

    [env, [RbConfig.ruby, File.join(gem_home, "bin", "fledge")]]
  end

  private def file_base(gem)
    gem.desktop? ? "#{gem.name}-#{@version}-#{gem.platform}" : "#{gem.name}-#{@version}"
  end

  private def with_bundler(env, work)
    project = File.join(work, "project")
    FileUtils.mkdir_p(File.join(project, "vendor", "cache"))
    FileUtils.cp(Dir.glob(File.join(@dir, "*.gem")), File.join(project, "vendor", "cache"))
    File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"fledge\", \"#{@version}\"\n")
    env = env.merge("BUNDLE_GEMFILE" => File.join(project, "Gemfile"), "BUNDLE_PATH" => File.join(work, "bundle"),
      "GEM_HOME" => File.join(work, "bundle-gem-home"))
    run(env, project, *ruby_command("bundle"), "install", "--local")
    [env, [*ruby_command("bundle"), "exec", "fledge"]]
  end

  # Runs +fledge+ (a command) for its version and a build of hello,
  # refusing any download, and runs the built hello with no Ruby in its
  # environment.
  private def hello(env, fledge, chdir, label)
    dist = build(env, fledge, chdir, label)
    unpacked = File.join(chdir, "unpacked-#{label}")
    FileUtils.mkdir_p(unpacked)
    Fledge::Archive.unpack(File.join(dist, "Hello-#{@platform}#{@platform.archive_extension}"), into: unpacked)
    launcher = Dir.glob(File.join(unpacked, "*", @platform.executable("hello")), File::FNM_CASEFOLD).first or
      raise Failure, "#{label}: no hello was built"
    printed = run(bare(env), chdir, launcher, unsetenv_others: true)
    raise Failure, "#{label}: the built hello printed #{printed.inspect}" unless printed.start_with?("Hello from Ruby ")

    @log.puts "#{label}: the built hello printed #{printed}"
  end

  # Writes hello's project for the phone, as hello does for this computer.
  private def project((env, fledge), work)
    dist = build(env, fledge, work, @phone.to_s, @phone.to_s)
    written = File.join(dist, "Hello-#{@phone}")
    raise Failure, "#{@phone}: fledge build wrote no #{written}" unless Dir.exist?(written)

    @log.puts "#{@phone}: fledge build wrote #{written}"
  end

  private def build(env, fledge, chdir, label, *target)
    out = run(env, chdir, *fledge, "--version")
    raise Failure, "#{label}: fledge --version printed #{out.inspect}" unless out == "fledge #{@version}\n"

    dist = File.join(chdir, "dist-#{label}")
    run(env, chdir, *fledge, "build", *target, "-o", dist, HELLO)
    raise Failure, "#{label}: fledge build wrote a cache" if Dir.exist?(File.join(env.fetch("HOME").to_s, ".cache", "fledge"))

    dist
  end

  # An environment with no Ruby in it: only the system's own programs.
  private def bare(env)
    return { "HOME" => env.fetch("HOME").to_s, "PATH" => "/usr/bin:/bin" } unless @platform.windows?

    root = ENV.fetch("SystemRoot", "C:\\Windows")
    { "SystemRoot" => root, "PATH" => File.join(root, "System32"), "USERPROFILE" => env.fetch("HOME").to_s }
  end

  private def run(env, chdir, *command, **)
    out, err, status = Open3.capture3(env, *command, chdir:, **)
    raise Failure, "#{command.join(' ')} failed (#{status}): #{out}#{err}" unless status.success?
    raise Failure, "#{command.join(' ')} downloaded: #{err}" if err.include?("Downloading")

    out
  end
end

if $PROGRAM_NAME == __FILE__
  dir, phone = ARGV
  abort "usage: ruby tasks/gems_check.rb DIR [PHONE]" unless dir
  begin
    GemsCheck.new(dir: File.expand_path(dir), log: $stdout, phone: phone && Fledge::MobilePlatform.find(phone)).call
    puts "✅ fledge #{Fledge::VERSION}'s gems install from #{dir} and build hello#{" for #{phone}" if phone} offline"
  rescue GemsCheck::Failure => e
    abort "❌ #{e.message}"
  end
end
