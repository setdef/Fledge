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

`Gem.dir` and `Gem.path` name the gem folder inside the app, and never your users' `GEM_HOME` or `~/.gem`. Fledge leaves out the `development` and `test` groups. Fledge marks the bundle frozen in the app's `.bundle/config`, so Bundler never writes `Gemfile.lock`, even in a read-only folder, and RubyGems loads a defaults file from Fledge at start.

RubyGems still activates a bundled gem your lockfile does not lock, such as `irb`, when your code requires it, as under `bundle exec`. So on macOS and Linux, `binding.irb` works in an app with a `Gemfile`. On Windows it fails in the app and under `bundle exec` alike, because `irb` there needs `fiddle`, and Bundler leaves `fiddle` out of a bundle that does not lock it.

## The locale

On macOS and Linux, a double-click starts a program with no locale variable set, or with `LANG` set to `C` or `POSIX`. Then the launcher, and the Ruby that `RbConfig.ruby` names, use UTF-8, where `ruby` would stay in C. `Encoding.default_external`, `Encoding.find("locale")`, and `Encoding.find("filesystem")` are UTF-8, not US-ASCII. Without this, Ruby and Bundler would fail for a user whose home folder has a name that is not ASCII.

When your users set `LC_ALL` or `LC_CTYPE`, `C` included, the app uses it as `ruby` does, and Fledge adds nothing to `ENV`. To see it, print `Encoding.default_external` from your program, then run the app with `env -i`, and again with `env -i LC_ALL=C`. If this surprises you, [open an issue](https://github.com/setdef/Fledge/issues).

## Restarts

On macOS and Linux, `exec RbConfig.ruby, $0, *ARGV` restarts the app as it first started, with the same setup. On Windows, start the app's `NAME.exe` again.

## C headers

The app carries Ruby's C headers, so `require "mkmf"` and `find_executable` work. Fledge leaves out the static and import libraries, so an app cannot compile an extension. On a phone, `mkmf` cannot load.

## What a standard Ruby installs and the app does not

On macOS and Linux, Fledge starts from Ruby builds that install `bootsnap` and `msgpack`, and leaves both out of the app. On Windows, the app does not load RubyInstaller's files at start.
