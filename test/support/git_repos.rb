# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"

# Real git repositories holding gems, as Ferro's holds its gems under
# gems/*/, for the tests of git gems (ADR 006). Each gemspec lists its
# files with git ls-files, as most do, so a checkout without git would
# break it.
module FakeRepo
  # Writes a repository at +directory+/+name+ holding each of +gems+
  # (name => files, each path relative to the gem's folder and its
  # contents) in gems/NAME/, commits it, and returns [its path, the
  # commit]. +extensions+ names, by gem, the extconf.rb its gemspec
  # lists.
  def self.write(directory, name, gems:, version: "1.0", extensions: {}, licenses: ["MIT"])
    root = File.join(directory, name)
    gems.each do |gem, files|
      folder = File.join(root, "gems", gem)
      files.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(folder, path)))
        File.write(File.join(folder, path), content)
      end
      File.write(File.join(folder, "#{gem}.gemspec"), gemspec(gem, version, extensions.fetch(gem, []), licenses))
    end
    git(root, "init", "--quiet", "--initial-branch=trunk")
    git(root, "add", ".")
    git(root, "-c", "user.name=Fledge", "-c", "user.email=fledge@example.com", "commit", "--quiet", "-m", "Gems")
    [root, git(root, "rev-parse", "HEAD").strip]
  end

  def self.gemspec(name, version, extensions, licenses)
    <<~GEMSPEC
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = #{version.inspect}
        spec.authors = ["Fledge"]
        spec.summary = "A git gem for Fledge's tests"
        spec.licenses = #{licenses.inspect}
        spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) { |ls| ls.readlines("\\x0", chomp: true) }
        spec.extensions = #{extensions.inspect}
      end
    GEMSPEC
  end

  def self.git(root, *arguments)
    FileUtils.mkdir_p(root)
    out, status = Open3.capture2e("git", *arguments, chdir: root)
    raise "git #{arguments.join(' ')} failed: #{out}" unless status.success?

    out
  end
end
