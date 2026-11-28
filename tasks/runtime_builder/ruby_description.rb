# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "../../lib/fledge/runtime_contents"

class RuntimeBuilder
  # The RUBY_DESCRIPTION of the Ruby a runtime carries, read out of that
  # Ruby and written into the runtime as Fledge::RuntimeContents::DESCRIPTION,
  # so that fledge build compares a Gemfile's ruby and each gem's
  # required_ruby_version with the version RubyGems reports on the
  # runtime (Gem.ruby_version): 4.1.0.preview1 for a preview, 4.1.0.dev
  # for a build of Ruby's master.
  #
  # Ruby names a preview or a development build only in the string its
  # version.c compiles from version.h, "ruby ", RUBY_VERSION, that name,
  # the release date and revision, and the platform; rbconfig.rb records
  # only a PATCHLEVEL of -1. So the build reads the string out of the
  # program or library Ruby compiled it into, in each runtime's layout,
  # as far as the platform, which differs between an iOS runtime's slices
  # and an Android runtime's ABIs.
  module RubyDescription
    # Where a runtime keeps the Ruby it carries: Ruby's program on macOS
    # and Linux, its DLL on Windows, and each iOS slice's framework.
    FILES = %w[bin/ruby ruby/bin/*-ruby*.dll FledgeRuby.xcframework/*/FledgeRuby.framework/FledgeRuby].freeze
    # Android's library for each ABI, in the runtime's AAR, a zip.
    AAR = "FledgeRuby.aar"
    AAR_FILES = "jni/*/libfledgeruby.so"
    # ruby_description, from Ruby's version.c, without its platform.
    LITERAL = /(ruby \d+\.\d+\.\d+\S* \(\d{4}-\d\d-\d\d[^)\0]*\)) \[[^\]\0]+\]/n

    # Writes the description of the Ruby in the runtime folder +stage+
    # into its Fledge::RuntimeContents::DESCRIPTION.
    def self.write(stage)
      File.write(File.join(stage, Fledge::RuntimeContents::DESCRIPTION), "#{read(stage)}\n")
    end

    # The description of the Ruby in the runtime folder +stage+, such as
    # <tt>ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f)</tt>. Raises
    # when it holds no Ruby that describes itself, or Rubies that
    # describe themselves differently.
    def self.read(stage)
      found = libraries(stage).flat_map { |bytes| bytes.scan(LITERAL).flatten }.uniq.sort
      raise "#{stage} holds no Ruby whose RUBY_DESCRIPTION names it" if found.empty?
      raise "#{stage} holds Rubies that describe themselves differently: #{found.join('; ')}" if found.size > 1

      found.first.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    # The bytes of each file in +stage+ that holds the Ruby it carries.
    # unzip reads an AAR, as LicenseAudit does.
    private_class_method def self.libraries(stage)
      files = Dir.glob(FILES, base: stage).sort.map { |path| File.binread(File.join(stage, path)) }
      aar = File.join(stage, AAR)
      return files unless File.file?(aar)

      bytes, status = Open3.capture2("unzip", "-p", aar, AAR_FILES, binmode: true)
      raise "unzip could not read #{AAR_FILES} from #{aar}" unless status.success?

      [*files, bytes]
    end
  end
end
