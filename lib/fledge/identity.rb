# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"
require_relative "config"
require_relative "error"
require_relative "icon"

module Fledge
  # Who an app says it is, to the operating system and the person who
  # runs it.
  #
  # The name in a Dock, a taskbar, Task Manager, and a Start menu, the
  # icon beside it, the version and publisher in a Properties dialog, and
  # the identifier macOS and Windows check before they let an app send a
  # notification are all the developer's to decide (decision 18), and
  # whether the app opens windows or runs in a terminal decides which of
  # them each operating system asks for.
  #
  # This class gathers them from the project: what <tt>fledge.yml</tt>
  # says (Fledge::Config), and otherwise the gemspec's version and
  # authors, and the app's name, as Tauri's bundler takes a product's
  # version from its Cargo.toml. A windowed app needs an identifier, as
  # Tauri, Briefcase, and Flatpak require one, since macOS knows a bundle
  # and Windows an AppUserModelID by it, and no default could be one the
  # developer owns: the build fails, suggesting one.
  #
  # Use it through Fledge::App#identity.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   identity = Fledge::App.at("examples/my_cool_app/exe/my_cool_app").identity
  #   identity.version   # => "0.1.0", the gemspec's
  #   identity.publisher # => "Kerrick Long", its authors
  #   identity.windowed? # => false
  #--
  # SPDX-SnippetEnd
  #++
  class Identity < Data.define(:name, :kind, :identifier, :version, :publisher, :copyright, :icon)
    ##
    # :attr_reader: name
    # The app's name, as people see it.

    ##
    # :attr_reader: kind
    # +console+ or +windowed+ (Config::KINDS).

    ##
    # :attr_reader: identifier
    # The app's reverse-DNS identifier, or +nil+ for a console app that
    # has none.

    ##
    # :attr_reader: version
    # The app's version, such as <tt>"1.2.3"</tt>.

    ##
    # :attr_reader: publisher
    # Who publishes the app, or +nil+ when nothing says.

    ##
    # :attr_reader: copyright
    # The app's copyright notice, or +nil+ for none.

    ##
    # :attr_reader: icon
    # The app's Fledge::Icon, or +nil+ for none.

    # The version of an app that names none, and has no gemspec.
    DEFAULT_VERSION = "0.0.0"

    # The identity of the app named +name+ in the project at +root+, from
    # its +config+ and its +gemspec+, if it has one. Raises Fledge::Error
    # for a windowed app with no identifier, or an icon Fledge cannot use.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Identity.from(config: Fledge::Config.none, gemspec: nil, name: "Hello", root: "examples/hello").version
    #   # => "0.0.0"
    #--
    # SPDX-SnippetEnd
    #++
    def self.from(config:, gemspec:, name:, root:)
      kind = config.kind || "console"
      identifier = config.identifier
      if identifier.nil? && kind == "windowed"
        raise Error, "#{File.join(root, Config::FILE)}: a windowed app needs an identifier, which macOS and Windows know it by: " \
          "a reverse-DNS name of a domain you control, such as identifier: #{suggestion(gemspec, name)}"
      end

      authors = gemspec ? gemspec.authors.reject(&:empty?) : [] # : Array[String]
      new(
        name:, kind:, identifier:,
        version: config.version || gemspec&.version&.to_s || DEFAULT_VERSION,
        publisher: config.publisher || (authors.empty? ? nil : authors.join(", ")),
        copyright: config.copyright,
        icon: config.icon && Icon.read(File.expand_path(config.icon.to_s, root))
      )
    end

    # An identifier to suggest: Flathub's for a project hosted on GitHub
    # (<tt>io.github.OWNER.NAME</tt>), or else an example one.
    private_class_method def self.suggestion(gemspec, name) # :nodoc:
      owner = gemspec&.homepage.to_s[%r{\Ahttps?://github\.com/([A-Za-z0-9-]+)/}, 1]
      app = name.gsub(/[^A-Za-z0-9-]/, "")
      app = "MyCoolApp" if app.empty?
      owner ? "io.github.#{owner}.#{app}" : "com.example.#{app}"
    end

    # Whether the app opens its own windows and shows no terminal.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   identity.windowed? # => true for kind: windowed
    #--
    # SPDX-SnippetEnd
    #++
    def windowed?
      kind == "windowed"
    end
  end
end
