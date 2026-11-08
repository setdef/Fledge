# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# A windowed app, as Fledge packages one, that opens no window.
#
# Lota's games and Tokra's desktop apps open windows through a GUI
# library. This app has none to open, since it is pure Ruby, but it ships
# as a windowed app all the same (its fledge.yml says kind: windowed): an
# .app bundle on macOS, a program Windows starts without a console, and a
# folder with a desktop entry on Linux, each with its name, icon, and
# version. Delivery starts it the way a person would, by Finder's or
# Explorer's means, and cannot read what it prints, so it reports in a
# file instead.
#
# Given a path, it writes there, or into it when it is a folder, as an
# app that opens folders would read them (its fledge.yml lists folders
# under file_associations), as JSON, what it ran on, and lives for
# two seconds, as an app with a window would for at least that long,
# which lets macOS's open -W see it running. It then prints a line
# (which goes nowhere when no one captured its output, and must not fail
# when Windows gave it no console) and exits with the status its second
# argument names, or 0. Without a path it writes to the system's
# temporary folder.
#
# On Windows it also asks Windows, through Fiddle (one of Ruby's bundled
# gems), whether it has a console, which a windowed app must not, and
# what its AppUserModelID is, which Fledge's launcher sets from the
# identifier in fledge.yml. Run from an AppImage, it reports the name of
# the folder the AppImage's runtime ran it from (APPDIR), which says
# whether it was mounted with FUSE (.mount_*) or extracted
# (appimage_extracted_*). Where Ruby has YJIT (macOS and Linux), it
# enables it, as Rails does, and reports whether YJIT wrote machine code,
# which a macOS app signed with the hardened runtime may do only with the
# entitlement Fledge signs it with.

require "json"
require "tmpdir"

report = ARGV.fetch(0) { Dir.tmpdir }
report = File.join(report, "hello_window.json") if File.directory?(report)
facts = {
  "ruby" => RUBY_VERSION,
  "platform" => RUBY_PLATFORM,
  "program" => File.basename($PROGRAM_NAME),
  "folder" => File.basename(__dir__),
  "arguments" => ARGV.length,
}
facts["appdir"] = File.basename(ENV.fetch("APPDIR")) if ENV.key?("APPDIR")
if defined?(RubyVM::YJIT.enable)
  RubyVM::YJIT.enable
  200.times { [1, 2, 3].map { |number| number * 2 }.sum }
  facts["yjit"] = RubyVM::YJIT.runtime_stats.fetch(:inline_code_size).positive?
end
if Gem.win_platform?
  require "fiddle"

  console = Fiddle::Function.new(Fiddle.dlopen("kernel32")["GetConsoleWindow"], [], Fiddle::TYPE_VOIDP)
  facts["console"] = !console.call.null?
  shell32 = Fiddle.dlopen("shell32")
  get_id = Fiddle::Function.new(shell32["GetCurrentProcessExplicitAppUserModelID"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
  out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
  if get_id.call(out).zero?
    wide = out.ptr
    length = 0
    length += 2 until wide[length, 2] == "\0\0"
    facts["app_user_model_id"] = wide[0, length].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
    Fiddle::Function.new(Fiddle.dlopen("ole32")["CoTaskMemFree"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID).call(wide)
  end
end
File.write(report, "#{JSON.generate(facts)}\n")
sleep 2
puts "Hello Window wrote #{report}"
exit Integer(ARGV.fetch(1, "0"))
