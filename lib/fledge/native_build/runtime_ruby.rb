# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require_relative "../error"
require_relative "../tar_gz"

module Fledge
  class NativeBuild
    # The runtime's own Ruby, unpacked with its build-only companion into
    # the build's work folder, which runs SCRIPT with none of the
    # developer's Ruby settings and its own gem folder.
    class RuntimeRuby # :nodoc:
      # The Ruby of +platform+'s runtime, which +runtimes+ finds, unpacked
      # under +work+ when it first runs, its output going to +log+, in an
      # environment made from +env+.
      def initialize(platform:, runtimes:, work:, log:, env:)
        @platform = platform
        @runtimes = runtimes
        @work = work
        @log = log
        @env = env
        @ruby = nil # : String?
      end

      # Runs SCRIPT on the runtime's Ruby for +jobs+, and returns where each
      # gem and its extensions went.
      def run(jobs)
        ruby = prepare
        plan = File.join(@work, "plan.json")
        result = File.join(@work, "result.json")
        script = File.join(@work, "build.rb")
        File.write(script, SCRIPT)
        File.write(plan, JSON.generate({ "home" => home, "jobs" => jobs, "result" => result }))
        @log.puts "Compiling native gems for #{@platform} with the runtime's Ruby"
        status = Open3.popen2e(child_env, ruby, script, plan) do |_, output, thread|
          output.each_line { |line| @log.puts line }
          thread.value
        end
        raise Error, "a gem's extension did not compile for #{@platform}; the compiler's output is above" unless status.success?

        JSON.parse(File.read(result))
      end

      # Unpacks the runtime and its build-only companion, once, and returns
      # the path of the runtime's Ruby.
      private def prepare
        @ruby ||= begin
          ruby = File.join(@work, "ruby")
          FileUtils.rm_rf(ruby)
          [@runtimes.archive(@platform), @runtimes.dev_archive(@platform)].each do |archive|
            TarGz.each_entry(archive) { |entry| entry.write_into(ruby) unless entry.type == :directory && File.directory?(File.join(ruby, entry.path)) }
          end
          top = Dir.children(ruby).first.to_s
          File.join(ruby, top, *(@platform.windows? ? %w[ruby bin ruby.exe] : %w[bin ruby]))
        end
      end

      # The gem folder the runtime's Ruby installs into.
      def home
        File.join(@work, "gems")
      end

      # The environment the runtime's Ruby and the compiler run in: the
      # caller's, without the developer's Ruby settings, with RubyGems
      # pointed at the build's gem folder, and on macOS the runtime's oldest
      # macOS as the deployment target, which clang and rustc both read.
      private def child_env
        env = @env.to_h.keys.grep(SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
        env["GEM_HOME"] = home
        env["GEM_PATH"] = home
        minimum = @platform.macos_minimum
        env["MACOSX_DEPLOYMENT_TARGET"] = minimum if minimum
        env
      end
    end
  end
end
