# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require_relative "error"
require_relative "plist"

module Fledge
  # The seal on a macOS app bundle's resources:
  # <tt>Contents/_CodeSignature/CodeResources</tt>.
  #
  # A bundle's signature covers more than its program. It names a
  # property list holding the hash of every other file in the bundle, so
  # <tt>codesign --verify</tt> notices a file changed, added, or removed
  # after signing. Which files it lists, and how, follows rules the list
  # carries with it.
  #
  # This class writes that list as <tt>codesign --sign -</tt> writes it on
  # macOS 15, with the same rules: +files+, the first version's SHA-1
  # hashes of the files under <tt>Resources/</tt>, and +files2+, the
  # SHA-256 hash of every file and the target of every symbolic link,
  # leaving out the program itself, <tt>Info.plist</tt> (which the
  # signature hashes directly), and <tt>.DS_Store</tt> files. Each file
  # goes to the rule of greatest weight that matches its path relative to
  # +Contents+, as codesign chooses. A file where a rule expects code of
  # its own (in <tt>Contents/MacOS</tt>, say), which would need a
  # signature of its own, is refused.
  #
  # Use it through Fledge::MacBundle.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   seal = Fledge::CodeResources.new
  #   seal.add(Fledge::Entry.file("Resources/app/main.rb", "puts 1\n"))
  #   seal.add(Fledge::Entry.symlink("MacOS/lib", "../Resources/lib"))
  #   File.write("Contents/_CodeSignature/CodeResources", seal.bytes)
  #--
  # SPDX-SnippetEnd
  #++
  class CodeResources
    # The first version's rules: what +files+ lists.
    RULES = {
      "^Resources/" => true,
      "^Resources/.*\\.lproj/" => { "optional" => true, "weight" => 1000.0 },
      "^Resources/.*\\.lproj/locversion.plist$" => { "omit" => true, "weight" => 1100.0 },
      "^Resources/Base\\.lproj/" => { "weight" => 1010.0 },
      "^version.plist$" => true,
    }.freeze

    # The second version's rules: what +files2+ lists.
    RULES2 = {
      ".*\\.dSYM($|/)" => { "weight" => 11.0 },
      "^(.*/)?\\.DS_Store$" => { "omit" => true, "weight" => 2000.0 },
      "^(Frameworks|SharedFrameworks|PlugIns|Plug-ins|XPCServices|Helpers|MacOS|Library/(Automator|Spotlight|LoginItems))/" =>
        { "nested" => true, "weight" => 10.0 },
      "^.*" => true,
      "^Info\\.plist$" => { "omit" => true, "weight" => 20.0 },
      "^PkgInfo$" => { "omit" => true, "weight" => 20.0 },
      "^Resources/" => { "weight" => 20.0 },
      "^Resources/.*\\.lproj/" => { "optional" => true, "weight" => 1000.0 },
      "^Resources/.*\\.lproj/locversion.plist$" => { "omit" => true, "weight" => 1100.0 },
      "^Resources/Base\\.lproj/" => { "weight" => 1010.0 },
      "^[^/]+$" => { "nested" => true, "weight" => 10.0 },
      "^embedded\\.provisionprofile$" => { "weight" => 20.0 },
      "^version\\.plist$" => { "weight" => 20.0 },
    }.freeze

    # Creates an empty seal.
    def initialize
      @files = {} # : Hash[String, Plist::Bytes | Hash[String, Plist::Bytes | bool]]
      @files2 = {} # : Hash[String, Hash[String, Plist::Bytes | String | bool]]
    end

    # Adds +entry+, a Fledge::Entry whose path is relative to the bundle's
    # +Contents+ folder, to the seal. Folders add nothing. Raises
    # Fledge::Error for a file a rule calls nested code.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   seal.add(Fledge::Entry.file("Resources/notices/NOTICES.txt", notices))
    #--
    # SPDX-SnippetEnd
    #++
    def add(entry)
      return if entry.type == :directory

      path = entry.path
      add_v1(path, entry) if entry.type == :file
      rule = CodeResources.rule(RULES2, path) or return
      return if rule["omit"]
      raise Error, "#{path} is where a bundle keeps code with its own signature, which Fledge does not sign" if rule["nested"] && entry.type == :file

      @files2[path] = (entry.type == :symlink) ? { "symlink" => entry.link } : with_optional({ "hash2" => Plist::Bytes.new(bytes: Digest::SHA256.digest(entry.content)) }, rule)
    end

    # The seal as the property list codesign writes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   seal.bytes.start_with?("<?xml") # => true
    #--
    # SPDX-SnippetEnd
    #++
    def bytes
      Plist.write({ "files" => @files, "files2" => @files2, "rules" => RULES, "rules2" => RULES2 })
    end

    # The rule in +rules+ that decides +path+: the matching one of greatest
    # weight, as a Hash of its settings, or +nil+ when none matches.
    def self.rule(rules, path)
      matches = rules.select { |pattern, _| path.match?(Regexp.new(pattern)) }
      return nil if matches.empty?

      none = {} # : Hash[String, bool | Float]
      settings = matches.map { |_, value| value.is_a?(Hash) ? value : none }
      settings.max_by { |value| (weight = value["weight"]).is_a?(Float) ? weight : 1.0 }
    end

    private def add_v1(path, entry)
      rule = CodeResources.rule(RULES, path) or return
      return if rule["omit"]

      hash = Plist::Bytes.new(bytes: Digest::SHA1.digest(entry.content))
      @files[path] = rule["optional"] ? { "hash" => hash, "optional" => true } : hash
    end

    private def with_optional(record, rule)
      rule["optional"] ? record.merge("optional" => true) : record
    end
  end
end
