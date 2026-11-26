# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Delivery asks every app it delivers for the same things
# (.github/scripts/deliver.sh and deliver.ps1): its one line with no
# argument and status 0, and "exit status 3 reaches the caller", which
# runs the app with the argument 3 and fails unless it exits 3. An app
# whose program ignores its arguments passes everything else and fails
# there, which only a full CI run, an hour later, showed twice on
# 2026-11-22 (test/fixtures/ffi_libc and test/fixtures/rust_lengths).
#
# This test reads the workflows for each app they hand to deliver.sh or
# deliver.ps1, as the NAME-PLATFORM archive that script's first argument
# (or -Archive) names, finds the app's folder under examples/ or
# test/fixtures/ by NAME in snake_case, and reads its program for an
# +exit+ that takes its status from +ARGV+. Apps delivered by another
# script (deliver-server.sh, deliver-console.sh, and the rest, whose
# apps differ on purpose: a server ended by a signal, a windowed app)
# are not read, because they are not named after deliver.sh itself. It
# cannot see what the app prints, or that it prints to standard error.
class WorkflowDeliveryAppsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = %r{deliver\.(?:sh|ps1)"?\s+(?:-Archive\s+)?"[^"\s]*/([A-Z]\w*)-}
  PASSES_STATUS_ON = /^\s*exit\b[^#\n]*\bARGV\b/

  def test_every_app_delivered_exits_with_the_status_it_is_given
    apps = delivered_apps
    assert_includes apps, "Hello"
    assert_includes apps, "RustLengths"
    assert_includes apps, "FfiLibc"

    problems = apps.flat_map do |name|
      folder = folder_for(name)
      next ["#{name}: no folder examples/#{snake(name)} or test/fixtures/#{snake(name)}"] unless folder

      programs = programs_in(folder)
      next ["#{name}: #{folder} holds no main.rb or exe/ program"] if programs.empty?

      programs.filter_map { |program| complaint(name, program) }
    end
    assert_empty problems
  end

  def test_a_program_that_ignores_its_arguments_is_named_with_the_line_to_add
    source = %(puts "RustLengths binds rb_len_t in 8 bytes"\n)
    message = complaint("RustLengths", "test/fixtures/rust_lengths/main.rb", source)
    assert_includes message, "RustLengths"
    assert_includes message, "test/fixtures/rust_lengths/main.rb"
    assert_includes message, 'exit Integer(ARGV.fetch(0, "0"))'
    assert_includes message, "exit status 3 reaches the caller"
  end

  def test_a_program_that_exits_with_its_first_argument_is_accepted
    assert_nil complaint("Hello", "examples/hello/main.rb", %(puts "hi"\nexit Integer(ARGV.fetch(0, "0"))\n))
  end

  def test_a_comment_that_mentions_exit_and_ARGV_does_not_count
    assert complaint("Hello", "examples/hello/main.rb", %(# exit with ARGV\nputs "hi"\n))
  end

  private def delivered_apps
    Dir[File.join(ROOT, ".github/workflows/*.yml")].flat_map { |file| File.read(file).scan(SCRIPT).flatten }.uniq.sort
  end

  private def snake(name) = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

  private def folder_for(name)
    %w[examples test/fixtures].map { |parent| "#{parent}/#{snake(name)}" }
      .find { |folder| File.directory?(File.join(ROOT, folder)) }
  end

  private def programs_in(folder)
    main = File.join(folder, "main.rb")
    return [main] if File.file?(File.join(ROOT, main))

    Dir[File.join(ROOT, folder, "exe", "*")].map { |path| path.delete_prefix("#{ROOT}/") }
  end

  private def complaint(name, program, source = File.read(File.join(ROOT, program)))
    return if source.match?(PASSES_STATUS_ON)

    "#{name}: #{program} never exits with a status taken from ARGV. Delivery runs the app " \
      "with the argument 3 and fails unless it exits 3 (\"exit status 3 reaches the caller\", " \
      ".github/scripts/deliver.sh and deliver.ps1). Add as its last line: exit Integer(ARGV.fetch(0, \"0\"))"
  end
end
