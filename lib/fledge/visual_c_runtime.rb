# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "binary"
require_relative "entry"
require_relative "linkage"

module Fledge
  # The DLLs of Microsoft's Visual C++ runtime a Windows app carries when
  # its project asks for <tt>windows: { visual_c_runtime: local }</tt>
  # (Config::Windows), copied from the building computer.
  #
  # A gem's DLL built with Visual Studio needs the runtime, which Windows
  # does not include. Microsoft calls copying it into the app's folder
  # local deployment, and limits distributing it to licensed Visual
  # Studio users, a right only the app's developer can hold: so Fledge
  # copies it only when the project asks, only from the computer that
  # builds the app, and nothing Fledge itself publishes carries it
  # (doc/contributors/design/gems.md, "The Visual C++ runtime").
  #
  # This class finds each DLL the gems need (Linkage#visual_c_libraries)
  # in a folder, the building computer's System32, where Microsoft's
  # Visual C++ Redistributable installs it and where the developer's own
  # <tt>bundle exec</tt> loads it from, and each DLL of the runtime those
  # need in turn, as msvcp140.dll needs vcruntime140.dll, read with
  # Fledge::Binary.
  #
  # Use it through Fledge::AppGems.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   runtime = Fledge::VisualCRuntime.new(["MSVCP140.dll"], folder: 'C:\Windows\System32', readers:)
  #   runtime.entries("ruby/bin/ruby_builtin_dlls").map(&:path)
  #   # => ["ruby/bin/ruby_builtin_dlls/msvcp140.dll", "ruby/bin/ruby_builtin_dlls/vcruntime140.dll", ...]
  #--
  # SPDX-SnippetEnd
  #++
  class VisualCRuntime
    # The building computer's System32 by +env+, the folder Windows'
    # Visual C++ Redistributable installs the runtime in ("Deployment in
    # Visual C++", Central deployment).
    def self.system32(env)
      File.join(env["SystemRoot"] || 'C:\Windows', "System32")
    end

    # Finds +names+, the runtime's DLLs the gems need, in +folder+,
    # reading each with +readers+ (Fledge::Binary::Readers) for the
    # runtime's DLLs it needs.
    def initialize(names, folder:, readers:)
      @folder = folder
      @readers = readers
      @found = {} # : Hash[String, String]
      @missing = [] # : Array[String]
      gather(names)
    end

    # Why the app cannot carry the runtime, one sentence for each DLL the
    # folder lacks, or none.
    def problems
      @missing.map do |name|
        "#{name}, of Microsoft's Visual C++ runtime, which windows: { visual_c_runtime: local } copies into the app from " \
          "#{@folder}, is not there. Install Microsoft's Visual C++ Redistributable on this computer, which puts it there."
      end
    end

    # The files that carry the runtime in the app's folder +into+, each by
    # the name the folder gives it.
    def entries(into)
      @found.sort.map { |name, content| Entry.file("#{into}/#{name}", content) }
    end

    # Adds each of +names+ the folder holds to the found, with the
    # runtime's DLLs it needs, and each it lacks to the missing.
    private def gather(names)
      queue = names.dup
      until queue.empty?
        name = queue.shift.to_s
        next if (@found.keys + @missing).any? { |seen| seen.casecmp?(name) }

        file = Dir.children(@folder).find { |child| child.casecmp?(name) }
        next @missing << name unless file

        content = File.binread(File.join(@folder, file))
        @found[file] = content
        queue.concat(Binary.parse({ file => content }, readers: @readers).fetch(file).needed.grep(Linkage::VISUAL_C_RUNTIME))
      end
    end
  end
end
