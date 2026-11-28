# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  class MobileExtensions
    # A shared library a gem's Rakefile built for one target of a phone
    # that is no extension of Ruby's, such as one ffi-compiler links for
    # Ruby's ffi to open by its path: the gem's name, the library's path
    # in the gem, where the build left it, its file, and the paths,
    # relative to the app's Ruby root, at which the gem looks for it
    # (.links). Every such gem read gives <tt>ffi_lib</tt> a path in its
    # own folder, which ffi hands <tt>dlopen</tt> unchanged.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   library.file  # => "ext/x86_64-linux/libllhttp-ext.so"
    #   library.links # => ["lib/ruby/gems/4.1.0+5/gems/llhttp-ffi-0.5.1/ext/x86_64-linux/libllhttp-ext.so"]
    #--
    # SPDX-SnippetEnd
    #++
    class FfiLibrary < Data.define(:gem, :file, :path, :links)
      ##
      # :attr_reader: gem
      # The name of the gem whose Rakefile built it, such as <tt>"llhttp-ffi"</tt>.

      ##
      # :attr_reader: file
      # Its path in the gem's folder, where the build left it.

      ##
      # :attr_reader: path
      # The library the build made.

      ##
      # :attr_reader: links
      # The paths, relative to the app's Ruby root, where a desktop has
      # its file.

      # Where a desktop has the library +file+, a path in +package+'s
      # gem, for a Ruby whose gem folder is +gem_dir+, relative to the Ruby
      # root, as the gem's entries are: in the gem's own folder, where the
      # build left it, since RubyGems copies only what a Rakefile installs
      # into its extension folder, and ffi-compiler installs nothing
      # there.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::FfiLibrary.links(package, "ext/scrypt/x86_64-linux/libscrypt_ext.so", gem_dir: "lib/ruby/gems/4.1.0+5")
      #   # => ["lib/ruby/gems/4.1.0+5/gems/scrypt-3.1.0/ext/scrypt/x86_64-linux/libscrypt_ext.so"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.links(package, file, gem_dir:)
        ["#{package.installed_path(gem_dir)}/#{file}"]
      end
    end
  end
end
