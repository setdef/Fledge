# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  # One gem an app's Gemfile.lock locks for one platform, as RubyGems
  # serves it.
  #
  # A Gemfile.lock names each gem by name, version, and RubyGems platform
  # (<tt>sqlite3 (2.10.2-x64-mingw-ucrt)</tt>), says which server it came
  # from, and, since Bundler 2.6, the SHA-256 of its <tt>.gem</tt> file in
  # its CHECKSUMS section. That is all <tt>fledge build</tt> needs to fetch
  # the very file Bundler would install on that platform, and to check it.
  #
  # Use it to carry a gem from Fledge::Bundle to Fledge::GemFetcher.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   gem = Fledge::LockedGem.new(name: "sqlite3", version: "2.10.2", platform: "x64-mingw-ucrt",
  #     remote: "https://rubygems.org/", sha256: "7fe1bf1a...")
  #   gem.full_name # => "sqlite3-2.10.2-x64-mingw-ucrt"
  #   gem.file_name # => "sqlite3-2.10.2-x64-mingw-ucrt.gem"
  #   gem.url       # => "https://rubygems.org/gems/sqlite3-2.10.2-x64-mingw-ucrt.gem"
  #--
  # SPDX-SnippetEnd
  #++
  class LockedGem < Data.define(:name, :version, :platform, :remote, :sha256)
    ##
    # :attr_reader: name
    # The gem's name.

    ##
    # :attr_reader: version
    # Its version, as text.

    ##
    # :attr_reader: platform
    # Its RubyGems platform, such as <tt>"x86_64-linux-gnu"</tt>, or
    # <tt>"ruby"</tt> for a gem that is the same everywhere.

    ##
    # :attr_reader: remote
    # The server it comes from, ending in <tt>/</tt>.

    ##
    # :attr_reader: sha256
    # The SHA-256 of its <tt>.gem</tt> file, from the lockfile.

    # The name RubyGems gives the gem's files and folders:
    # <tt>NAME-VERSION</tt>, then <tt>-PLATFORM</tt> unless it is +ruby+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   i18n.full_name # => "i18n-1.15.2"
    #--
    # SPDX-SnippetEnd
    #++
    def full_name
      (platform == "ruby") ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
    end

    # The gem's <tt>.gem</tt> file name.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   i18n.file_name # => "i18n-1.15.2.gem"
    #--
    # SPDX-SnippetEnd
    #++
    def file_name
      "#{full_name}.gem"
    end

    # Where the server keeps the <tt>.gem</tt> file, as RubyGems.org and
    # every gem server lay it out: <tt>REMOTE/gems/FILE</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   i18n.url # => "https://rubygems.org/gems/i18n-1.15.2.gem"
    #--
    # SPDX-SnippetEnd
    #++
    def url
      "#{remote.end_with?('/') ? remote : "#{remote}/"}gems/#{file_name}"
    end

    # How a person reads the gem's name: <tt>NAME VERSION</tt>, then the
    # platform in parentheses unless it is +ruby+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   sqlite3.to_s # => "sqlite3 2.10.2 (x64-mingw-ucrt)"
    #--
    # SPDX-SnippetEnd
    #++
    def to_s
      (platform == "ruby") ? "#{name} #{version}" : "#{name} #{version} (#{platform})"
    end
  end
end
