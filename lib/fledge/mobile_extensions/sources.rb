# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "rubygems/package"
require_relative "../error"
require_relative "../gem_package"
require_relative "../git_package"
require_relative "../path_package"

module Fledge
  class MobileExtensions
    # Unpacks a gem's files for a phone's extension build: a gem from a
    # gem server from its <tt>.gem</tt>, a gem from git from its checkout,
    # and a gem from a folder from that folder.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions::Sources.unpack(package, "/work/ios-arm64/adder-0.1.0") # => "/work/ios-arm64/adder-0.1.0"
    #--
    # SPDX-SnippetEnd
    #++
    module Sources
      # +package+'s files unpacked into +dir+, which is emptied first, and
      # the folder its gemspec's paths, such as its extensions, are
      # relative to.
      def self.unpack(package, dir)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(File.dirname(dir))
        case package
        when GemPackage
          ::Gem::Package.new(package.path).extract_files(dir) # steep:ignore NoMethod
          dir
        when PathPackage
          package.copy_to(dir)
          File.dirname(File.join(dir, package.gemspec))
        when GitPackage
          FileUtils.cp_r(package.checkout, dir)
          FileUtils.rm_rf(File.join(dir, ".git"))
          File.dirname(File.join(dir, package.gemspec))
        else raise Error, "#{package.spec.full_name} is not a gem from a gem server, from git, or from a folder"
        end
      end
    end
  end
end
