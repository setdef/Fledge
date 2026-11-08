# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  # One gem an app's Gemfile.lock takes from a folder (<tt>gem "foo", path:
  # "../foo"</tt>) that needs more than the project's own files to ship: a
  # folder outside the project, or a gem with an extension to compile.
  #
  # A path gem inside the project, without an extension, ships as part of
  # the project and Bundler finds it where the Gemfile says. Bundler
  # itself sets the other two kinds up. For a folder outside the project
  # it has <tt>bundle cache --all</tt> copy the gem into
  # <tt>vendor/cache/NAME</tt>, and a Bundler that finds that copy uses it
  # in place of the original path (Bundler::Source::Path#specs and
  # #has_app_cache?, at Bundler 4.0.20), even when the original is gone.
  # For an extension it compiles nothing: <tt>bundle exec</tt> loads what
  # the developer compiled in the gem's own <tt>lib</tt>, for their Ruby
  # (Bundler::Source::Path#install). A built app has the runtime's Ruby, so
  # Fledge compiles the extension against it and ships the result in the
  # same place.
  #
  # Use it to carry a path gem from Fledge::Bundle to Fledge::PathPackage.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   gem = Fledge::PathGem.new(name: "greeter", version: "1.0", folder: "/src/greeter", app_path: "vendor/cache/greeter",
  #     glob: "{,*,*/*}.gemspec", inside: false)
  #   gem.to_s # => "greeter 1.0"
  #--
  # SPDX-SnippetEnd
  #++
  class PathGem < Data.define(:name, :version, :folder, :app_path, :glob, :inside)
    ##
    # :attr_reader: name
    # The gem's name.

    ##
    # :attr_reader: version
    # Its version, as text, as the lockfile locks it.

    ##
    # :attr_reader: folder
    # Its folder on this computer, as an absolute path.

    ##
    # :attr_reader: app_path
    # Where the built app's Bundler finds it, relative to the app's own
    # folder: the folder inside the project, or Bundler's
    # <tt>vendor/cache/NAME</tt> for one outside.

    ##
    # :attr_reader: glob
    # The glob its gemspecs are found by, relative to its folder.

    ##
    # :attr_reader: inside
    # Whether the folder is inside the project, and so ships with it.

    # The name RubyGems gives the gem's files: <tt>NAME-VERSION</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.full_name # => "greeter-1.0"
    #--
    # SPDX-SnippetEnd
    #++
    def full_name
      "#{name}-#{version}"
    end

    # A name for the gem's copy while it is compiled, unique among a build's
    # gems.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.scope # => "path-greeter-1.0"
    #--
    # SPDX-SnippetEnd
    #++
    def scope
      "path-#{full_name}"
    end

    # How a person reads the gem's name: <tt>NAME VERSION</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gem.to_s # => "greeter 1.0"
    #--
    # SPDX-SnippetEnd
    #++
    def to_s
      "#{name} #{version}"
    end
  end
end
