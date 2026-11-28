# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"
require_relative "../error"
require_relative "../archive"

module Fledge
  class NativeBuild
    # The runtime's own Ruby, unpacked into the build's work folder, which
    # runs SCRIPT with none of the developer's Ruby settings and its own
    # gem folder. The runtime alone has what compiling a gem's extension
    # needs of Ruby: its headers and the library mkmf links against.
    class RuntimeRuby # :nodoc:
      # The Ruby of +platform+'s runtime, which +runtimes+ finds, unpacked
      # under +work+ when it first runs, its output going to +log+, in an
      # environment made from +env+, less what the Ruby installed at
      # +prefix+ (default: the one running Fledge) added to it.
      def initialize(platform:, runtimes:, work:, log:, env:, prefix: RbConfig::CONFIG.fetch("prefix"))
        @platform = platform
        @runtimes = runtimes
        @work = work
        @log = log
        @env = env
        @prefix = prefix
        @ruby = nil # : String?
      end

      # Runs +source+ (default: SCRIPT) on the runtime's Ruby for +jobs+, and
      # returns what it wrote for each: where each gem and its extensions
      # went, for SCRIPT. +message+ says what it is doing, and +failure+
      # what went wrong when it fails.
      def run(jobs, source: SCRIPT, message: "Compiling native gems for #{@platform} with the runtime's Ruby",
        failure: "a gem's extension did not compile for #{@platform}; the compiler's output is above"
      )
        ruby = prepare
        plan = File.join(@work, "plan.json")
        result = File.join(@work, "result.json")
        script = File.join(@work, "build.rb")
        File.write(script, source)
        File.write(plan, JSON.generate({ "home" => home, "jobs" => jobs, "result" => result }))
        @log.puts message
        status = Open3.popen2e(env, ruby, script, plan) do |_, output, thread|
          output.each_line { |line| @log.puts line }
          thread.value
        end
        raise Error, failed(result, failure) unless status.success?

        JSON.parse(File.read(result))
      end

      # +failure+, naming the gem SCRIPT wrote as the one whose extension
      # failed, if it wrote one: the build's output, which RubyGems' own
      # error message holds, is already in the log.
      private def failed(result, failure)
        name = JSON.parse(File.read(result)).then { |written| written["failed"] if written.is_a?(Hash) }
        name ? "gem #{name}'s extension did not compile for #{@platform}; the compiler's output is above" : failure
      rescue SystemCallError, JSON::ParserError
        failure
      end

      # Unpacks the runtime, once, and returns the path of its Ruby.
      private def prepare
        @ruby ||= begin
          ruby = File.join(@work, "ruby")
          FileUtils.rm_rf(ruby)
          Archive.unpack(@runtimes.archive(@platform), into: ruby)
          top = Dir.children(ruby).first.to_s
          File.join(ruby, top, *(@platform.windows? ? %w[ruby bin ruby.exe] : %w[bin ruby]))
        end
      end

      # The gem folder the runtime's Ruby installs into.
      def home
        File.join(@work, "gems")
      end

      # The environment the runtime's Ruby and the compiler run in: the
      # caller's, without the developer's Ruby settings; with RubyGems
      # installing into the build's gem folder and finding gems there and
      # then in the runtime's own, as <tt>gem install</tt> on the runtime's
      # Ruby finds them, since RubyGems follows a GEM_PATH that ends in the
      # path separator with its default path
      # (Gem::PathSupport#split_gem_path, at RubyGems 4.1.0.beta2), so
      # that Gem::Ext::RakeBuilder finds the rake the runtime bundles; with
      # RubyGems reading a gem's metadata with Psych, as RubyGems 4.0
      # did, since the parser RubyGems 4.1 (4.1.0.beta2 and beta3) reads
      # it with by default gives every name in it as a BINARY string; and
      # on macOS the runtime's oldest macOS as the deployment target,
      # which clang and rustc both read; and with PKG_CONFIG_PATH less
      # the folders inside the developer's own Ruby, which jdx/ruby's
      # rbconfig.rb puts first in it whenever that Ruby starts, so that
      # what a gem links does not depend on which Ruby ran Fledge
      # (gems.md, "What the build takes from the developer's
      # environment").
      #
      # A runtime that holds the headers, static libraries, and
      # pkg-config files of the libraries its Ruby was built with puts its
      # pkg-config folder first in PKG_CONFIG_PATH and its include folder first
      # in CPATH, which gcc and clang search before the system's headers, so
      # that a gem finds those before the computer's; mkmf already links against
      # the runtime's lib/ first.
      def env
        env = @env.to_h.keys.grep(SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
        given = @env.to_h["PKG_CONFIG_PATH"]
        path = pkg_config_path(given.to_s)
        env["PKG_CONFIG_PATH"] = path unless path == given
        gem_libraries(env)
        env["GEM_HOME"] = home
        env["GEM_PATH"] = "#{home}#{File::PATH_SEPARATOR}"
        env["RUBYGEMS_USE_PSYCH"] = "true"
        minimum = @platform.macos_minimum
        env["MACOSX_DEPLOYMENT_TARGET"] = minimum if minimum
        env
      end

      # Puts the unpacked runtime's pkg-config and include folders first in
      # +env+, when it has a pkg-config folder.
      private def gem_libraries(env)
        ruby = @ruby
        return unless ruby && !@platform.windows?

        prefix = File.dirname(File.dirname(ruby))
        pkgconfig = File.join(prefix, "lib", "pkgconfig")
        return unless File.directory?(pkgconfig)

        rest = env.key?("PKG_CONFIG_PATH") ? env["PKG_CONFIG_PATH"] : @env["PKG_CONFIG_PATH"]
        env["PKG_CONFIG_PATH"] = [pkgconfig, rest].compact.reject(&:empty?).join(File::PATH_SEPARATOR)
        env["CPATH"] = [File.join(prefix, "include"), @env["CPATH"]].compact.reject(&:empty?).join(File::PATH_SEPARATOR)
      end

      # +given+ without any folder inside the developer's own Ruby, or nil
      # when nothing is left: such a folder describes that Ruby's
      # libraries, never the runtime's.
      private def pkg_config_path(given)
        prefix = File.expand_path(@prefix)
        folders = given.split(File::PATH_SEPARATOR).reject do |folder|
          path = File.expand_path(folder)
          path == prefix || path.start_with?("#{prefix}/")
        end
        folders.empty? ? nil : folders.join(File::PATH_SEPARATOR)
      end
    end
  end
end
