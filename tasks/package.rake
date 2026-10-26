# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"

# Fledge is installed from its git tags and GitHub Releases, never from
# RubyGems.org (ADR 001). Bundler's gem tasks define release, which
# pushes the branch and a tag to git and the gem to RubyGems.org; this
# removes all three steps and leaves a refusal, and the gemspec's
# allowed_push_host stops a hand-run gem push.
%w[release release:guard_clean release:source_control_push release:rubygem_push].each do |name|
  Rake::Task[name].clear if Rake::Task.task_defined?(name)
end
desc "Refuse: Fledge never publishes to RubyGems.org (ADR 001)"
task :release do
  abort "❌ Fledge never publishes to RubyGems.org. Releases are git tags and GitHub Releases (ADR 001)."
end

namespace :package do
  # The gem, built from what git tracks, installed with no network into
  # an empty GEM_HOME, and run from there with no Bundler and none of
  # the caller's Ruby environment, so nothing in the checkout can stand
  # in for a file the gem forgot to pack.
  desc "Build the gem, install it into an empty GEM_HOME, and run fledge from it"
  task :check do
    root = File.expand_path("..", __dir__)
    work = File.join(root, "tmp", "package")
    FileUtils.rm_rf(work)
    FileUtils.mkdir_p(work)

    spec = Gem::Specification.load(File.join(root, "fledge.gemspec"))
    stray = spec.files.grep(%r{\A(?:test|tasks|doc|examples|\.github)/})
    abort "❌ The gem packs development files: #{stray.join(', ')}" if stray.any?

    Bundler.with_unbundled_env do
      sh "gem", "build", File.join(root, "fledge.gemspec"), "--output", File.join(work, "fledge.gem"), chdir: root
      home = File.join(work, "home")
      env = {
        "GEM_HOME" => home,
        "GEM_PATH" => home,
        "RUBYLIB" => nil,
        "RUBYOPT" => nil,
        "BUNDLE_GEMFILE" => nil,
      }
      sh env, "gem", "install", "--local", "--no-document", "--install-dir", home, File.join(work, "fledge.gem")

      exe = File.join(home, "bin", "fledge")
      out, err, status = Open3.capture3(env, RbConfig.ruby, exe, "--version", chdir: work)
      expected = "fledge #{spec.version}\n"
      unless status.success? && out == expected && err.empty?
        abort "❌ The installed fledge printed #{out.inspect} and #{err.inspect}, exit #{status.exitstatus}; " \
          "expected #{expected.inspect}"
      end

      help, err, status = Open3.capture3(env, RbConfig.ruby, exe, "--help", chdir: work)
      unless status.success? && help.include?("fledge - Ship a Ruby app") && err.empty?
        abort "❌ The installed fledge --help printed #{help.inspect} and #{err.inspect}, exit #{status.exitstatus}"
      end
    end

    puts "✅ The built gem installs into an empty GEM_HOME and its fledge runs"
  end
end
