# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "bundler"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "parity"

# The proof before the push of a commit that changes a runtime, or the
# Ruby a parity check compares one with (CONTRIBUTING.md, "Before a
# push"; doc/contributors/design/runtimes.md, "Proving a runtime change
# before its push"): on a computer of the platform, the checks of CI's
# that run an app built from the changed runtime, each by the script or
# task CI runs it with. For a desktop platform: the runtime, built as
# CI's Runtime job builds it unless FLEDGE_RUNTIME_DIR names one; the
# parity check (tasks/parity.rb); Delivery of hello and my_cool_app
# with their parity probes (.github/scripts/deliver.sh), as the
# Delivery jobs run them, and Delivery of fledge build --from
# (prepare-from.sh, then deliver-from.sh), but on Windows (below); and
# the licensing page's integration test with LLVM's readers, as the gate
# runs it. For +android+, on an x86-64 Linux computer with KVM, under
# MISE_ENV=android: the glibc Linux runtime that is the reference, the
# Android runtime, and the mobile parity check and ruby/spec in an
# emulator, as the Mobile apps (Android) and ruby/spec jobs run them.
class RuntimeProof
  ROOT = File.expand_path("..", __dir__)

  # deliver.ps1 has run only on CI's Windows runners, and
  # deliver-from.ps1 needs a runner's RUNNER_TEMP and installs the app it
  # builds, so on Windows the proof runs neither, and leaves Windows
  # Delivery to CI.
  WINDOWS_DELIVERY = "⚠️ Delivery on Windows is CI's: deliver.ps1 and deliver-from.ps1 have run only on its runners"

  # Raised when a step fails, naming it.
  class Failed < StandardError; end

  attr_reader :platform

  # +platform+ is a desktop platform's name, or +android+; +runtimes+
  # the folder that holds the runtime already built, or nil to build it.
  def initialize(platform: Fledge::Platform.local.name, runtimes: ENV.fetch("FLEDGE_RUNTIME_DIR", nil),
    work: File.join(ROOT, "tmp", "proof"), out: $stdout
  )
    @platform = RuntimeBuilder.platform(platform)
    @runtimes = runtimes && File.expand_path(runtimes)
    @work = work
    @out = out
  end

  # The command that builds the runtime for +platform+ (a
  # Fledge::Platform or Mobile::Platform) as CI's Runtime jobs do, or
  # raises Failed with what to do instead where no command here can.
  def self.build_command(platform)
    name = platform.name
    if name == "android" then [RbConfig.ruby, "tasks/runtime_builder.rb", name]
    elsif platform.is_a?(Fledge::Platform) && platform.windows?
      raise Failed, "#{name} runtimes build on Linux or macOS (ruby tasks/runtime_builder.rb #{name}): " \
        "build it there and name its folder in FLEDGE_RUNTIME_DIR"
    elsif platform.is_a?(Fledge::Platform) && platform.musl?
      raise Failed, "#{name} runtimes build in CI's Alpine image (ci.yml, runtime-musl): name a runtime's folder in FLEDGE_RUNTIME_DIR"
    elsif platform.is_a?(Fledge::Platform) && platform.os == "linux"
      ["bash", ".github/scripts/glibc-runtime.sh", name]
    elsif platform.is_a?(Fledge::Platform)
      [RbConfig.ruby, "tasks/runtime_builder.rb", name]
    else
      raise Failed, "no proof here for #{name}"
    end
  end

  # The env ci.yml sets for every job, which its anchors' aliases
  # repeat steps in.
  def self.workflow_env
    YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).fetch("env")
  end

  # Runs every step, and raises Failed at the first that fails.
  def call
    FileUtils.rm_rf(@work)
    FileUtils.mkdir_p(@work)
    (platform.name == "android") ? android : desktop
    @out.puts "✅ the runtime proof of #{platform} passed"
  end

  private def desktop
    runtimes = @runtimes || build(platform)
    env = { "FLEDGE_RUNTIME_DIR" => runtimes, "FLEDGE_RUNTIME_DIR_UNCHECKED" => "1" }
    step("rake parity", env, RbConfig.ruby, "tasks/parity.rb", bundled: true)
    if platform.windows?
      @out.puts WINDOWS_DELIVERY
    else
      deliver(env, runtimes)
      deliver_from(env)
    end
    licensing_page
  end

  # The Android SDK, which the Android runtime's Gradle build of its AAR
  # needs (RuntimeBuilder::Android#pack_aar), then the glibc Linux
  # runtime the Android checks compare with, then the Android runtime,
  # each into tmp/runtime unless FLEDGE_RUNTIME_DIR names a folder that
  # holds both.
  private def android
    raise Failed, "the Android proof needs MISE_ENV=android (CONTRIBUTING.md, \"Android on Linux\")" unless ENV["MISE_ENV"] == "android"

    step("the Android SDK", {}, "bin/android-sdk")
    runtimes = @runtimes || [Fledge::Platform.find("x86_64-linux"), platform].map { |each| build(each) }.last
    env = { "BUNDLETOOL" => capture(RbConfig.ruby, ".github/scripts/fetch_pin.rb", "mobile", "bundletool") }
    %w[tasks/mobile_parity.rb tasks/ruby_spec.rb].each do |task|
      step("#{task} android-build", env, RbConfig.ruby, task, "android-build", runtimes, bundled: true)
      step("#{task} android", env, "bin/android-emulator", "google_apis", "--", RbConfig.ruby, task, "android", bundled: true)
    end
  end

  private def build(each)
    step("the #{each} runtime", {}, *RuntimeProof.build_command(each))
    File.join(ROOT, "tmp", "runtime")
  end

  # Delivery of hello with the parity probe, and of the gem-shaped app
  # with the probe as its program, as the Delivery jobs run them on
  # what the Build job built.
  private def deliver(env, runtimes)
    dist = File.join(@work, "dist")
    bundle_probe = Parity.gem_probe(File.join(@work, "parity-bundle"), name: "ParityBundle", source: Parity.gem_app(platform.name))
    gem_app = Parity.gem_app(platform.name)
    ["examples/hello", Parity::PROBE, bundle_probe, gem_app].each do |app|
      step("fledge build #{File.basename(app)}", env, RbConfig.ruby, "-I", "lib", "exe/fledge", "build", "-o", dist, app)
    end
    hello = capture(reference(runtimes), "examples/hello/main.rb")
    examples_bundle = { "BUNDLE_PATH" => File.join(@work, "examples-bundle") }
    step("bundle install for #{File.basename(gem_app)}", examples_bundle, "bundle", "install", chdir: gem_app)
    expected = capture("bundle", "exec", "ruby", "exe/my_cool_app", env: examples_bundle, chdir: gem_app)
    { "Hello" => ["Parity", hello], "MyCoolApp" => ["ParityBundle", expected] }.each do |name, (probe, line)|
      archive, probe_archive = [name, probe].map { |each| File.join(dist, "#{each}-#{platform}#{platform.archive_extension}") }
      step("deliver.sh #{name}", {}, "sh", ".github/scripts/deliver.sh", archive, probe_archive, line)
    end
  end

  # The Ruby the runtime came from, which hello must print as under
  # ruby main.rb.
  private def reference(runtimes)
    parity = Parity.new(platform:, work: File.join(@work, "reference"), runtimes:)
    FileUtils.mkdir_p(File.join(@work, "reference"))
    parity.unpack_reference
  end

  # Delivery of fledge build --from: the builder app prepare-from.sh
  # builds into dist/, run by deliver-from.sh on the game.
  # The script reads the status a refusal exits with from the
  # workflow's env, which ci.yml sets once for every job.
  private def deliver_from(env)
    step("prepare-from.sh", env, "sh", ".github/scripts/prepare-from.sh", File.join(@work, "from"), platform.name)
    builder = File.join(ROOT, "dist", "Builder-#{platform}#{platform.archive_extension}")
    game = File.join(ROOT, "test", "fixtures", "from", "game")
    refuses = RuntimeProof.workflow_env.slice("FROM_REFUSES_A_BAD_APP_WITH")
    step("deliver-from.sh", refuses, "sh", ".github/scripts/deliver-from.sh", platform.name, builder, game)
  end

  # The licensing page's integration test, with LLVM's readers from the
  # llvm-mingw runtime/sources.yml pins, as the gate runs it, where that
  # pin has a build for this computer.
  private def licensing_page
    host = Fledge::Platform.local.name
    return @out.puts("⚠️ no llvm-mingw for #{host}: the licensing page's test is the gate's, in CI") unless
      YAML.safe_load_file(File.join(ROOT, "runtime", "sources.yml")).dig("llvm-mingw", "hosts", host)

    archive = capture(RbConfig.ruby, ".github/scripts/fetch_pin.rb", "llvm-mingw", "hosts", host)
    llvm = File.join(@work, "llvm-mingw")
    FileUtils.mkdir_p(llvm)
    step("unpack llvm-mingw", {}, "tar", "-xJf", archive, "-C", llvm, "--strip-components=1")
    readers = {
      "FLEDGE_LLVM" => File.join(llvm, "bin"),
      "FLEDGE_REQUIRE_READERS" => "1",
      "TEST" => "test/integration/licensing_page_test.rb",
    }
    step("the licensing page's test", readers, "bundle", "exec", "rake", "test:integration", bundled: true)
  end

  # Runs +command+ from the checkout with +env+, in the environment the
  # rake that started this had before bundle exec (as CI's steps run),
  # or in this one's when +bundled+.
  private def step(label, env, *command, bundled: false, chdir: ROOT)
    @out.puts "== #{label}"
    run = -> { system(env, *command, chdir:) }
    ok = bundled ? run.call : Bundler.with_original_env(&run)
    raise Failed, "#{label} failed: #{command.join(' ')}" unless ok
  end

  private def capture(*command, env: {}, chdir: ROOT)
    out, status = Bundler.with_original_env { Open3.capture2(env, *command, chdir:) }
    raise Failed, "#{command.join(' ')} failed" unless status.success?

    out.strip
  end
end
