<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# How a Fledge app differs from running `ruby main.rb`

An app that [Fledge](../README.md) builds runs your code as `ruby main.rb` does, or `bundle exec` for a project with a `Gemfile`: the same requires, globals, `ENV`, standard library, and gems. Fledge's CI runs a built app and `ruby main.rb` side by side on every platform, and fails on any difference not listed with a reason in [`tasks/parity.rb`](../tasks/parity.rb). Here are the differences your code can see, and why each one is there.

## Your program's path

`$0`, `__FILE__`, and `$PROGRAM_NAME` are the absolute path of the program inside the app, where `ruby main.rb` gives the path as you typed it. Your users can start the app from any folder, so a relative path would not hold. `__dir__`, `RbConfig.ruby`, and `Gem.dir` return where your program, its Ruby, and its gems are, as usual.

## Your users' Ruby settings

The app boots the same whatever your users set in `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and the other variables Ruby reads, so a Ruby they installed cannot break it. They still appear in `ENV`, and every program your app starts receives them. You can see the difference in `$VERBOSE`: with `RUBYOPT=-W0`, `ruby main.rb` sets it to `nil`, and the app leaves it as it was.

## Your gems

`Gem.dir` and `Gem.path` name the gem folder inside the app, and never your users' `GEM_HOME` or `~/.gem`. The app sets up the groups `bundle exec` would, `development` and `test` among them, less those your Bundler `without` setting names. Fledge marks the bundle frozen in the app's `.bundle/config`, so Bundler never writes `Gemfile.lock`, even in a read-only folder, and RubyGems loads a defaults file from Fledge at start.

RubyGems still activates a bundled gem your lockfile does not lock, such as `irb`, when your code requires it, as under `bundle exec`. So on macOS and Linux, `binding.irb` works in an app with a `Gemfile`. On Windows it fails in the app and under `bundle exec` alike, because `irb` there needs `fiddle`, and Bundler leaves `fiddle` out of a bundle that does not lock it.

## The locale

On macOS and Linux, a double-click starts a program with no locale variable set, or with `LANG` set to `C` or `POSIX`. Then the launcher, and the Ruby that `RbConfig.ruby` names, use UTF-8, where `ruby` would stay in C. `Encoding.default_external`, `Encoding.find("locale")`, and `Encoding.find("filesystem")` are UTF-8, not US-ASCII. Without this, Ruby and Bundler would fail for a user whose home folder has a name that is not ASCII.

When your users set `LC_ALL` or `LC_CTYPE`, `C` included, the app uses it as `ruby` does, and Fledge adds nothing to `ENV`. To see it, print `Encoding.default_external` from your program, then run the app with `env -i`, and again with `env -i LC_ALL=C`. If this surprises you, [open an issue](https://github.com/setdef/Fledge/issues).

## Windows' ANSI code page

On Windows, the app runs with UTF-8 as its ANSI code page, the character set Windows reads a narrow (`char *`) string in when a program calls a Windows function whose name ends in `A`. `ruby.exe` runs with the system's, such as Windows-1252 on an English or Western European Windows. The app's program declares UTF-8 in its manifest (`activeCodePage`), which Windows 10 version 1903 and later honor.

Without it, a gem that hands Ruby's UTF-8 paths to such a function fails once your users install the app under a folder whose name is not ASCII, such as `C:\Users\José\`. The ffi gem is one: it opens a DLL with `LoadLibraryExA`, so a gem that loads its own DLL through ffi, such as libusb, fails to load there with "The specified module could not be found". It fails the same way under `ruby.exe`, but your users would meet it as an app that does not start.

What you can see from Ruby:

- In a windowed app, `Encoding.locale_charmap` is `"CP65001"` and `Encoding.find("locale")` is UTF-8, where `rubyw.exe` gives the system's code page, such as `"CP1252"` and Windows-1252. A console app takes them from the console's code page, as `ruby.exe` does, and the console's code page stays as it was.
- With `TZ` set to a zone whose name is not ASCII, `Time#zone` is a UTF-8 string, not Windows-1252.
- A C extension's `fopen` and the C runtime's other narrow functions read UTF-8, because the C runtime's locale is UTF-8 too.

`Encoding.default_external` and `Encoding.find("filesystem")` are UTF-8 under `ruby.exe` already, and do not change. The Ruby that `RbConfig.ruby` names is RubyInstaller's `ruby.exe`, which keeps the system's code page, so a gem loaded through ffi from a folder named outside ASCII fails in a Ruby your app starts, as it does under `ruby.exe`. If this surprises you, [open an issue](https://github.com/setdef/Fledge/issues).

## Restarts

On macOS and Linux, `exec RbConfig.ruby, $0, *ARGV` restarts the app as it first started, with the same setup. On Windows, start the app's `NAME.exe` again.

## C headers

The app carries Ruby's C headers, and the library a compiler links against Ruby (a static `libruby` on macOS and Linux, the import library of Ruby's DLL on Windows), so `require "mkmf"`, `find_executable`, `have_func`, and `have_library` work as under `ruby` on a computer with a compiler. They fail in a folder whose path has a space, as they fail under `ruby /path/to/main.rb` there: `mkmf` leaves the program's own folder unquoted in the commands it links with, and on Linux Ruby's own library folder too, so the linker takes the part after the space for a file (`ld: cannot find space/rv/rv-ruby@4.1.0-preview1/4.1.0-preview1/lib` for Ruby itself on Linux, `ld.exe: cannot find Apps/MkmfLinkApp-x64-mingw-ucrt/app` for an app on Windows). Under `ruby main.rb`, typed in the program's own folder, that folder is `.`, which has no space; an app names its program by its whole path, as "Your program's path" says. On a phone, `mkmf` cannot load.

## On a phone

A phone's operating system forbids some things your code can do on a desktop, such as starting a program, and Fledge's Ruby for phones has a few gaps of its own. [What a phone forbids](phones.md#what-a-phone-forbids) lists them for iOS and Android, with what to do instead.

## What a standard Ruby installs and the app does not

On macOS and Linux, Fledge starts from Ruby builds that install `bootsnap` and `msgpack`, and leaves both out of the app. On Windows, the app loads RubyInstaller's library at start, so `defined?(RubyInstaller)` is true as under `ruby.exe`, but runs none of RubyInstaller's start-up: it writes nothing into the app's gem folder, sets no `GEM_HOME`, and never adds MSYS2's DLLs to the app's search.
