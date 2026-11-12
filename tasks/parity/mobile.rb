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

  # The folders of a Ruby's platform-specific files, named for its
  # platform, on the desktops the reference runs on and on the phones.
  DESKTOP_ARCH = "(?:arm64-darwin23|x86_64-linux|aarch64-linux)"
  MOBILE_ARCH = "(?:arm64-darwin|x86_64-linux-android|aarch64-linux-android)"

  # What decisions 9 and 10 mean on a phone (doc/contributors/design/phone-projects.md,
  # "Parity on a phone"): each way an app's Ruby on iOS or Android differs from ruby main.rb on the
  # desktop that runs its simulator, and why each is right.
  MOBILE_JUSTIFIED = [
    Justification.new(fact: "ENV", reference: [/./], app: [/./], platforms: MOBILE,
      reason: "iOS and Android start an app with an environment of their own, which no person sets: the system's " \
        "HOME and TMPDIR inside the app's own container, and on iOS the Simulator's variables, with nothing of a " \
        "shell's. The runtime adds SSL_CERT_FILE, naming its CA certificates for OpenSSL, as rv-ruby's Ruby adds " \
        "PORTABLE_RUBY_SSL_CERT_FILE, and on Android HOME, the app's files folder, as iOS gives every app one."),
    Justification.new(fact: "child ENV", reference: [/./], app: [/\A"Errno::/], platforms: MOBILE,
      reason: "An app on a phone starts no programs: iOS lets no app run one, and Android lets no app run a file " \
        "of its own (W^X, from target API 29), so a phone has no Ruby program to start, and spawning RbConfig.ruby " \
        "fails as it does where Ruby is missing."),
    Justification.new(fact: "RbConfig.ruby is a program", reference: [/\Atrue\z/], app: [/\Afalse\z/], platforms: MOBILE,
      reason: "As for child ENV: a phone's runtime is a library inside the app, with no bin/ruby, since nothing on a " \
        "phone could run it; RbConfig.ruby names where it would be."),
    Justification.new(fact: "RbConfig.ruby runs", reference: [/\A"42"\z/], app: [/\A"Errno::/], platforms: MOBILE,
      reason: "As for child ENV."),
    Justification.new(fact: "RUBY_PLATFORM", reference: [/\A"#{DESKTOP_ARCH}"\z/o], app: [/\A"#{MOBILE_ARCH}"\z/o], platforms: MOBILE,
      reason: "Ruby names the platform it was built for: rv-ruby's for macOS 14 (darwin23) or glibc Linux, a " \
        "phone's for iOS, which Ruby calls arm64-darwin, or Android, which it calls ARCH-linux-android. Fledge's " \
        "target names for them are ADR 057's."),
    Justification.new(fact: "RUBY_DESCRIPTION", reference: [/\[#{DESKTOP_ARCH}\]"\z/o], app: [/\[#{MOBILE_ARCH}\]"\z/o],
      platforms: MOBILE, reason: "As for RUBY_PLATFORM, which it ends with; the version, date, and revision are the same."),
    Justification.new(fact: "$LOAD_PATH", reference: [%r{\A"<prefix>/lib/ruby/(?:site_ruby/|vendor_ruby/)?#{ABI}/#{DESKTOP_ARCH}"\z}o],
      app: [%r{\A"<prefix>/lib/ruby/(?:site_ruby/|vendor_ruby/)?#{ABI}/#{MOBILE_ARCH}"\z}o], platforms: MOBILE,
      reason: "As for RUBY_PLATFORM: Ruby's folders of platform-specific files are named for its platform, in the " \
        "same places and order."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"<prefix>/lib/ruby/#{ABI}/#{DESKTOP_ARCH}/[^"]+\.(?:bundle|so|rb)"\z}o],
      app: [%r{\A"<prefix>/lib/ruby/#{ABI}/#{MOBILE_ARCH}/rbconfig\.rb"\z}o, %r{\A"[a-z0-9_/]+\.so"\z}], platforms: MOBILE,
      reason: "A phone's Ruby links every extension in, since iOS loads no code from files, and records each as the " \
        "feature it registers (json/ext/parser.so, encdb.so), where a desktop Ruby records the file it loaded; " \
        "rbconfig.rb is in the folder of Ruby's platform, as for $LOAD_PATH. The same extensions load."),
    Justification.new(fact: "RubyVM::YJIT.enabled?", reference: [/\Afalse\z/], app: [/\Anull\z/], platforms: MOBILE,
      reason: "A phone's Ruby is an interpreter only: iOS gives no app memory it may write code into and run, and " \
        "Ruby builds no JIT for Android (configure.ac at 4.1.0-preview1), so RubyVM::YJIT is not defined, as in any Ruby " \
        "built without YJIT. An app that turns YJIT on only where it is defined runs either way."),
    Justification.new(fact: "$stdout.sync", reference: [/\Afalse\z/], app: [/\Atrue\z/], platforms: MOBILE,
      reason: "A phone has no terminal: an app's standard output is the pipe the embedding API reads into the " \
        "system log, where a developer watches the app run. Ruby writes through to a terminal but buffers a pipe " \
        "until the program ends, so the runtime puts $stdout in sync mode, which writes each line when it is " \
        "printed, as under ruby main.rb in a terminal, and as Briefcase's iOS host unbuffers Python's streams."),
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
    Justification.new(fact: "requireable", reference: [/\A"io-nonblock"="loads"\z/],
      app: [/\A"io-nonblock"="loads, but not its gem"\z/], platforms: MOBILE,
      reason: "TEMPORARY, a defect to fix: a phone's Ruby is built out of its source folder, and tool/rbinstall.rb's " \
        "load_gemspec (lines 921 to 928 at 4.1.0-preview1) prefixes lib/ to each .rb file a default gem's gemspec " \
        "lists that it finds relative to the build folder, not the source, so io-nonblock's specification lists " \
        "lib/ext/io/nonblock/extconf.rb. RubyGems then takes the specification for one whose files sit under lib/, " \
        "and its register_default_spec skips io/nonblock.bundle, which is not under lib/ and has a slash " \
        "(lib/rubygems.rb, lines 1312 to 1342), so require \"io/nonblock\" loads the extension without " \
        "activating the default gem."),
  ].freeze
end
