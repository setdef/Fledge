# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The files the gate's lints of shell, workflows, and C read (lint:shell,
# lint:workflows, and lint:c, in tasks/lint.rake), each a list of paths
# relative to the repository's +root+ that git tracks, which the fast
# check (tasks/check.rake) narrows to those a change touches; and how
# both find a tool on PATH.
module LintFiles
  # The first bytes of a file shellcheck checks.
  SHEBANGS = ["#!/usr/bin/env bash", "#!/bin/sh"].freeze

  extend self

  # The shell scripts: the tracked files in bin and .github/scripts that
  # start with a shell's shebang.
  def shell(root)
    tracked(root, "bin", ".github/scripts").select do |path|
      File.read(File.join(root, path), 64).start_with?(*SHEBANGS)
    end
  end

  # The GitHub Actions workflows actionlint checks.
  def workflows(root)
    tracked(root, ".github/workflows").grep(/\.ya?ml\z/)
  end

  # The C and its headers of the launcher and the mobile embedding API,
  # which clang-format checks.
  def c(root)
    tracked(root, "runtime/launcher", "runtime/mobile").grep(/\.[ch]\z/)
  end

  # The path of the executable +name+ on the PATH in +env+, or nil. On
  # Windows a name is tried with each extension PATHEXT lists, as cmd
  # does, so shellcheck is found as shellcheck.exe.
  def which(name, env = ENV)
    extensions = ["", *(env.fetch("PATHEXT", "").split(File::PATH_SEPARATOR) if Gem.win_platform?)]
    env.fetch("PATH", "").split(File::PATH_SEPARATOR).product(extensions).map { |dir, extension| File.join(dir, name + extension) }
      .find { |path| File.file?(path) && File.executable?(path) }
  end

  # The files git tracks under +dirs+.
  def tracked(root, *dirs)
    IO.popen(["git", "ls-files", "-z", "--", *dirs], chdir: root, &:read).split("\0")
  end
end
