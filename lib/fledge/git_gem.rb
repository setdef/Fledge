# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  # One gem an app's Gemfile.lock takes from a git repository, at the
  # revision it locks.
  #
  # A Gemfile can take a gem from git (<tt>gem "ferro-idna", git: URL,
  # tag: "ferro-idna/v0.1.0.pre.1", glob: "gems/*/*.gemspec"</tt>), and
  # its lockfile records, in a GIT section, the repository, the revision
  # the tag or branch pointed to when it was locked, and the glob its
  # gemspecs are found by. The revision pins the gem as a checksum pins a
  # <tt>.gem</tt>, so it is what Fledge fetches, and nothing else
  # (ADR 006).
  #
  # Bundler keeps a git gem's checkout at
  # <tt>GEM_DIR/bundler/gems/SCOPE</tt> and its extensions under
  # <tt>GEM_DIR/bundler/gems/extensions</tt>, and a built app's Bundler
  # finds it there, so this class names SCOPE as Bundler does.
  #
  # Use it to carry a git gem from Fledge::Bundle to Fledge::GitCheckout.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   gem = Fledge::GitGem.new(name: "ferro-idna", version: "0.1.0.pre.1", uri: "https://github.com/setdef/Ferro",
  #     revision: "21a106d0c0d6c7f822476ab12102f31efcaa17d1", glob: "gems/*/*.gemspec", ref: "tag ferro-idna/v0.1.0.pre.1")
  #   gem.scope     # => "Ferro-21a106d0c0d6"
  #   gem.full_name # => "ferro-idna-0.1.0.pre.1"
  #   gem.to_s      # => "ferro-idna 0.1.0.pre.1"
  #--
  # SPDX-SnippetEnd
  #++
  class GitGem < Data.define(:name, :version, :uri, :revision, :glob, :ref)
    ##
    # :attr_reader: name
    # The gem's name.

    ##
    # :attr_reader: version
    # Its version, as text, as the lockfile locks it.

    ##
    # :attr_reader: uri
    # The repository, as the lockfile names it.

    ##
    # :attr_reader: revision
    # The commit the lockfile locks, in full.

    ##
    # :attr_reader: glob
    # Where the repository's gemspecs are, relative to its top.

    ##
    # :attr_reader: ref
    # What the Gemfile asked for, such as <tt>tag v1.0</tt>, or +nil+.

    # The name RubyGems gives the gem's files: <tt>NAME-VERSION</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.full_name # => "ferro-idna-0.1.0.pre.1"
    #--
    # SPDX-SnippetEnd
    #++
    def full_name
      "#{name}-#{version}"
    end

    # The folder Bundler checks the revision out into, in
    # <tt>bundler/gems</tt>: the repository's base name and the first
    # twelve characters of the revision.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.scope # => "Ferro-21a106d0c0d6"
    #--
    # SPDX-SnippetEnd
    #++
    def scope
      "#{base_name}-#{revision[0, 12]}"
    end

    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT
    # SPDX-SnippetCopyrightText: 2010-2019 André Arko, 2009 Engine Yard
    # SPDX-SnippetComment: Bundler::Source::Git#base_name, adapted from
    #   bundler/source/git.rb at Bundler 4.0.20 (lines 370 to 372).
    #++
    # The repository's name without its scheme, host, folders, or .git.
    private def base_name
      File.basename(uri.sub(%r{^(\w+://)?([^/:]+:)?(//\w*/)?(\w*/)*}, ""), ".git")
    end
    #--
    # SPDX-SnippetEnd
    #++

    # Where the gem came from, for a person to read: the repository, the
    # revision, and what the Gemfile asked for.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.url
    #   # => "https://github.com/setdef/Ferro at 21a106d0c0d6c7f822476ab12102f31efcaa17d1 (tag ferro-idna/v0.1.0.pre.1)"
    #--
    # SPDX-SnippetEnd
    #++
    def url
      "#{uri} at #{revision}#{" (#{ref})" if ref}"
    end

    # How a person reads the gem's name: <tt>NAME VERSION</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.to_s # => "ferro-idna 0.1.0.pre.1"
    #--
    # SPDX-SnippetEnd
    #++
    def to_s
      "#{name} #{version}"
    end
  end
end
