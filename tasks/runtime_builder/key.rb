# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require "json"
require "open3"

class RuntimeBuilder
  # What a runtime is built from, as a digest per input, so that a runtime
  # left in tmp/runtime is reused only when nothing it is built from has
  # changed. The inputs are the pins (runtime/sources.yml), the rest
  # of runtime/ (the launcher's C, the notices, the license records but
  # runtime/audited.yml, which CI's runs write), the build tasks and the
  # parts of lib/ they use, the platform, the computer that builds, Fledge's
  # version, and the toolchain's versions.
  class Key
    # The files of each input, as globs under the repository's root.
    INPUTS = {
      "pins" => %w[runtime/sources.yml],
      "runtime sources" => %w[runtime/**/*],
      "build tasks" => %w[
        tasks/runtime_builder.rb
        tasks/runtime_builder/**/*.rb
        tasks/license_audit.rb
        tasks/license_audit/**/*.rb
        tasks/release_archive.rb
        tasks/download_cache.rb
      ],
      "Fledge's library code" => %w[
        lib/fledge/version.rb
        lib/fledge/platform.rb
        lib/fledge/runtimes.rb
        lib/fledge/download.rb
        lib/fledge/archive.rb
        lib/fledge/license_policy.rb
        lib/fledge/binary.rb
        lib/fledge/binary/**/*.rb
        lib/fledge/runtime_contents.rb
        lib/fledge/mobile_project/**/*
      ],
    }.freeze

    # Files an input's globs match that are not part of it.
    LEFT_OUT = { "runtime sources" => %w[runtime/sources.yml runtime/audited.yml] }.freeze

    # The commands whose first line of output names the toolchain's
    # versions, for the runtime of +platform+ built by +cc+ (the C
    # compiler's name). Windows' toolchain is pinned in sources.yml, and
    # Android's NDK too.
    def self.probes(platform, cc:)
      return [] if platform.respond_to?(:windows?) && platform.windows?
      return [["xcodebuild", "-version"], ["xcrun", "clang", "--version"], ["rustc", "--version"]] if platform.name == "ios"
      return [["rustc", "--version"]] if platform.name == "android"

      [[cc, "--version"], ["rustc", "--version"]]
    end

    # Runs each of +probes+ and returns its first line of output, or
    # "not found", by the command.
    def self.toolchain(probes)
      probes.to_h do |command|
        out, status = Open3.capture2e(*command)
        [command.join(" "), status.success? ? out.lines.first.to_s.strip : "failed"]
      rescue SystemCallError
        [command.join(" "), "not found"]
      end
    end

    # +describing+ is a String naming the platform, the computer, and
    # Fledge's version; +toolchain+ is what .toolchain returned.
    def initialize(root:, describing:, toolchain:)
      @root = root
      @describing = describing
      @toolchain = toolchain
    end

    # A digest by the name of each input.
    def parts
      @parts ||= INPUTS.to_h { |name, globs| [name, digest_files(name, globs)] }
        .merge("build" => Digest::SHA256.hexdigest(@describing), "toolchain" => Digest::SHA256.hexdigest(JSON.generate(@toolchain)))
    end

    # The key as the JSON a runtime's key file holds.
    def to_json(*)
      JSON.pretty_generate("parts" => parts, "toolchain" => @toolchain, "build" => @describing)
    end

    # Why a runtime recorded as +recorded+ (the JSON of its key file, or
    # nil when it has none or it does not parse) is not one built from
    # these inputs: a sentence naming each input that changed, or nil
    # when none did.
    def mismatch(recorded)
      before = recorded_parts(recorded) or return "it records no key"
      changed = parts.keys.select { |name| before[name] != parts[name] }
      return nil if changed.empty?

      "its #{changed.join(' and ')} changed since it was built"
    end

    private def recorded_parts(recorded)
      JSON.parse(recorded.to_s).fetch("parts")
    rescue JSON::ParserError, KeyError, TypeError
      nil
    end

    private def digest_files(name, globs)
      left = LEFT_OUT.fetch(name, [])
      files = globs.flat_map { |glob| Dir.glob(glob, base: @root) }.uniq.sort - left
      digest = Digest::SHA256.new
      files.each do |file|
        path = File.join(@root, file)
        next unless File.file?(path)

        digest << file << "\0" << Digest::SHA256.file(path).hexdigest << "\n"
      end
      digest.hexdigest
    end
  end
end
