# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +windows+: the
    # package identity of its MSIX package, and how the app comes by
    # Microsoft's Visual C++ runtime.
    #
    # Windows knows an MSIX package by its name and its publisher, a
    # distinguished name such as <tt>CN=Example</tt>: together they
    # make the package family, which updates replace and settings stay
    # with. The publisher must be the subject of the certificate that
    # signs the package, and a package for the Microsoft Store must carry
    # the name and publisher Partner Center reserved for the app, on its
    # Product identity page, which the Store then signs for
    # (Fledge::Msix). No default could be either: a made-up publisher
    # follows the package family for good, as a made-up identifier would.
    # So an app whose +installers+ ask for +msix+ gives
    # +msix_publisher+, as electron-builder's <tt>msix.publisher</tt>
    # and <tt>msix.identityName</tt> are given, and +msix_name+ when the
    # package's name is not its identifier.
    #
    # A gem's DLL built with Visual Studio needs Microsoft's Visual C++
    # runtime (<tt>vcruntime140.dll</tt>, <tt>msvcp140.dll</tt>), which
    # Windows does not include, and which Microsoft lets only its licensed
    # Visual Studio users distribute, a right Fledge cannot check that a
    # developer holds. So Fledge ships it only when the developer says
    # how, in Microsoft's own words for the two ways
    # (Fledge::Linkage::VISUAL_C_RUNTIME): +local+, copied from the
    # building computer into the app, and +central+, the Visual C++
    # Redistributable installed on each computer the app goes to.
    #
    # An app whose Ruby draws with a framework Microsoft ships as a
    # framework package, such as the Windows App Runtime that WinUI 3
    # needs, has its package depend on that package, which the Microsoft
    # Store or App Installer then installs with it, so that the app
    # carries none of Microsoft's files. +msix_dependencies+ lists each
    # as Microsoft's <tt>PackageDependency</tt> element does (Microsoft
    # Learn, "PackageDependency"): its package's name and publisher, and
    # the oldest version of it that serves. Fledge writes the list into an
    # MSIX package only; the setup program, the <tt>.zip</tt>, and the
    # other installers ignore it. An app that runs from one of those finds
    # the framework only if the computer already has it, and its Ruby
    # decides what to do without it.
    #
    # This class reads the mapping: its +msix_name+, three to fifty
    # letters, digits, periods, and hyphens, its +msix_publisher+, its
    # +msix_allow_unsigned+, which is true unless the package is signed
    # after the build or by the Store (Fledge::Msix), its
    # +msix_dependencies+, each a Dependency, and its +visual_c_runtime+,
    # one of VISUAL_C_RUNTIME.
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
    #   #     msix_dependencies:
    #   #       - name: Microsoft.WindowsAppRuntime.2
    #   #         publisher: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
    #   #         min_version: 2.7.0.0
    #   #     visual_c_runtime: local
    #   Fledge::Config.load("path/to/project").windows.msix_name # => "12345Example.CoolApp"
    #   Fledge::Config.load("path/to/project").windows.msix_dependencies.first.min_version # => "2.7.0.0"
    #   Fledge::Config.load("path/to/project").windows.visual_c_runtime # => "local"
    #--
    # SPDX-SnippetEnd
    #++
    class Windows < Data.define(:msix_name, :msix_publisher, :msix_allow_unsigned, :msix_dependencies, :visual_c_runtime)
      ##
      # :attr_reader: msix_name
      # The MSIX package's name, or +nil+ for the app's identifier.

      ##
      # :attr_reader: msix_publisher
      # The MSIX package's publisher, a distinguished name, or +nil+ for
      # none.

      ##
      # :attr_reader: msix_allow_unsigned
      # Whether a package Fledge leaves unsigned may be installed with
      # <tt>Add-AppxPackage -AllowUnsigned</tt>: +true+ by default, and
      # +false+ for a package that is signed after the build or by the
      # Microsoft Store.

      ##
      # :attr_reader: msix_dependencies
      # The framework packages the MSIX package depends on, each a
      # Dependency, in the order <tt>fledge.yml</tt> lists them; empty for
      # none.

      ##
      # :attr_reader: visual_c_runtime
      # How the app comes by Microsoft's Visual C++ runtime when a gem's
      # DLL needs it, one of VISUAL_C_RUNTIME, or +nil+ for not at all, so
      # that fledge build refuses such a gem.

      # The keys the mapping may hold.
      KEYS = %w[msix_name msix_publisher msix_allow_unsigned msix_dependencies visual_c_runtime].freeze

      # A framework package an MSIX package depends on, by the three
      # attributes of the manifest's <tt>PackageDependency</tt> that name
      # one (Microsoft Learn, "PackageDependency"): +name+ and
      # +publisher+ as they stand in the <tt>Identity</tt> of the
      # dependency's package, and +min_version+, the oldest version that
      # serves, four numbers between periods.
      class Dependency < Data.define(:name, :publisher, :min_version)
        ##
        # :attr_reader: name
        # The dependency package's name.

        ##
        # :attr_reader: publisher
        # The dependency package's publisher, a distinguished name.

        ##
        # :attr_reader: min_version
        # The oldest version of the package that serves, such as
        # <tt>2.7.0.0</tt>.

        # The keys an entry may hold.
        KEYS = %w[name publisher min_version].freeze

        # A version as the manifest's schema wants one (ST_Version): four
        # whole numbers between periods, each from 0 to 65535, with no
        # leading zero.
        VERSION = /\A(?<part>0|[1-9]\d{0,3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])(?:\.\g<part>){3}\z/
      end

      # The ways an app may come by the Visual C++ runtime, as Microsoft's
      # "Deployment in Visual C++" names them: +local+, "library files
      # are installed in your application folder together with the
      # executable file", copied from this computer; and +central+,
      # "library DLL files are installed in the Windows\System32
      # directory" by the Visual C++ Redistributable, which each computer
      # the app goes to has.
      VISUAL_C_RUNTIME = %w[local central].freeze

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
        unless item.is_a?(Hash)
          raise Error, "#{file}: windows must be a mapping of msix_name, msix_publisher, msix_allow_unsigned, msix_dependencies, and visual_c_runtime, " \
            "such as windows: { msix_publisher: CN=Example }"
        end

        unknown = item.keys - KEYS
        unless unknown.empty?
          raise Error, "#{file}: windows has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. " \
            "It knows msix_name, msix_publisher, msix_allow_unsigned, msix_dependencies, and visual_c_runtime."
        end

        new(msix_name: package_name(item["msix_name"], file), msix_publisher: package_publisher(item["msix_publisher"], file),
          msix_allow_unsigned: allow_unsigned(item["msix_allow_unsigned"], file),
          msix_dependencies: dependencies(item["msix_dependencies"], file), visual_c_runtime: runtime(item["visual_c_runtime"], file))
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

      # Whether to allow unsigned installs at +value+: true or false, or
      # +nil+, which is true.
      private_class_method def self.allow_unsigned(value, file) # :nodoc:
        return true if value.nil?
        return value if value == true || value == false

        raise Error, "#{file}: windows: msix_allow_unsigned must be true or false, not #{value.inspect}"
      end

      # The dependencies at +value+: a list of mappings of Dependency's
      # KEYS, each with all three and none named twice, or +nil+ for none.
      private_class_method def self.dependencies(value, file) # :nodoc:
        return [] if value.nil?

        entries = (value.is_a?(Array) ? value : [value]).map { |entry| dependency(entry, file, value) }
        names = entries.map(&:name)
        twice = names.find { |name| names.count(name) > 1 }
        raise Error, "#{file}: windows: msix_dependencies lists #{twice} twice, which a package manifest does not allow" if twice

        entries
      end

      # The Dependency at +entry+, one of the list +value+.
      private_class_method def self.dependency(entry, file, value) # :nodoc:
        unless value.is_a?(Array) && entry.is_a?(Hash)
          raise Error, "#{file}: windows: msix_dependencies must be a list of mappings, each with a name, a publisher, and a min_version, " \
            "not #{entry.inspect}"
        end

        unknown = entry.keys - Dependency::KEYS
        unless unknown.empty?
          raise Error, "#{file}: windows: msix_dependencies has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. " \
            "It knows name, publisher, and min_version."
        end

        hints = { "name" => "Microsoft.WindowsAppRuntime.2", "publisher" => "CN=Microsoft Corporation, ...", "min_version" => "1.0.0.0" }
        missing = Dependency::KEYS.find { |key| entry[key].nil? }
        raise Error, "#{file}: windows: msix_dependencies has an entry with no #{missing}, such as #{missing}: #{hints.fetch(missing)}" if missing

        name, publisher = entry.values_at("name", "publisher")
        unless name.is_a?(String) && name.match?(NAME)
          raise Error, "#{file}: windows: msix_dependencies name must be 3 to 50 letters, digits, periods, and hyphens, as the Name of the " \
            "dependency package's Identity is, such as Microsoft.WindowsAppRuntime.2, not #{name.inspect}"
        end
        unless publisher.is_a?(String) && publisher.length <= PUBLISHER_MAX && publisher.match?(/\A[A-Za-z][A-Za-z0-9.]*=\S/)
          raise Error, "#{file}: windows: msix_dependencies publisher must be a distinguished name, such as CN=Example, as the Publisher of " \
            "the dependency package's Identity is, not #{publisher.inspect}"
        end

        Dependency.new(name:, publisher:, min_version: version(entry["min_version"], file))
      end

      # The version at +value+: four numbers between periods.
      private_class_method def self.version(value, file) # :nodoc:
        return value if value.is_a?(String) && value.match?(Dependency::VERSION)

        raise Error, "#{file}: windows: msix_dependencies min_version must be four whole numbers between periods, each at most " \
          "65535, such as 2.7.0.0, not #{value.inspect}"
      end

      # The way at +value+: one of VISUAL_C_RUNTIME, or +nil+.
      private_class_method def self.runtime(value, file) # :nodoc:
        return nil if value.nil?
        return value if value.is_a?(String) && VISUAL_C_RUNTIME.include?(value)

        raise Error, "#{file}: windows: visual_c_runtime must be local, to copy Microsoft's Visual C++ runtime from this computer into " \
          "the app, or central, for computers that have the Visual C++ Redistributable, not #{value.inspect}"
      end
    end
  end
end
