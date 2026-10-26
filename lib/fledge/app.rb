# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "entry"
require_relative "error"

module Fledge
  # A Ruby app Fledge can ship: a folder with a main.rb.
  #
  # LÖVE ships a game as a folder with a main.lua, and Fledge ships a
  # Ruby app the same way: the launcher runs <tt>main.rb</tt> with the
  # app's folder on the load path. A folder without one would build
  # into an archive that fails the moment someone runs it, far from the
  # person who could fix it.
  #
  # This class checks the folder when you name it, takes the app's name
  # from the folder's name, and lists the files to ship, leaving out the
  # folder's <tt>.git</tt> history and any build output inside it.
  #
  # Use it to name the app <tt>fledge build</tt> copies into a runtime.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   app = Fledge::App.at("examples/hello")
  #   app.name                    # => "hello"
  #   app.entries.map(&:path)     # => ["main.rb"]
  #
  #   Fledge::App.at("lib")
  #   # raises Fledge::Error: lib has no main.rb. An app is a folder with a main.rb.
  #--
  # SPDX-SnippetEnd
  #++
  class App < Data.define(:root)
    ##
    # :attr_reader: root
    # The app's folder, as an absolute path.

    # Folders inside an app that never ship, such as version control history.
    NEVER_SHIPPED = %w[.git].freeze

    # The app in the folder +path+. Raises Fledge::Error when +path+ is
    # not a folder or has no <tt>main.rb</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::App.at(".").root # => the current directory, absolute
    #--
    # SPDX-SnippetEnd
    #++
    def self.at(path)
      root = File.expand_path(path)
      raise Error, "#{path} is not a folder. An app is a folder with a main.rb." unless File.directory?(root)
      unless File.file?(File.join(root, "main.rb"))
        raise Error, "#{path} has no main.rb. An app is a folder with a main.rb."
      end

      new(root:)
    end

    # The app's name: its folder's name.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::App.at("examples/hello").name # => "hello"
    #--
    # SPDX-SnippetEnd
    #++
    def name
      File.basename(root)
    end

    # The files, folders, and symlinks to ship, with paths relative to
    # the app's folder. Leaves out NEVER_SHIPPED and each path in +skip+
    # (absolute paths, such as the folder builds go to).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::App.at("my_app").entries(skip: [File.expand_path("my_app/dist")])
    #--
    # SPDX-SnippetEnd
    #++
    def entries(skip: [])
      Entry.walk(root, skip: skip + NEVER_SHIPPED.map { |name| File.join(root, name) })
    end
  end
end
