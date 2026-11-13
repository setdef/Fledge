# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class Parity
  # The mobile targets (ADR 057), on which the mobile parity
  # check (tasks/mobile_parity.rb) runs the probe.
  MOBILE = RuntimeBuilder::Mobile::PLATFORMS.values.flat_map(&:targets).map(&:name).freeze

  # The iOS targets, which leave fiddle out.
  IOS = RuntimeBuilder::Mobile::PLATFORMS.fetch("ios").targets.map(&:name).freeze

  # The Android targets, whose runtime has a ruby program (ADR 069).
  ANDROID = RuntimeBuilder::Mobile::PLATFORMS.fetch("android").targets.map(&:name).freeze

  # The folders of a Ruby's platform-specific files, named for its
  # platform, on the desktops the reference runs on and on the phones.
  DESKTOP_ARCH = "(?:arm64-darwin23|x86_64-linux|aarch64-linux)"
  MOBILE_ARCH = "(?:arm64-darwin|x86_64-linux-android|aarch64-linux-android)"

  # What starting a program raises on iOS: ENOENT in the Simulator,
  # where the program RbConfig.ruby names is missing, and EPERM on a
  # device, where iOS refuses to start any (doc/phones.md).
  ERRNO_SPAWN = /\A"Errno::(?:ENOENT|EPERM): /

  # What decisions 9 and 10 mean on a phone (doc/contributors/design/phone-projects.md,
  # "Parity on a phone"): each way an app's Ruby on iOS or Android differs from ruby main.rb on the
  # desktop that runs its simulator, and why each is right.
  MOBILE_JUSTIFIED = [
    *["ENV", "child ENV"].map do |fact|
      Justification.new(fact:, app: [/\A"HOME"="<home>"\z/], platforms: ANDROID,
        reason: "The check compares a phone app's ENV, and a child's, with the environment the system gave the " \
          "app, which its host logs (MobileParity::Environment): a phone starts an app with an environment of its " \
          "own, and no person's shell. Android gives an app no HOME, so FledgeRuby sets it to the app's files " \
          "folder, as iOS gives every app one, so that Dir.home is a folder the app may write, as every desktop's " \
          "is; a Ruby the app starts, the Android runtime's ruby program (ADR 069), inherits it.")
    end,
    Justification.new(fact: "child ENV", reference: [/\A"[^"]+"=/], app: [ERRNO_SPAWN], platforms: IOS,
      reason: "An app on iOS starts no programs, since iOS lets no app run one, so the iOS runtime has no Ruby " \
        "program to start, and spawning RbConfig.ruby fails as it does where Ruby is missing (ENOENT in the " \
        "Simulator) or as iOS refuses it (EPERM on a device), and the child sees none of the environment."),
    Justification.new(fact: "RbConfig.ruby is a program", reference: [/\Atrue\z/], app: [/\Afalse\z/], platforms: IOS,
      reason: "As for child ENV: the iOS runtime is a library inside the app, with no bin/ruby, since nothing on " \
        "iOS could run it; RbConfig.ruby names where it would be."),
    Justification.new(fact: "RbConfig.ruby runs", reference: [/\A"42"\z/], app: [ERRNO_SPAWN], platforms: IOS,
      reason: "As for child ENV."),
    Justification.new(fact: "RUBY_PLATFORM", reference: [/\A"#{DESKTOP_ARCH}"\z/o], app: [/\A"#{MOBILE_ARCH}"\z/o], platforms: MOBILE,
      reason: "Ruby names the platform it was built for: rv-ruby's for macOS 14 (darwin23) or glibc Linux, a " \
        "phone's for iOS, which Ruby calls arm64-darwin, or Android, which it calls ARCH-linux-android. Fledge's " \
        "target names for them are ADR 057's."),
    Justification.new(fact: "RUBY_DESCRIPTION", reference: [/\A(?<version>"[^"]*) \[#{DESKTOP_ARCH}\]"\z/o],
      app: [/\A(?<version>"[^"]*) \[#{MOBILE_ARCH}\]"\z/o],
      platforms: MOBILE, reason: "As for RUBY_PLATFORM, which it ends with; the version, date, and revision are the same."),
    Justification.new(fact: "$LOAD_PATH", reference: [%r{\A"<prefix>/lib/ruby/(?<folder>(?:site_ruby/|vendor_ruby/)?#{ABI})/#{DESKTOP_ARCH}"\z}o],
      app: [%r{\A"<prefix>/lib/ruby/(?<folder>(?:site_ruby/|vendor_ruby/)?#{ABI})/#{MOBILE_ARCH}"\z}o], platforms: MOBILE,
      reason: "As for RUBY_PLATFORM: Ruby's folders of platform-specific files are named for its platform, in the " \
        "same places and order."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"<prefix>/lib/ruby/#{ABI}/#{DESKTOP_ARCH}/(?:enc/)?(?<feature>[^"]+)\.(?:bundle|so)"\z}o],
      app: [%r{\A"(?<feature>[a-z0-9_/]+)\.so"\z}], platforms: MOBILE,
      reason: "A phone's Ruby links every extension in, since iOS loads no code from files, and records each as the " \
        "feature it registers (json/ext/parser.so, encdb.so, with no enc/), where a desktop Ruby records the file it " \
        "loaded. The same extensions load."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"<prefix>/lib/ruby/(?<abi>#{ABI})/#{DESKTOP_ARCH}/rbconfig\.rb"\z}o],
      app: [%r{\A"<prefix>/lib/ruby/(?<abi>#{ABI})/#{MOBILE_ARCH}/rbconfig\.rb"\z}o], platforms: MOBILE,
      reason: "As for $LOAD_PATH: rbconfig.rb is in the folder of Ruby's platform."),
    Justification.new(fact: "RubyVM::YJIT.enabled?", reference: [/\Afalse\z/], app: [/\Anull\z/], platforms: MOBILE,
      reason: "A phone's Ruby is an interpreter only: iOS gives no app memory it may write code into and run, and " \
        "Ruby builds no JIT for Android (configure.ac at 4.1.0-preview1), so RubyVM::YJIT is not defined, as in any Ruby " \
        "built without YJIT. An app that turns YJIT on only where it is defined runs either way."),
    Justification.new(fact: "$stdout writes through", reference: [/\Afalse\z/], app: [/\Atrue\z/], platforms: MOBILE,
      reason: "A phone has no terminal: an app's standard output is the pipe the embedding API reads into the " \
        "system log, where a developer watches the app run. Ruby writes through to a terminal but buffers a pipe " \
        "until the program ends, so the runtime has $stdout write through as to a terminal, with Ruby's own " \
        "FMODE_TTY, as under ruby main.rb in one, and as Briefcase's iOS host unbuffers Python's streams; " \
        "$stdout.sync and $stdout.tty? stay false, as under ruby main.rb with its output to a pipe."),
    Justification.new(fact: "gems", reference: [/\A"fiddle /], platforms: IOS,
      reason: "The iOS runtime leaves out fiddle, which calls any C function by name, as xord/cruby leaves it out " \
        "of RubySketch's Ruby \"to pass the App Store review\" (ADR 058)."),
    Justification.new(fact: "requireable", reference: [/\A"fiddle"=/], platforms: IOS, reason: "As for gems."),
    Justification.new(fact: "gems", app: [/\A"win32-registry /], platforms: MOBILE,
      reason: "Ruby's own install puts every bundled gem it can in a Ruby it builds from source, as the phones' " \
        "runtimes are, win32-registry among them, which only Windows can use; rv-ruby's builds, which the " \
        "desktop's ruby main.rb runs, leave it out."),
    Justification.new(fact: "requireable", app: [/\A"win32-registry"=/], platforms: MOBILE,
      reason: "As for win32-registry's gem: it calls Windows' kernel32.dll through fiddle, so it loads nowhere else."),
  ].freeze
end
