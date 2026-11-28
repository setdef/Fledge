# Tutorial: ship a command-line tool

In this tutorial we write a two-line Ruby program, build it into an app with Fledge, and run that app the way someone without Ruby would. Along the way we give it a proper name, add a gem, and get it ready to hand over.

You need:

- a computer running Linux, macOS on Apple silicon, or Windows (the [platforms reference](reference/platforms.md) lists them all);
- Ruby 4.1, the Ruby Fledge's runtime has, with the Bundler it comes with. On macOS or Linux, a version manager installs it: with [mise](https://mise.jdx.dev), `mise use ruby@4.1.0-preview1`. On Windows, install the head build of [RubyInstaller](https://github.com/oneclick/rubyinstaller2), `rubyinstaller-head`, the Ruby 4.1 that Fledge's Windows runtime is made from;
- [Git](https://git-scm.com), on your `PATH`, which Bundler runs to fetch Fledge from GitHub.

The commands and output here are from x86-64 Linux. On another platform, file names end in that platform's name instead of `x86_64-linux`, a Windows app is a `.zip` with `greet.exe` in it, and the shell commands are your system's.

If you get stuck, ask on [the Fledge forum](https://forum.setdef.com/c/fledge). Paste the command you ran and everything it printed.

## Write the program

Make a folder for the project, and a program in it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ mkdir greet
$ cd greet
```
<!-- SPDX-SnippetEnd -->

Save this as `main.rb`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
name = ARGV.first || "world"
puts "Hello, #{name}!"
```
<!-- SPDX-SnippetEnd -->

Run it with your Ruby, so we know what it should do:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ ruby main.rb Ada
Hello, Ada!
```
<!-- SPDX-SnippetEnd -->

This is the program we'll ship, unchanged: the app runs `main.rb` as `ruby main.rb` does.

## Add Fledge to the project

Fledge is a gem, and a project's gems are listed in its `Gemfile`. Save this as `Gemfile`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
source "https://rubygems.org"

gem "fledge", github: "setdef/Fledge", tag: "v0.17.0"
```
<!-- SPDX-SnippetEnd -->

With `github:` and `tag:`, Bundler takes the gem from Fledge's repository on GitHub, at the release's tag, rather than from rubygems.org. Install it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
```
<!-- SPDX-SnippetEnd -->

Bundler clones the repository with Git, and writes `Gemfile.lock`, which holds every gem's exact version, the platforms the lockfile covers, a checksum for each gem from a gem server, and the commit of each gem from git. Fledge ships exactly the gems `Gemfile.lock` locks, checks each `.gem` file against its checksum, and takes each gem from git at its locked commit, so the app holds what you tested.

> **Why the tag?** Each Fledge release pins, by SHA-256, the runtimes it builds with. A release's tag gives you a Fledge whose pins match its release's runtimes. Fledge itself becomes one of the app's gems; it is plain Ruby, and the app never runs it.

## Build the app

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
Downloading fledge-runtime-0.17.0-x86_64-linux.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.17.0
Writing the gems' executables for x86_64-linux
dist/Greet-x86_64-linux.tar.gz
```
<!-- SPDX-SnippetEnd -->

The first line is the slow one. A Fledge runtime is a complete Ruby, built to run from any folder, and fledge downloads it once per platform, checks it against the SHA-256 this Fledge pins for it, and keeps it in `~/.cache/fledge`. Later builds reuse it.

The last line is the only one on standard output: the path of each file fledge wrote that you would hand to someone. Everything else is on standard error, so a script can read the paths alone.

Let's see what is in `dist`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ ls dist
CACHEDIR.TAG  Greet-x86_64-linux  Greet-x86_64-linux.tar.gz  Greet-x86_64-linux.tar.gz.sha256
```
<!-- SPDX-SnippetEnd -->

- `Greet-x86_64-linux` is the app: a folder that holds the program, the project, and the runtime.
- `Greet-x86_64-linux.tar.gz` is that folder packed for sending.
- `Greet-x86_64-linux.tar.gz.sha256` holds the archive's SHA-256, so the person you send it to can check it arrived whole.
- `CACHEDIR.TAG` marks `dist` as a folder of build output, so that backups skip it, and so that the next build leaves it out of the app.

## Run it as someone without Ruby would

Unpack the archive somewhere else, and run the program in it with an environment that has no Ruby: `env -i` empties the environment, and `PATH=/usr/bin:/bin` leaves only the system's programs.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ mkdir -p /tmp/elsewhere
$ tar -xzf dist/Greet-x86_64-linux.tar.gz -C /tmp/elsewhere
$ env -i PATH=/usr/bin:/bin /tmp/elsewhere/Greet-x86_64-linux/Greet Ada
Hello, Ada!
```
<!-- SPDX-SnippetEnd -->

That is the whole app. It works from any folder, on any computer of the same platform, whether it has a Ruby or not, and any Ruby it does have changes nothing in it.

## Give it a proper name

There is a problem: the program is called `Greet`. Fledge named the app for the project's folder, camelized, as Bundler names a gem's module. That suits a windowed app, but people type a command-line tool's name, and they expect `greet`.

How an app presents itself is what `fledge.yml` is for. Save this in the project's folder, beside the `Gemfile`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: greet
version: "1.0.0"
```
<!-- SPDX-SnippetEnd -->

Build again:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
Writing the gems' executables for x86_64-linux
dist/greet-x86_64-linux.tar.gz
```
<!-- SPDX-SnippetEnd -->

No download this time. The app, its folder, and its program are now all `greet`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ tar -xzf dist/greet-x86_64-linux.tar.gz -C /tmp/elsewhere
$ env -i PATH=/usr/bin:/bin /tmp/elsewhere/greet-x86_64-linux/greet
Hello, world!
```
<!-- SPDX-SnippetEnd -->

The old `Greet` build is still in `dist`; fledge replaces only a build of the same name. Delete it whenever you like.

Look inside the app folder:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ ls /tmp/elsewhere/greet-x86_64-linux
app  bin  fledge.cfg  greet  include  lib  libexec  notices
```
<!-- SPDX-SnippetEnd -->

- `greet` is the program a person runs: Fledge's launcher, renamed for the app.
- `app` holds a copy of your project, `main.rb` and the `Gemfile` among them.
- `fledge.cfg` tells the launcher what to run.
- `bin`, `include`, `lib`, and `libexec` are the runtime's Ruby, and the gems.
- `notices` holds the licenses and notices of everything in the runtime.

The app takes the whole project folder, so anything you leave there ships too. Keep scratch files out of the project, or in a folder you mark with a `CACHEDIR.TAG`, as `dist` is.

Here is what the launcher reads:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ cat /tmp/elsewhere/greet-x86_64-linux/fledge.cfg
# Written by fledge build 0.17.0 for x86_64-linux: what this app's program runs.
# Needs glibc 2.28 or newer, the newest any of its compiled files needs.
entry = main.rb
gemfile = Gemfile
```
<!-- SPDX-SnippetEnd -->

The launcher starts Ruby on `app/main.rb`, with the `Gemfile`'s gems set up as `bundle exec` sets them up. The second line is for you: this app runs on any x86-64 Linux with glibc 2.28 or newer, such as Debian 10, AlmaLinux 8, and Ubuntu 20.04, and the releases after them. A gem whose compiled code needs a newer glibc raises that line, and fledge warns you when it does.

Before we go on, predict: if `main.rb` raised an exception, what would the person running `greet` see, and what exit status would their shell get? Try it with `raise "oops"` at the end of `main.rb`, build, and run. You'll find what `ruby main.rb` gives you: Ruby's message and backtrace, and status 1. The app's exit status is the program's, so scripts that call `greet` can rely on it. Take the `raise` out again before you go on.

## Use a gem

Most programs need gems. Let's color the greeting with [Rainbow](https://rubygems.org/gems/rainbow). Add it to the `Gemfile`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
source "https://rubygems.org"

gem "rainbow"
gem "fledge", github: "setdef/Fledge", tag: "v0.17.0"
```
<!-- SPDX-SnippetEnd -->

And use it in `main.rb`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "rainbow"

name = ARGV.first || "world"
puts Rainbow("Hello, #{name}!").green
```
<!-- SPDX-SnippetEnd -->

Then install, and build:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
$ bundle exec fledge build
Writing the gems' executables for x86_64-linux
dist/greet-x86_64-linux.tar.gz
```
<!-- SPDX-SnippetEnd -->

Nothing about Rainbow, and yet the app has it. `bundle install` left Rainbow's `.gem` file in your Ruby's gem cache; fledge found it there, checked it against the SHA-256 in `Gemfile.lock`'s `CHECKSUMS` section, and installed it into the app as RubyGems would. A gem it can't find in a cache, it downloads, and says so. It never copies the gem your Ruby installed: a gem with a C extension compiles for the app's Ruby, so fledge installs every gem from its `.gem` file. The program now prints its greeting in green, with no Ruby on the computer.

A gem with a C extension takes one more thing: a compiler, on the computer that builds. See [Ship gems with C extensions](how-to/native-gems.md).

## Hand it over

Send the archive and its `.sha256` file. The person you send them to checks the archive, unpacks it, and runs the program:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ sha256sum -c greet-x86_64-linux.tar.gz.sha256
greet-x86_64-linux.tar.gz: OK
$ tar -xzf greet-x86_64-linux.tar.gz
$ ./greet-x86_64-linux/greet Ada
Hello, Ada!
```
<!-- SPDX-SnippetEnd -->

On macOS the check is `shasum -a 256 -c`, and on Windows, `Get-FileHash` in PowerShell prints the hash to compare.

To ship the same tool for macOS and Windows, run `bundle exec fledge build` on a Mac and on a Windows computer, by hand or on a CI service's runners: each platform's app is built on a computer of that platform. [Platforms](reference/platforms.md) lists what each one needs.

## What's next

You can now build a Ruby program into an app, rename it with `fledge.yml`, ship its gems, and check the result on a computer with no Ruby. Next, [make a windowed app](how-to/windowed-app.md) with an icon and installers, or browse [the guides](how-to/README.md).
