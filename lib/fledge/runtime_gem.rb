# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "platform"

module Fledge
  # The gem that carries one target's runtime (ADR 030).
  #
  # A release's runtimes travel in gems as well as in its GitHub Release,
  # so that a Fledge installed from a gem server builds an app with no
  # download. A desktop platform's runtime is in the gem
  # <tt>fledge-runtime</tt>, published once per platform as nokogiri and
  # sorbet-static publish their builds, and the plain <tt>fledge</tt> gem
  # depends on it, so RubyGems and Bundler install the one for the
  # computer they install on. A phone's runtime is built for on more than
  # one kind of computer and is wanted by few, so it is a gem of its own
  # for any computer, <tt>fledge-runtime-ios</tt> or
  # <tt>fledge-runtime-android</tt>, that a developer adds.
  #
  # Each gem holds its runtime's release assets, byte for byte, in its
  # +runtime+ folder, so the SHA-256 that Fledge pins for each asset (ADR
  # 014) checks it there too.
  #
  # This class names the gem and the RubyGems platform for each target.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   gem = Fledge::RuntimeGem.for(Fledge::Platform.find("x86_64-linux"))
  #   gem.name     # => "fledge-runtime"
  #   gem.platform # => "x86_64-linux-gnu"
  #
  #   Fledge::RuntimeGem.for(Fledge::MobilePlatform.find("ios")).name # => "fledge-runtime-ios"
  #--
  # SPDX-SnippetEnd
  #++
  class RuntimeGem < Data.define(:target)
    ##
    # :attr_reader: target
    # The target's name, as Fledge::Platform or Fledge::MobilePlatform
    # names it, such as <tt>"x86_64-linux"</tt> or <tt>"ios"</tt>.

    # The name of the gem that carries every desktop platform's runtime.
    NAME = "fledge-runtime"

    # The folder in each gem that holds the runtime's release assets.
    FOLDER = "runtime"

    # The gem for +target+, a Fledge::Platform or Fledge::MobilePlatform.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RuntimeGem.for(Fledge::Platform.local).target # => "arm64-darwin"
    #--
    # SPDX-SnippetEnd
    #++
    def self.for(target)
      new(target: target.to_s)
    end

    # The gem's name: <tt>fledge-runtime</tt> for a desktop platform, and
    # <tt>fledge-runtime-ios</tt> or <tt>fledge-runtime-android</tt> for a
    # phone.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RuntimeGem.new(target: "android").name # => "fledge-runtime-android"
    #--
    # SPDX-SnippetEnd
    #++
    def name
      desktop? ? NAME : "#{NAME}-#{target}"
    end

    # The gem's RubyGems platform. A phone's gem is +ruby+, for any
    # computer. A desktop platform's is its Fledge name, but glibc Linux's
    # carries <tt>-gnu</tt>, as nokogiri's and tailwindcss-ruby's do:
    # RubyGems installs a gem for plain <tt>x86_64-linux</tt> on musl Linux
    # too (Gem::Platform#===), and one for <tt>x86_64-linux-gnu</tt> only
    # on glibc.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RuntimeGem.new(target: "aarch64-linux").platform      # => "aarch64-linux-gnu"
    #   Fledge::RuntimeGem.new(target: "aarch64-linux-musl").platform # => "aarch64-linux-musl"
    #   Fledge::RuntimeGem.new(target: "ios").platform                # => "ruby"
    #--
    # SPDX-SnippetEnd
    #++
    def platform
      return "ruby" unless desktop?

      target.end_with?("-linux") ? "#{target}-gnu" : target
    end

    # Whether +target+ is a desktop platform, whose gem
    # <tt>fledge</tt> depends on.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RuntimeGem.new(target: "x64-mingw-ucrt").desktop? # => true
    #--
    # SPDX-SnippetEnd
    #++
    def desktop?
      Platform.names.include?(target)
    end
  end
end
