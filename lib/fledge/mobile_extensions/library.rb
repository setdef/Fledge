# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../git_package"
require_relative "../path_package"

module Fledge
  class MobileExtensions
    # An extension built for an Android target as the shared object
    # mkmf makes on a desktop, which Ruby loads from a file: its feature,
    # its file, the linker flags its extconf.rb asked for, and the paths,
    # relative to the app's Ruby root, where a desktop's RubyGems leaves
    # its file, at which the app links to it (.links).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   library.feature # => "adder/adder"
    #   library.links   # => ["app/vendor/cache/adder/lib/adder/adder.so"]
    #--
    # SPDX-SnippetEnd
    #++
    class Library < Data.define(:feature, :path, :flags, :links)
      ##
      # :attr_reader: feature
      # The name <tt>require</tt> asks for, such as <tt>"adder/adder"</tt>.

      ##
      # :attr_reader: path
      # The shared object's path.

      ##
      # :attr_reader: flags
      # The linker flags its extconf.rb asked for (Linking.link_flags).

      ##
      # :attr_reader: links
      # The paths, relative to the app's Ruby root, where a desktop has
      # its file.

      # Where a desktop's RubyGems leaves the file of +package+'s extension
      # +feature+, for the Ruby of the gem platform +platform+ whose gem
      # folder is +gem_dir+, relative to the Ruby root, as the gem's
      # entries are. RubyGems copies it into the gem's first require path,
      # which Ruby searches first, as Gem.install_extension_in_lib has it
      # by default, and leaves it in the gem's extension folder
      # (Gem::Ext::ExtConfBuilder.build); Bundler builds a git gem's
      # under its own extension folder, and a path gem's in none.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Library.links(package, "adder/adder", platform: "x86_64-linux-android", gem_dir: "lib/ruby/gems/4.1.0+5")
      #   # => ["lib/ruby/gems/4.1.0+5/gems/adder-1.0.0/lib/adder/adder.so",
      #   #     "lib/ruby/gems/4.1.0+5/extensions/x86_64-linux-android/4.1.0+5-static/adder-1.0.0/adder/adder.so"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.links(package, feature, platform:, gem_dir:)
        file = "#{feature}.so"
        folder = package.spec.require_paths.find { |path| !File.absolute_path?(path) }
        api = "#{File.basename(gem_dir)}-static"
        extensions = case package
                     when PathPackage then nil
                     when GitPackage then "#{gem_dir}/bundler/gems/extensions/#{platform}/#{api}/#{package.scope}"
                     else "#{gem_dir}/extensions/#{platform}/#{api}/#{package.spec.full_name}"
        end
        [*(folder ? ["#{package.installed_path(gem_dir)}/#{folder}/#{file}"] : []), *(extensions ? ["#{extensions}/#{file}"] : [])]
      end
    end
  end
end
