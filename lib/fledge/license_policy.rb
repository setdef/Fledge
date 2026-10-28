# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  # Which licenses may ship inside a Fledge runtime.
  #
  # Everything Fledge itself copies into an app, its runtime, the app's
  # developer gives to whoever receives the app. The maintainer's rule is
  # that a developer who buys a commercial license must be able to ship an
  # app with no copyleft obligation beyond keeping notices (decisions 1,
  # 8, and 24 in <tt>doc/contributors/decisions.md</tt>): permissive
  # licenses ship freely, the LGPL ships only as a separate shared library
  # whose source Fledge publishes, and the GPL and the AGPL do not ship at
  # all, except Fledge's own files. The rule is for what Fledge puts in an
  # app, not for the app's own gems, whose licenses are the developer's
  # choice and responsibility (2026-10-28; ADR 007).
  #
  # This module holds that policy and judges an SPDX license expression
  # against it, as SPDX 2.3, annex D, reads one: +OR+ takes the least
  # restrictive alternative, +AND+ the most restrictive part, and +WITH+
  # an allowed exception makes the license it follows notice-only. The
  # license audit judges every runtime with it (ADR 004).
  #
  # Use it to ask whether a license may ship.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::LicensePolicy.category("MIT")                      # => :notice_only
  #   Fledge::LicensePolicy.category("Ruby OR BSD-2-Clause")     # => :notice_only
  #   Fledge::LicensePolicy.category("LGPL-2.1-or-later")        # => :shared_library
  #   Fledge::LicensePolicy.category("GPL-3.0-only")             # => :forbidden
  #   Fledge::LicensePolicy.gem_license(["MIT", "GPL-2.0-only"]) # => "MIT OR GPL-2.0-only"
  #--
  # SPDX-SnippetEnd
  #++
  module LicensePolicy
    # Licenses whose only obligation, for an unmodified copy shipped in a
    # proprietary app, is to keep their notices. Artistic-1.0-Perl is the
    # license Ruby's LEGAL offers for win32/win32.c and win32ole.c beside
    # the GPL; unmodified, it asks for its notice and directions to the
    # standard version (section 4a). OFL-1.1 lets fonts ship inside any
    # software; only the fonts stay OFL. blessing is SQLite's dedication
    # to the public domain, which asks nothing at all. LicenseRef-krb5 is
    # MIT Kerberos's NOTICE, whose parts are all BSD, MIT, ISC, and
    # OpenLDAP terms that ask for their notices (krb5's NOTICE at
    # krb5-1.22.2-final), and which no single SPDX identifier names.
    # Unicode-3.0 and Unicode-DFS-2016, the Unicode data licenses that
    # ICU4X's Rust crates and unicode-ident carry, ask that the copyright
    # and permission notice go with every copy, and nothing more. WTFPL,
    # the terminfo crate's, asks nothing at all. bzip2-1.0.6, the license
    # of the bzip2 module in NSIS's makensis, asks that a binary
    # reproduce its notice, and nothing more.
    NOTICE_ONLY = %w[
      0BSD
      Apache-2.0
      Artistic-1.0-Perl
      BSD-2-Clause
      BSD-3-Clause
      BSL-1.0
      bzip2-1.0.6
      CC-BY-2.5
      CC0-1.0
      ISC
      LicenseRef-MinGW-w64-runtime
      LicenseRef-krb5
      MIT
      MIT-0
      OFL-1.1
      PSF-2.0
      PostgreSQL
      Ruby
      Unicode-3.0
      Unicode-DFS-2016
      Unlicense
      WTFPL
      Zlib
      blessing
    ].freeze

    # Licenses whose copyleft reaches only the files they cover: allowed
    # for runtime components that ship as unmodified files, such as the CA
    # bundle, whose source form is the file itself.
    FILE_LEVEL = %w[EPL-2.0 MPL-2.0].freeze

    # Allowed only for a runtime component that ships as its own shared
    # library, with its source published, or that is linked into another
    # component whose source Fledge publishes too.
    SHARED_LIBRARY = %w[LGPL-2.1-only LGPL-2.1-or-later LGPL-3.0-only LGPL-3.0-or-later].freeze
    # Licenses that ask whoever distributes a binary to say where its
    # source is: allowed for a runtime component whose source Fledge
    # publishes beside the runtime and names in its notices, as NSIS's
    # LZMA module's Common Public License asks (CPL-1.0, section 3).
    SOURCE_OFFER = %w[CPL-1.0].freeze

    # Exceptions that make a GPL runtime library's code notice-only, or
    # less, inside a program compiled with it.
    EXCEPTIONS = %w[Bison-exception-2.2 GCC-exception-3.1 LLVM-exception].freeze

    # Names gemspecs use that are not SPDX identifiers, and the SPDX
    # identifiers they mean.
    ALIASES = { "BSDL" => "BSD-2-Clause", "PSFL" => "PSF-2.0" }.freeze

    # The verdicts, from least restrictive to most.
    CATEGORIES = %i[notice_only first_party file_level source_offer shared_library forbidden].freeze

    # The verdict on the SPDX expression +expression+: one of CATEGORIES.
    # With +first_party+, AGPL-3.0-or-later is Fledge's own and
    # <tt>:first_party</tt>; otherwise it is forbidden like any copyleft
    # license not listed above. An empty or malformed expression, an
    # unknown license, and NOASSERTION are forbidden.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::LicensePolicy.category("GPL-3.0-or-later WITH GCC-exception-3.1") # => :notice_only
    #   Fledge::LicensePolicy.category("MIT AND MPL-2.0")                         # => :file_level
    #--
    # SPDX-SnippetEnd
    #++
    def self.category(expression, first_party: false)
      Expression.new(expression, first_party:).category
    end

    # Whether +expression+ asks nothing beyond keeping notices.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::LicensePolicy.notice_only?("BSD-3-Clause") # => true
    #   Fledge::LicensePolicy.notice_only?("LGPL-3.0-only") # => false
    #--
    # SPDX-SnippetEnd
    #++
    def self.notice_only?(expression)
      category(expression) == :notice_only
    end

    # The SPDX expression a gem's specification declares through its
    # +licenses+: each name mapped through ALIASES, alternatives joined by
    # +OR+, since RubyGems lists the licenses a gem may be taken under.
    # NOASSERTION when it declares none.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::LicensePolicy.gem_license(["Ruby", "BSDL"]) # => "Ruby OR BSD-2-Clause"
    #   Fledge::LicensePolicy.gem_license([])               # => "NOASSERTION"
    #--
    # SPDX-SnippetEnd
    #++
    def self.gem_license(licenses)
      return "NOASSERTION" if licenses.empty?

      licenses.map { |license| ALIASES.fetch(license, license) }.uniq.join(" OR ")
    end

    # One SPDX license expression, parsed as it is judged.
    #
    # An expression is a small grammar (SPDX 2.3, annex D), and a verdict
    # needs all of it: a license chosen from alternatives, a license that
    # holds only with another, and a GPL lifted by an exception.
    #
    # This class reads the expression's tokens once, by recursive descent,
    # and judges each license as it reads it.
    #
    # Use it through LicensePolicy.category.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::LicensePolicy::Expression.new("(MIT OR LGPL-2.1-or-later) AND Apache-2.0").category
    #   # => :notice_only
    #--
    # SPDX-SnippetEnd
    #++
    class Expression
      # Parses +text+. With +first_party+, AGPL-3.0-or-later is
      # <tt>:first_party</tt>.
      def initialize(text, first_party: false)
        @tokens = text.to_s.scan(/\(|\)|[A-Za-z0-9.+:-]+/)
        @first_party = first_party
      end

      # The verdict: one of LicensePolicy::CATEGORIES.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::LicensePolicy::Expression.new("(MIT").category # => :forbidden
      #--
      # SPDX-SnippetEnd
      #++
      def category
        return :forbidden if @tokens.empty?

        result = disjunction
        @tokens.empty? ? result : :forbidden
      end

      # Licenses joined by OR: whoever ships may choose any, so the most
      # permissive decides.
      private def disjunction
        operands("OR") { conjunction }.min_by { |category| rank(category) } || :forbidden
      end

      # Licenses joined by AND: each must hold, so the strictest decides.
      private def conjunction
        operands("AND") { exception }.max_by { |category| rank(category) } || :forbidden
      end

      # The verdict on each operand the block reads, for as long as
      # +operator+ joins another.
      private def operands(operator)
        categories = [yield]
        categories << yield while @tokens.first == operator && @tokens.shift
        categories
      end

      # Where +category+ is in CATEGORIES, from most permissive to least.
      private def rank(category)
        CATEGORIES.index(category) || CATEGORIES.size
      end

      private def exception
        license = atom
        return license unless @tokens.first == "WITH"

        @tokens.shift
        EXCEPTIONS.include?(@tokens.shift) ? :notice_only : :forbidden
      end

      private def atom
        token = @tokens.shift
        return classify(token.to_s) unless token == "("

        inner = disjunction
        (@tokens.shift == ")") ? inner : :forbidden
      end

      private def classify(id)
        id = ALIASES.fetch(id, id)
        return :notice_only if NOTICE_ONLY.include?(id)
        return :first_party if @first_party && id == "AGPL-3.0-or-later"
        return :file_level if FILE_LEVEL.include?(id)
        return :source_offer if SOURCE_OFFER.include?(id)
        return :shared_library if SHARED_LIBRARY.include?(id)

        :forbidden
      end
    end
  end
end
