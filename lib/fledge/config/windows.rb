# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +windows+: the
    # package identity of its MSIX package.
    #
    # Windows knows an MSIX package by its name and its publisher, a
    # distinguished name such as <tt>CN=Example</tt>: together they
    # make the package family, which updates replace and settings stay
    # with. The publisher must be the subject of the certificate that
    # signs the package, and a package for the Microsoft Store must carry
    # the name and publisher Partner Center reserved for the app, on its
    # Product identity page, which the Store then signs for
    # (Fledge::Msix). No default could be either: a made-up publisher
    # follows the package family for good, as a made-up identifier would
    # (ADR 064). So an app whose +installers+ ask for +msix+ gives
    # +msix_publisher+, as electron-builder's <tt>msix.publisher</tt>
    # and <tt>msix.identityName</tt> are given, and +msix_name+ when the
    # package's name is not its identifier.
    #
    # This class reads the mapping: its +msix_name+, three to fifty
    # letters, digits, periods, and hyphens, and its +msix_publisher+.
    #
    # Use it through Fledge::Config#windows.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   windows:
    #   #     msix_name: 12345Example.CoolApp
    #   #     msix_publisher: CN=1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D
    #   Fledge::Config.load("path/to/project").windows.msix_name # => "12345Example.CoolApp"
    #--
    # SPDX-SnippetEnd
    #++
    class Windows < Data.define(:msix_name, :msix_publisher)
      ##
      # :attr_reader: msix_name
      # The MSIX package's name, or +nil+ for the app's identifier.

      ##
      # :attr_reader: msix_publisher
      # The MSIX package's publisher, a distinguished name, or +nil+ for
      # none.

      # The keys the mapping may hold.
      KEYS = %w[msix_name msix_publisher].freeze

      # A package's name, as the package manifest's schema allows one
      # (ST_PackageName): three to fifty letters, digits, periods, and
      # hyphens.
      NAME = /\A[A-Za-z0-9.-]{3,50}\z/

      # The longest publisher the package manifest's schema allows
      # (ST_Publisher_2010_v2).
      PUBLISHER_MAX = 8192

      # The mapping at +data+'s +windows+ key in the <tt>fledge.yml</tt> at
      # +file+, or +nil+ when it has none. Raises Fledge::Error, naming the
      # file and the key, when it is not a mapping of KEYS with the values
      # they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Windows.from({ "windows" => { "msix_publisher" => "CN=Example" } }, "fledge.yml").msix_publisher
      #   # => "CN=Example"
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data, file)
        item = data["windows"]
        return nil if item.nil?
        raise Error, "#{file}: windows must be a mapping of msix_name and msix_publisher, such as windows: { msix_publisher: CN=Example }" unless item.is_a?(Hash)

        unknown = item.keys - KEYS
        unless unknown.empty?
          raise Error, "#{file}: windows has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows msix_name and msix_publisher."
        end

        new(msix_name: package_name(item["msix_name"], file), msix_publisher: package_publisher(item["msix_publisher"], file))
      end

      # The name at +value+: text of NAME's form, or +nil+.
      private_class_method def self.package_name(value, file) # :nodoc:
        return nil if value.nil?
        return value if value.is_a?(String) && value.match?(NAME)

        raise Error, "#{file}: windows: msix_name must be 3 to 50 letters, digits, periods, and hyphens, as an MSIX package's name is, " \
          "such as Partner Center's Package/Identity/Name, not #{value.inspect}"
      end

      # The publisher at +value+: text of at most PUBLISHER_MAX characters
      # that begins with a distinguished name's attribute, or +nil+.
      private_class_method def self.package_publisher(value, file) # :nodoc:
        return nil if value.nil?
        return value if value.is_a?(String) && value.length <= PUBLISHER_MAX && value.match?(/\A[A-Za-z][A-Za-z0-9.]*=\S/)

        raise Error, "#{file}: windows: msix_publisher must be a distinguished name, such as CN=Example: Partner Center's " \
          "Package/Identity/Publisher, or the subject of the certificate you sign with, not #{value.inspect}"
      end
    end
  end
end
