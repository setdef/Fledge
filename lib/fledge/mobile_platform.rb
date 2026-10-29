# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"
require_relative "platform"

module Fledge
  # A phone's system Fledge builds an app's project for: +ios+, for
  # iPhones and iPads, or +android+.
  #
  # A desktop app is built for the computer <tt>fledge build</tt> runs on
  # (ADR 010). A phone builds nothing, so its app is built on a computer
  # whose tools build for it: Xcode, which runs only on macOS, for iOS; and
  # the Android SDK's Gradle plugin, which Google supports on macOS,
  # Windows, and x86-64 Linux, for Android, as Briefcase, Flutter, React
  # Native, and Tauri build them (ADR 012). Each mobile runtime is one
  # archive for two targets (ADR 011, section 2), named for the system,
  # and no gem publishes a build for any of them, so an app's gems must
  # be pure Ruby, which Bundler picks, as it would on any computer it
  # resolved no build for, with <tt>force_ruby_platform</tt> (ADR 011,
  # section 1).
  #
  # This class names the two, says on which computers each is built, and
  # answers what Fledge::Bundle and Fledge::AppGems ask of a target.
  #
  # Use it for <tt>fledge build ios</tt> and <tt>fledge build android</tt>.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   ios = Fledge::MobilePlatform.find("ios")
  #   ios.to_s                    # => "ios"
  #   ios.lockfile_names          # => ["ruby"]
  #   ios.check_host(Fledge::Platform.find("x86_64-linux"))
  #   # raises Fledge::Error: An iOS app's project is built on a Mac, ...
  #--
  # SPDX-SnippetEnd
  #++
  class MobilePlatform < Data.define(:name)
    ##
    # :attr_reader: name
    # The system's name, as <tt>fledge build</tt> takes it and as its
    # runtime archive is named: <tt>"ios"</tt> or <tt>"android"</tt>.

    # The computers each system's project is built on, by the platform
    # names of Fledge::Platform.
    HOSTS = {
      "ios" => %w[arm64-darwin],
      "android" => %w[arm64-darwin x86_64-linux x64-mingw-ucrt],
    }.freeze

    # What a person calls each system.
    TITLES = { "ios" => "An iOS app's project", "android" => "An Android app's project" }.freeze

    # Why each system's project is built only on HOSTS.
    WHY = {
      "ios" => "with Xcode, which runs only on macOS",
      "android" => "with the Android SDK, which Google supports on macOS, Windows, and x86-64 Linux",
    }.freeze

    # The names of the systems Fledge builds apps' projects for.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobilePlatform.names # => ["ios", "android"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.names
      HOSTS.keys
    end

    # The system named +name+, or +nil+ for any other name.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobilePlatform.find("android").name # => "android"
    #   Fledge::MobilePlatform.find("arm64-darwin") # => nil
    #--
    # SPDX-SnippetEnd
    #++
    def self.find(name)
      new(name:) if HOSTS.key?(name)
    end

    # Raises Fledge::Error unless this system's project is built on the
    # computer whose Fledge::Platform is +host+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobilePlatform.find("android").check_host(Fledge::Platform.find("x86_64-linux")) # => nil
    #--
    # SPDX-SnippetEnd
    #++
    def check_host(host)
      hosts = HOSTS.fetch(name)
      return if hosts.include?(host.name)

      raise Error, "#{TITLES.fetch(name)} is built #{WHY.fetch(name)}, and this computer is #{host}. " \
        "Build it on #{hosts.join(', ')}."
    end

    # Never: a phone is not Windows. Fledge::Bundle asks, for a Gemfile's
    # <tt>platforms:</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobilePlatform.find("ios").windows? # => false
    #--
    # SPDX-SnippetEnd
    #++
    def windows?
      false
    end

    # The names a Gemfile.lock's PLATFORMS section gives this system: only
    # +ruby+, since the app's Bundler resolves its lockfile with
    # <tt>force_ruby_platform</tt>, as on a computer no gem has a build
    # for.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobilePlatform.find("android").lockfile_names # => ["ruby"]
    #--
    # SPDX-SnippetEnd
    #++
    def lockfile_names
      [Gem::Platform::RUBY]
    end

    # Whether the app's Bundler takes only +ruby+ gems: always, on a
    # phone.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobilePlatform.find("ios").force_ruby_platform? # => true
    #--
    # SPDX-SnippetEnd
    #++
    def force_ruby_platform?
      true
    end

    # The system's name.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   "Hello-#{Fledge::MobilePlatform.find('ios')}" # => "Hello-ios"
    #--
    # SPDX-SnippetEnd
    #++
    def to_s
      name
    end
  end
end
