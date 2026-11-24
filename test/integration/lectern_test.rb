# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "tmpdir"

# examples/lectern, run as ruby main.rb under its own bundle (kramdown,
# kramdown-parser-gfm, and Rouge, installed from RubyGems.org, which no
# unit test may reach): what each Markdown element looks like, how it
# wraps, what the colors do under NO_COLOR and off a terminal, and what
# the command says of what it cannot read. A pseudo-terminal stands for
# the terminal, where there is one. The built app is run on a fresh
# computer by .github/scripts/deliver-lectern.sh, in CI's Delivery.
class LecternIntegrationTest < Minitest::Test
  EXAMPLE = File.expand_path("../../examples/lectern", __dir__)
  GEMFILE = File.join(EXAMPLE, "Gemfile")
  ESC = "\e["
  ROOT = File.expand_path("../..", __dir__)

  SAMPLE = <<~MARKDOWN
    # Title

    Some *emphasis*, **strong**, ~~gone~~, `code`, and [a link](https://example.com/page).

    ## Section

    - one
    - two
      1. inner

    > quoted

    ```ruby
    puts "hi" # note
    ```

    | name | size |
    |:-----|-----:|
    | a    | 1    |
  MARKDOWN

  # The example's own bundle, as a person's shell gives it. The test runs
  # under bundle exec, whose Bundler, restarted at the version this
  # repository's lockfile names, sets BUNDLER_VERSION, and
  # Bundler.with_unbundled_env keeps that variable while it removes
  # BUNDLE_PATH, where that Bundler is installed. A bundle command
  # started with it would run whichever Bundler the Ruby has, with
  # BUNDLER_VERSION turning off its switch to the one Lectern's lockfile
  # names (Bundler::SelfManager#autoswitching_applies?), and bundle
  # install would write that Bundler into the lockfile: the gate in CI
  # rewrote BUNDLED WITH from 4.0.20 to Ruby 4.1.0-preview1's 4.1.0.beta2
  # and dropped Bundler's checksum.
  BUNDLE = { "BUNDLE_GEMFILE" => GEMFILE, "BUNDLER_VERSION" => nil }.freeze

  # Installs Lectern's bundle once, and fails if that changed the Bundler
  # its Gemfile.lock names, or that Bundler's checksum, as a person's
  # bundle install leaves them. (On Windows, a person's bundle install
  # adds the computer's platform to PLATFORMS, and so does this one.)
  def self.install
    @installed ||= begin
      lockfile = File.join(EXAMPLE, "Gemfile.lock")
      locked = lockfile_bundler(lockfile)
      Bundler.with_unbundled_env do
        out, status = Open3.capture2e(BUNDLE, RbConfig.ruby, "-S", "bundle", "install", "--quiet")
        raise out unless status.success?
      end
      now = lockfile_bundler(lockfile)
      raise "bundle install changed the Bundler #{lockfile} names from #{locked} to #{now}" unless now == locked

      true
    end
  end

  # The BUNDLED WITH version of +lockfile+, and its checksum line for
  # Bundler.
  def self.lockfile_bundler(lockfile)
    text = File.read(lockfile)
    [text[/^BUNDLED WITH\r?\n\s+(\S+)/, 1], text[/^  bundler \(.*$/]&.chomp]
  end

  def setup
    self.class.install
  end

  # The command's output, error, and status, with +env+ and +stdin+, as a
  # subprocess whose output is a pipe.
  def lectern(*, stdin: "", env: {})
    Bundler.with_unbundled_env do
      Open3.capture3(BUNDLE.merge(env), RbConfig.ruby, "-S", "bundle", "exec", "ruby", File.join(EXAMPLE, "main.rb"),
        *, stdin_data: stdin)
    end
  end

  def test_each_element_is_drawn_in_its_style
    out, err, status = lectern("--color=always", "-", stdin: SAMPLE)

    assert_predicate status, :success?, err
    assert_includes out, "#{ESC}1;36mTitle#{ESC}0m"
    assert_includes out, "#{ESC}1;34mSection#{ESC}0m"
    assert_includes out, "#{ESC}3memphasis#{ESC}0m"
    assert_includes out, "#{ESC}1mstrong#{ESC}0m"
    assert_includes out, "#{ESC}9mgone#{ESC}0m"
    assert_includes out, "#{ESC}33mcode#{ESC}0m"
    assert_includes out, "#{ESC}4;34ma#{ESC}0m"
    assert_includes out, "#{ESC}2m(https://example.com/page)#{ESC}0m"
    assert_includes out, "#{ESC}36mputs#{ESC}0m", "a Ruby builtin is highlighted"
    assert_includes out, "#{ESC}32m\"hi\"#{ESC}0m", "a Ruby string is highlighted"
  end

  def test_plain_output_carries_the_structure_in_characters_alone
    out, err, status = lectern("-", stdin: SAMPLE)

    assert_predicate status, :success?, err
    refute_includes out, "\e"
    assert_equal <<~PLAIN, out
      Title
      ═════

      Some emphasis, strong, gone, code, and a link (https://example.com/page).

      Section
      ───────

      • one
      • two
        1. inner

      ┃ quoted

          puts "hi" # note

      ┌──────┬──────┐
      │ name │ size │
      ├──────┼──────┤
      │ a    │    1 │
      └──────┴──────┘
    PLAIN
  end

  def test_the_lines_wrap_to_the_width_and_a_table_shrinks_to_it
    long = "word " * 40
    table = "| a | b |\n|---|---|\n| #{'x ' * 20}| #{'y ' * 20}|\n"
    out, err, status = lectern("--width=30", "-", stdin: "> #{long}\n\n- #{long}\n\n#{table}")

    assert_predicate status, :success?, err
    widths = out.lines.map { |line| line.chomp.length }
    assert_operator widths.size, :>, 10
    assert_operator widths.max, :<=, 30
    assert_includes out, "│ x x x"
  end

  def test_a_list_numbers_its_items_and_a_task_list_shows_its_boxes
    out, = lectern("-", stdin: "3. three\n4. four\n\n- [ ] open\n- [x] done\n")

    assert_equal "3. three\n4. four\n\n[ ] open\n[x] done\n", out
  end

  def test_front_matter_is_not_shown_and_a_language_rouge_lacks_is_left_plain
    out, = lectern("--color=always", "-", stdin: "---\ntitle: x\n---\n```nonesuch\nputs 1\n```\n")

    assert_equal "    puts 1\n", out
  end

  def test_a_file_is_read_by_its_name_and_a_missing_one_ends_with_no_input
    Dir.mktmpdir do |dir|
      path = File.join(dir, "notes.md")
      File.write(path, "# Hi\n")

      assert_equal ["Hi\n══\n", true], lectern(path).then { |out, _, status| [out, status.success?] }
      out, err, status = lectern(File.join(dir, "missing.md"))

      assert_equal 66, status.exitstatus
      assert_empty out
      assert_equal "lectern: #{File.join(dir, 'missing.md')}: No such file or directory\n", err
    end
  end

  def test_the_built_app_prints_what_bundle_exec_prints_and_pages_with_no_ruby
    skip "deliver-lectern.ps1 delivers Lectern on Windows in CI" if Gem.win_platform?

    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    platform = Fledge::Platform.local
    unless File.file?(File.join(runtimes, Fledge::Runtimes.file_name(platform)))
      message = "no #{Fledge::Runtimes.file_name(platform)} in #{runtimes}; run bundle exec rake runtime"
      flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
      skip message
    end

    Dir.mktmpdir do |dir|
      out, err, status = Bundler.with_unbundled_env do
        Open3.capture3({ "FLEDGE_RUNTIME_DIR" => runtimes, "FLEDGE_RUNTIME_DIR_UNCHECKED" => "1" }, RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe/fledge"), "build", "-o", dir, EXAMPLE)
      end
      assert_predicate status, :success?, err

      readme = File.join(EXAMPLE, "README.md")
      File.write(File.join(dir, "plain"), lectern(readme).first)
      File.write(File.join(dir, "color"), lectern("--color=always", readme).first)
      archive = out.lines.first.to_s.chomp
      report, status = Open3.capture2e(File.join(ROOT, ".github/scripts/deliver-lectern.sh"), archive, readme, File.join(dir, "plain"), File.join(dir, "color"))
      assert_predicate status, :success?, report
      assert_includes report, "Delivered: Lectern"

      app = File.join(File.dirname(archive), File.basename(archive, ".tar.gz"), "Lectern")
      long = (1..60).map { |n| "line #{n}\n\n" }.join
      paged = on_terminal(long, { "PATH" => "/nonexistent" }, keys: "q", command: [app])
      assert_includes paged, "lines 1-23 of", "the pager of the built app, with no less on PATH"
    end
  end

  def test_a_bad_option_ends_with_usage
    _, err, status = lectern("--nope")

    assert_equal 64, status.exitstatus
    assert_includes err, "invalid option: --nope"
    assert_includes err, "usage: lectern"
  end

  def test_a_terminal_gets_color_and_no_color_leaves_only_attributes
    skip "no pseudo-terminal on Windows" if Gem.win_platform?

    full = on_terminal("*a* `b`\n", { "NO_COLOR" => nil })
    plain = on_terminal("*a* `b`\n", { "NO_COLOR" => "1" })

    assert_includes full, "#{ESC}3ma#{ESC}0m"
    assert_includes full, "#{ESC}33mb#{ESC}0m"
    assert_includes plain, "#{ESC}3ma#{ESC}0m"
    refute_includes plain, "#{ESC}33m"
  end

  def test_a_document_longer_than_the_screen_is_paged_and_a_short_one_is_not
    skip "no pseudo-terminal on Windows" if Gem.win_platform?

    long = (1..60).map { |n| "line #{n}\n\n" }.join
    paged = on_terminal(long, keys: "q")

    assert_includes paged, "\e[?1049h"
    assert_includes paged, "lines 1-23 of"
    assert_includes paged, "\e[?1049l"
    refute_includes on_terminal("short\n"), "\e[?1049h"
  end

  # What the command writes to a pseudo-terminal 24 rows by 80 columns,
  # which it reads the document from as a file and, if it pages, the
  # +keys+ from.
  private def on_terminal(markdown, env = {}, keys: nil, command: [RbConfig.ruby, "-S", "bundle", "exec", "ruby", File.join(EXAMPLE, "main.rb")])
    require "pty"
    require "io/console"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "doc.md")
      File.write(path, markdown)
      output = +""
      Bundler.with_unbundled_env do
        PTY.spawn(BUNDLE.merge("NO_COLOR" => nil).merge(env), *command, path) do |reader, writer, pid|
          reader.winsize = [24, 80]
          begin
            reader.each_char do |char|
              output << char
              next unless keys && output.include?("lines 1-")

              writer.write(keys)
              keys = nil
            end
          rescue Errno::EIO
            nil
          end
          Process.wait(pid)
        end
      end
      output
    end
  end
end
