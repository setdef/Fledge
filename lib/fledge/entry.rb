# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "error"

module Fledge
  # One file, folder, or symbolic link on its way into a built app.
  #
  # A build reads a runtime from an archive, reads your app from your
  # disk, and writes both to a folder and to a new archive. The launcher
  # has to stay executable and a symlink has to stay a symlink through
  # every step, even on a computer whose disk keeps no executable bit.
  # And a path read from an archive is input: <tt>../../.bashrc</tt> or
  # a path through a symlink would write outside the folder it belongs
  # in.
  #
  # An entry carries its path, kind, permissions, and contents together,
  # so nothing is lost between reading and writing. It refuses an unsafe
  # path when it is made, and refuses to write through a symlink when it
  # is written.
  #
  # Use it to write files a build adds to an app's folder.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Entry.file("app/main.rb", "puts 1\n").mode    # => 0o644
  #   Fledge::Entry.file("hello", launcher, mode: 0o755)    # an executable
  #   Fledge::Entry.directory("lib").path                   # => "lib"
  #   Fledge::Entry.symlink("current", "app").link          # => "app"
  #
  #   Fledge::Entry.file("../escape", "")
  #   # raises Fledge::Error: "../escape" is not a safe path ...
  #
  #   Fledge::Entry.walk("examples/hello").map(&:path) # => ["main.rb"]
  #--
  # SPDX-SnippetEnd
  #++
  class Entry < Data.define(:path, :type, :mode, :content, :link)
    ##
    # :attr_reader: path
    # The entry's path, relative, with <tt>/</tt> between folders.

    ##
    # :attr_reader: type
    # One of TYPES.

    ##
    # :attr_reader: mode
    # The permission bits, such as <tt>0o755</tt>.

    ##
    # :attr_reader: content
    # A file's bytes, or an empty String for other kinds.

    ##
    # :attr_reader: link
    # A symlink's target, or an empty String for other kinds.

    # The kinds of entry, a regular file, a folder, or a symbolic link.
    TYPES = %i[file directory symlink].freeze

    # A regular file at +path+ holding +content+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Entry.file("main.rb", "puts 1\n").type # => :file
    #--
    # SPDX-SnippetEnd
    #++
    def self.file(path, content, mode: 0o644)
      new(path:, type: :file, mode:, content:, link: "")
    end

    # A folder at +path+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Entry.directory("app").mode # => 0o755
    #--
    # SPDX-SnippetEnd
    #++
    def self.directory(path, mode: 0o755)
      new(path:, type: :directory, mode:, content: "", link: "")
    end

    # A symbolic link at +path+ pointing to +link+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Entry.symlink("latest", "v2").type # => :symlink
    #--
    # SPDX-SnippetEnd
    #++
    def self.symlink(path, link)
      new(path:, type: :symlink, mode: 0o777, content: "", link:)
    end

    # The entries under +root+, folders before what they hold, in name
    # order, with paths relative to +root+. Skips any path in +skip+
    # (absolute paths) and everything under it.
    #
    # Permissions are normalized: <tt>0o755</tt> for folders and
    # executable files, <tt>0o644</tt> for other files. A built app then
    # unpacks the same for everyone, whatever the permissions on the
    # computer that built it.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Entry.walk("my_app", skip: [File.expand_path("my_app/dist")])
    #--
    # SPDX-SnippetEnd
    #++
    def self.walk(root, skip: [])
      skipped = skip.map { |path| File.expand_path(path) }
      entries = [] # : Array[Entry]
      walk_into(File.expand_path(root), "", skipped, entries)
      entries
    end

    private_class_method def self.walk_into(root, relative, skipped, entries) # :nodoc:
      Dir.children(File.join(root, relative)).sort.each do |child|
        path = relative.empty? ? child : "#{relative}/#{child}"
        full = File.join(root, path)
        next if skipped.include?(full)

        entries << from_disk(full, path)
        walk_into(root, path, skipped, entries) if File.directory?(full) && !File.symlink?(full)
      end
    end

    private_class_method def self.from_disk(full, path) # :nodoc:
      if File.symlink?(full)
        symlink(path, File.readlink(full))
      elsif File.directory?(full)
        directory(path)
      else
        file(path, File.binread(full), mode: File.executable?(full) ? 0o755 : 0o644)
      end
    end

    # Creates an entry. Raises Fledge::Error for an unsafe +path+ and
    # ArgumentError for an unknown +type+.
    #
    # [path] Relative, with <tt>/</tt> between names, and with no empty,
    #        <tt>.</tt>, or <tt>..</tt> name in it.
    # [type] One of TYPES.
    # [mode] The permission bits.
    # [content] A file's bytes.
    # [link] A symlink's target.
    def initialize(path:, type:, mode:, content: "", link: "")
      raise ArgumentError, "unknown entry type #{type.inspect}" unless TYPES.include?(type)
      raise Error, "#{path.inspect} is not a safe path for a file in an app" unless safe?(path)

      super
    end

    private def safe?(path)
      return false if path.empty? || path.start_with?("/") || path.include?("\0") || path.include?("\\")

      path.split("/", -1).none? { |name| name.empty? || name == "." || name == ".." || name.end_with?(":") }
    end

    # Writes the entry under the folder +root+. Raises Fledge::Error
    # when a folder on the way is a symlink, so an archive cannot write
    # through a link it planted earlier.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Entry.file("app/main.rb", "puts 1\n").write_into("dist/hello")
    #--
    # SPDX-SnippetEnd
    #++
    def write_into(root)
      target = File.join(root, path)
      refuse_symlinked_parents(root)
      FileUtils.mkdir_p(File.dirname(target))
      case type
      when :directory then FileUtils.mkdir_p(target)
      when :file then File.binwrite(target, content)
      else File.symlink(link, target)
      end
      File.chmod(mode, target) unless type == :symlink
    end

    private def refuse_symlinked_parents(root)
      parents = path.split("/")[0...-1] || []
      parents.each_index do |index|
        parent = File.join(root, *parents.first(index + 1))
        raise Error, "#{path.inspect} would be written through the symlink #{parent}" if File.symlink?(parent)
      end
    end
  end
end
