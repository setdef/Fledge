# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class Parity
  # The mobile targets (ADR 011, section 1), on which the mobile parity
  # check (tasks/mobile_parity.rb) runs the probe.
  MOBILE = RuntimeBuilder::Mobile::PLATFORMS.values.flat_map(&:targets).map(&:name).freeze

  # The iOS targets, which leave fiddle out.
  IOS = RuntimeBuilder::Mobile::PLATFORMS.fetch("ios").targets.map(&:name).freeze

  # The folders of a Ruby's platform-specific files, named for its
  # platform, on the desktops the reference runs on and on the phones.
  DESKTOP_ARCH = "(?:arm64-darwin23|x86_64-linux|aarch64-linux)"
  MOBILE_ARCH = "(?:arm64-darwin|x86_64-linux-android|aarch64-linux-android)"

  # What decisions 9 and 10 mean on a phone (ADR 011, section 6): each
  # way an app's Ruby on iOS or Android differs from ruby main.rb on the
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
        "target names for them are ADR 011's."),
    Justification.new(fact: "RUBY_DESCRIPTION", reference: [/\[#{DESKTOP_ARCH}\]"\z/o], app: [/\[#{MOBILE_ARCH}\]"\z/o],
      platforms: MOBILE, reason: "As for RUBY_PLATFORM, which it ends with; the version, date, and revision are the same."),
    Justification.new(fact: "$LOAD_PATH", reference: [%r{\A"<prefix>/lib/ruby/(?:site_ruby/|vendor_ruby/)?4\.0\.0/#{DESKTOP_ARCH}"\z}o],
      app: [%r{\A"<prefix>/lib/ruby/(?:site_ruby/|vendor_ruby/)?4\.0\.0/#{MOBILE_ARCH}"\z}o], platforms: MOBILE,
      reason: "As for RUBY_PLATFORM: Ruby's folders of platform-specific files are named for its platform, in the " \
        "same places and order."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"<prefix>/lib/ruby/4\.0\.0/#{DESKTOP_ARCH}/[^"]+\.(?:bundle|so|rb)"\z}o],
      app: [%r{\A"<prefix>/lib/ruby/4\.0\.0/#{MOBILE_ARCH}/rbconfig\.rb"\z}o, %r{\A"[a-z0-9_/]+\.so"\z}], platforms: MOBILE,
      reason: "A phone's Ruby links every extension in, since iOS loads no code from files, and records each as the " \
        "feature it registers (json/ext/parser.so, encdb.so), where a desktop Ruby records the file it loaded; " \
        "rbconfig.rb is in the folder of Ruby's platform, as for $LOAD_PATH. The same extensions load."),
    Justification.new(fact: "RubyVM::YJIT.enabled?", reference: [/\Afalse\z/], app: [/\Anull\z/], platforms: MOBILE,
      reason: "A phone's Ruby is an interpreter only: iOS gives no app memory it may write code into and run, and " \
        "Ruby builds no JIT for Android (configure.ac at 4.0.9), so RubyVM::YJIT is not defined, as in any Ruby " \
        "built without YJIT. An app that turns YJIT on only where it is defined runs either way."),
    Justification.new(fact: "gems", reference: [/\A"fiddle /], platforms: IOS,
      reason: "The iOS runtime leaves out fiddle, which calls any C function by name, as xord/cruby leaves it out " \
        "of RubySketch's Ruby \"to pass the App Store review\" (ADR 011, section 4)."),
    Justification.new(fact: "requireable", reference: [/\A"fiddle"=/], platforms: IOS, reason: "As for gems."),
  ].freeze
end
