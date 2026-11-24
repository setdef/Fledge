# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# A developer writes their app in Ruby, with whatever front end their
# framework uses (HTML, CSS, and JavaScript in a web view, say), and
# never writes the native code a platform needs: every line of C,
# Objective-C, Swift, Java, Kotlin, or another platform's language is
# Fledge's, in its runtime, launcher, and templates. An example shows a
# developer's project, so it holds none. Reads git's list of files, so
# a file must be staged to count.
class ExamplesRubyOnlyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Each source language of a platform's native or systems code, with
  # the platform that makes a developer write it.
  NATIVE_EXTENSIONS = {
    ".c" => "C, the systems language of every platform",
    ".h" => "C's headers",
    ".cc" => "C++",
    ".cpp" => "C++",
    ".cxx" => "C++",
    ".hh" => "C++'s headers",
    ".hpp" => "C++'s headers",
    ".m" => "Objective-C, Apple's native language",
    ".mm" => "Objective-C++, Apple's native language",
    ".swift" => "Swift, Apple's native language",
    ".java" => "Java, Android's native language",
    ".kt" => "Kotlin, Android's native language",
    ".kts" => "Kotlin's scripts, Gradle's build files on Android",
    ".gradle" => "Groovy's build scripts, Gradle's on Android",
    ".groovy" => "Groovy, Gradle's language on Android",
    ".rs" => "Rust, a systems language",
    ".go" => "Go, a systems language",
    ".cs" => "C#, Windows' native language",
    ".sh" => "shell scripts, another language than Ruby",
    ".bat" => "batch files, Windows' shell",
    ".cmd" => "batch files, Windows' shell",
    ".ps1" => "PowerShell, Windows' shell",
  }.freeze

  NATIVE_NAMES = {
    "Makefile" => "make's build file, another language than Ruby",
    "CMakeLists.txt" => "CMake's build file, another language than Ruby",
  }.freeze

  RUBY_SHEBANG = %r{\A#!\S*(/ruby|/env\s+ruby)\b}

  def test_examples_hold_no_native_code
    offenders = examples.filter_map { |path| reason_against(path) && [path, reason_against(path)] }
    assert_empty offenders, offenders.map { |path, why| explain(path, why) }.join("\n")
  end

  def test_the_lists_name_a_reason_for_each_kind
    reasons = NATIVE_EXTENSIONS.values + NATIVE_NAMES.values
    assert(reasons.none?(&:empty?))
  end

  private def examples
    out = IO.popen(["git", "-C", ROOT, "ls-files", "-z", "examples"], &:read)
    out.split("\0").reject { |path| File.directory?(File.join(ROOT, path)) }
  end

  private def reason_against(path)
    NATIVE_NAMES[File.basename(path)] ||
      NATIVE_EXTENSIONS[File.extname(path).downcase] ||
      (path.split("/")[2] == "bin" && !ruby_shebang?(path) && "a program in bin/ that does not start with a Ruby shebang")
  end

  private def ruby_shebang?(path)
    File.open(File.join(ROOT, path), "rb") { |file| file.gets.to_s.match?(RUBY_SHEBANG) }
  end

  private def explain(path, why)
    "#{path} is #{why}. A developer writes their app in Ruby and never " \
      "the native code a platform needs: every line in another language " \
      "is Fledge's, in its runtime, launcher, or templates, not an example's."
  end
end
