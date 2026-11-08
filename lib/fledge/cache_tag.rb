# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"

module Fledge
  # The tag of the Cache Directory Tagging Specification
  # (https://bford.info/cachedir/): a file named CACHEDIR.TAG whose first
  # 43 bytes are FILE's SIGNATURE, which marks the folder that holds it
  # as one whose contents a tool made and can make again.
  #
  # A build writes into the folder <tt>--out</tt> names, often inside
  # the project it ships, and every folder a build ever wrote into has
  # to stay out of every later build's copy of that project, wherever
  # the later one goes. The tag says so on disk, as Cargo tags its
  # +target+ folder, and backup tools that honor it (GNU tar's
  # <tt>--exclude-caches</tt>, Borg, restic) leave the builds out too.
  #
  # Use it where a build makes the folder its output goes to, and where
  # a build copies the project (ADR 005, section 1).
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::CacheTag.make_folder("my_app/dist")
  #   Fledge::CacheTag.tagged?("my_app/dist") # => true
  #--
  # SPDX-SnippetEnd
  #++
  module CacheTag
    # The tag's name.
    FILE = "CACHEDIR.TAG"

    # What a tag's file begins with, the specification's 43 bytes.
    SIGNATURE = "Signature: 8a477f597d28d172789f06886806bc55"

    # The tag a build writes: the signature, and comments that say who
    # wrote it and where the specification is, as the specification
    # recommends.
    CONTENT = "#{SIGNATURE}\n# This file is a cache directory tag created by fledge build.\n" \
      "# For information about cache directory tags see https://bford.info/cachedir/\n"

    # Makes the folder +path+ and its parents, and tags it when it holds
    # nothing: when the build made it, or found it empty. A folder that
    # holds anything already, the build's or someone else's, is left as
    # it is, so a tag never marks someone's own files as a cache.
    def self.make_folder(path)
      FileUtils.mkdir_p(path)
      File.write(File.join(path, FILE), CONTENT) if Dir.empty?(path)
    end

    # Whether +folder+ holds a tag: a regular file, not a link, whose
    # first bytes are SIGNATURE, as the specification asks a tool to
    # check before it trusts one.
    def self.tagged?(folder)
      tag = File.join(folder, FILE)
      File.file?(tag) && !File.symlink?(tag) && File.binread(tag, SIGNATURE.bytesize) == SIGNATURE
    end
  end
end
