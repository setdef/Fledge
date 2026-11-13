# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../entry"

module Fledge
  class MobileExtensions
    # The Ruby file that stands, in a phone's app, where a desktop has the
    # file of a gem's extension, so that a require of that path finds the
    # extension linked into the app.
    #
    # A desktop's RubyGems copies what an <tt>extconf.rb</tt>'s
    # <tt>make install</tt> built into the gem's first require path
    # (Gem::Ext::ExtConfBuilder.build, lines 45 to 53 of
    # <tt>lib/rubygems/ext/ext_conf_builder.rb</tt> at Ruby
    # 4.1.0-preview1, and its +lib_dir+, line 245 of <tt>builder.rb</tt>),
    # so a gem's <tt>require_relative "adder/adder"</tt> finds
    # <tt>lib/adder/adder.bundle</tt>. Bundler's own templates wrote that
    # <tt>require_relative</tt> for a new gem's extension from 2.2.0
    # through 4.0.0 (<tt>lib/bundler/templates/newgem/lib/newgem.rb.tt</tt>,
    # line 5). A phone's extension is linked in and registered by its
    # feature (ADR 022), and Ruby looks one up only by the name a require
    # was given, never by a path (<tt>search_required</tt>, <tt>load.c</tt>
    # lines 1199 to 1218), so this file at that path requires the
    # feature, as CPython on iOS puts a <tt>.fwork</tt> file where a
    # binary module's <tt>.so</tt> was (<tt>Doc/using/ios.rst</tt>, lines
    # 90 to 115 at v3.13.0).
    #
    # Use Stub.for for each extension an <tt>extconf.rb</tt> builds.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions::Stub.for(package, "adder/adder", root:, gem_dir: "lib/ruby/gems/4.1.0+5").path
    #   # => "lib/ruby/gems/4.1.0+5/gems/adder-1.0.0/lib/adder/adder.rb"
    #--
    # SPDX-SnippetEnd
    #++
    module Stub
      # The file for +package+'s extension +feature+, as an Entry with its
      # path below the runtime's gem folder +gem_dir+; or +nil+ where the
      # gem's files in +root+ have a Ruby file of that name, which a
      # require of the path finds first on a desktop too, since Ruby tries
      # <tt>.rb</tt> before the extension's (<tt>loadable_ext</tt>,
      # <tt>load.c</tt> lines 35 to 38), as bigdecimal's
      # <tt>lib/bigdecimal.rb</tt> is.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Stub.for(package, "native", root:, gem_dir:) # => nil, for a gem with lib/native.rb
      #--
      # SPDX-SnippetEnd
      #++
      def self.for(package, feature, root:, gem_dir:)
        # The gemspec's own first require path: require_paths puts the
        # extension folder, an absolute path, before it.
        folder = package.spec.require_paths.find { |path| !File.absolute_path?(path) }
        return nil if folder.nil?

        path = File.join(folder, "#{feature}.rb")
        return nil if File.exist?(File.join(root, path))

        Entry.file("#{package.installed_path(gem_dir)}/#{path}", source(feature))
      end

      # The file's Ruby: a require of +feature+ by its <tt>.so</tt> name,
      # which Ruby looks up among the linked extensions however the phone
      # names its own (<tt>DLEXT</tt> is <tt>bundle</tt> on iOS), and which
      # no <tt>.rb</tt> answers, so it cannot find this file again.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Stub.source("adder/adder").lines.last # => "require \"adder/adder.so\"\n"
      #--
      # SPDX-SnippetEnd
      #++
      def self.source(feature)
        <<~RUBY
          # frozen_string_literal: true

          # Written by fledge build. On a phone, the extension #{feature} is
          # linked into the app, not a file here; this file stands where a
          # desktop has the extension's file, so that a require of this path,
          # such as require_relative, loads the extension as it does there.
          require #{"#{feature}.so".dump}
        RUBY
      end
    end
  end
end
