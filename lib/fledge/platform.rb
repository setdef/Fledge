# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "archive"
require_relative "error"

module Fledge
  # A platform Fledge builds apps for, named as RubyGems names it.
  #
  # You already meet RubyGems' platform names in a Gemfile.lock and in
  # precompiled gems: +arm64-darwin+, +x86_64-linux+. The same names say
  # which precompiled gem fits a runtime, so Fledge names its targets
  # with them (ADR 001, section 4). But RubyGems also knows platforms
  # Fledge has no runtime for, and names the computer you are on in more
  # detail (<tt>arm64-darwin-25</tt>) than a target needs.
  #
  # This class holds the platforms Fledge has runtimes for, finds one by
  # name, maps the computer you are on to one, and knows what differs
  # between them: the archive a built app ships in (a .zip on Windows,
  # where a person double-clicks one, and a .tar.gz elsewhere, which
  # keeps executable bits and symlinks) and the name of its executable.
  #
  # Use it to name the computer a build is for, and the runtime it uses.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Platform.find("x86_64-linux").name # => "x86_64-linux"
  #   Fledge::Platform.names # => ["arm64-darwin", "x86_64-linux", "aarch64-linux", "x64-mingw-ucrt"]
  #
  #   # On an Apple Silicon Mac:
  #   Fledge::Platform.local.name # => "arm64-darwin"
  #
  #   Fledge::Platform.find("x86_64-linux").archive_extension # => ".tar.gz"
  #   Fledge::Platform.find("x64-mingw-ucrt").archive_extension # => ".zip"
  #   Fledge::Platform.find("x64-mingw-ucrt").executable("hello") # => "hello.exe"
  #--
  # SPDX-SnippetEnd
  #++
  class Platform < Data.define(:name)
    # The names of the platforms Fledge has runtimes for, in the order
    # it lists them.
    NAMES = %w[arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt].freeze

    # The oldest macOS an arm64-darwin runtime runs on: rv-ruby's Sonoma
    # build, and the launcher built with -mmacosx-version-min=14.0 (ADR
    # 001, section 3).
    MACOS_MINIMUM = "14.0"

    # The oldest glibc a Linux runtime runs on: rv-ruby's Linux builds
    # call functions glibc added in 2.39, a floor the maintainer accepted
    # (decision 7; ADR 001, section 3).
    GLIBC_MINIMUM = "2.39"

    ##
    # :attr_reader: name
    # The RubyGems platform name, such as <tt>"x86_64-linux"</tt>.

    # The names of every platform Fledge has runtimes for.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.names.first # => "arm64-darwin"
    #--
    # SPDX-SnippetEnd
    #++
    def self.names
      NAMES
    end

    # The platform named +name+. Raises Fledge::UsageError, listing the
    # platforms Fledge knows, for any other name.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("aarch64-linux") # => #<data Fledge::Platform name="aarch64-linux">
    #--
    # SPDX-SnippetEnd
    #++
    def self.find(name)
      return new(name:) if NAMES.include?(name)

      raise UsageError, "'#{name}' is not a platform Fledge has runtimes for. Platforms: #{NAMES.join(', ')}."
    end

    # The platform of the computer described by +gem_platform+ (default:
    # this one). Raises Fledge::Error when Fledge has no runtime for it.
    #
    # RubyGems names a Mac with its Darwin version and a Linux computer
    # with its C library, when that is not glibc. A target needs neither:
    # one macOS runtime serves every supported version, and only glibc
    # Linux has runtimes. RubyInstaller's Ruby names Windows exactly as
    # the target is named, +x64-mingw-ucrt+.
    #
    # [gem_platform] A Gem::Platform (default: Gem::Platform.local).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.local(Gem::Platform.new("arm64-darwin-25")).name # => "arm64-darwin"
    #--
    # SPDX-SnippetEnd
    #++
    def self.local(gem_platform = Gem::Platform.local)
      name = target_name(gem_platform)
      return new(name:) if NAMES.include?(name)

      raise Error, "Fledge has no runtime for this computer's platform (#{gem_platform}). " \
        "Build on one it has: #{NAMES.join(', ')}."
    end

    private_class_method def self.target_name(gem_platform) # :nodoc:
      cpu = gem_platform.cpu
      os = gem_platform.os
      version = gem_platform.version
      return "#{cpu}-darwin" if os == "darwin"
      return "#{cpu}-linux" if os == "linux" && [nil, "gnu"].include?(version)

      gem_platform.to_s
    end

    # Whether the platform is Windows, whose apps are a .exe in a .zip.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("x64-mingw-ucrt").windows? # => true
    #--
    # SPDX-SnippetEnd
    #++
    def windows?
      name.end_with?("-mingw-ucrt")
    end

    # The operating system's name, as the libraries it provides are listed
    # under (Fledge::Linkage): +darwin+, +linux+, or +windows+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("aarch64-linux").os # => "linux"
    #--
    # SPDX-SnippetEnd
    #++
    def os
      return "windows" if windows?

      name.end_with?("-darwin") ? "darwin" : "linux"
    end

    # The oldest macOS the platform's apps run on (MACOS_MINIMUM), or
    # +nil+ for a platform that is not macOS.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("arm64-darwin").macos_minimum # => "14.0"
    #--
    # SPDX-SnippetEnd
    #++
    def macos_minimum
      (os == "darwin") ? MACOS_MINIMUM : nil
    end

    # The oldest glibc the platform's apps run on (GLIBC_MINIMUM), or +nil+
    # for a platform that is not Linux.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("x86_64-linux").glibc_minimum # => "2.39"
    #--
    # SPDX-SnippetEnd
    #++
    def glibc_minimum
      (os == "linux") ? GLIBC_MINIMUM : nil
    end

    # The names a Gemfile.lock's PLATFORMS section gives this platform,
    # any of which locks gems for it: the name itself, and on Linux its
    # glibc name too, which RubyGems treats as the same platform
    # (Gem::Platform#=== normalizes +gnu+ away). A macOS lockfile
    # platform with a Darwin version, such as <tt>arm64-darwin-25</tt>,
    # does not count: Bundler would refuse it on another version of
    # macOS.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("x86_64-linux").lockfile_names # => ["x86_64-linux", "x86_64-linux-gnu"]
    #   Fledge::Platform.find("arm64-darwin").lockfile_names # => ["arm64-darwin"]
    #--
    # SPDX-SnippetEnd
    #++
    def lockfile_names
      name.end_with?("-linux") ? [name, "#{name}-gnu"] : [name]
    end

    # Whether the app's Bundler takes only +ruby+ gems: never on a
    # desktop, whose gems' builds for it Bundler picks
    # (Fledge::MobilePlatform#force_ruby_platform?).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("x86_64-linux").force_ruby_platform? # => false
    #--
    # SPDX-SnippetEnd
    #++
    def force_ruby_platform?
      false
    end

    # The extension of the archive a built app ships in.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("arm64-darwin").archive_extension # => ".tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def archive_extension
      windows? ? Archive::ZIP : Archive::TAR_GZ
    end

    # The file name an executable called +name+ has on this platform:
    # +name+ on macOS and Linux, and <tt>name.exe</tt> on Windows, which
    # runs only files named so.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Platform.find("x86_64-linux").executable("hello")   # => "hello"
    #   Fledge::Platform.find("x64-mingw-ucrt").executable("hello") # => "hello.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def executable(name)
      windows? ? "#{name}.exe" : name
    end

    # The platform's name.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   "hello-#{Fledge::Platform.find('x86_64-linux')}" # => "hello-x86_64-linux"
    #--
    # SPDX-SnippetEnd
    #++
    def to_s
      name
    end
  end
end
