<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Hello Example

The smallest app Fledge builds: one `main.rb` that greets you and exits.

Before you ship a real program, you want to see the whole road once: a script you run with `ruby main.rb`, turned into an app that runs on a computer with no Ruby, and on a phone. Hello is that script, with nothing else in the way. It has no `Gemfile` and no gems, only a `fledge.yml` of one line, so whatever goes wrong while you try it is about Fledge and your computer, not about the app.

## What it shows

- **A lone script.** Hello is a `main.rb` with no `Gemfile` or gemspec. Fledge builds `main.rb` when a folder names no other program.
- **A project's root.** Fledge ships the program's project: the nearest folder, from the program's up, with a `Gemfile`, `gems.rb`, a gemspec, or a `fledge.yml`. Hello sits inside Fledge's own repository, under Fledge's `Gemfile`, so its `fledge.yml` is what makes `examples/hello` the project, and keeps the rest of Fledge's repository out of the app. Everything in that folder ships, in the app's `app/`, this README too.
- **A name from the folder.** `fledge.yml` gives no `name`, and `main.rb` names no command, so the app is named for its folder, as written: `hello`.
- **An identifier, for a phone.** `fledge.yml`'s one key, `identifier: com.setdef.fledge.Hello`, is what iOS and Android know the app by. A desktop's console app needs none; a phone's project does.
- **Ruby's own extensions.** `main.rb` sends its line through `JSON`, a C extension of Ruby's standard library, so the line prints only when the app's Ruby loads its extensions.
- **An exit status.** `main.rb` exits with the number you pass it, and the app exits with the same status, as `ruby main.rb` does.

## Run it with Ruby

In this folder:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ ruby main.rb
Hello from Ruby 4.1.0 on arm64-darwin27
$ ruby main.rb 3; echo $?
Hello from Ruby 4.1.0 on arm64-darwin27
3
```
<!-- SPDX-SnippetEnd -->

The line names `RUBY_VERSION` and `RUBY_PLATFORM`, so yours names your Ruby and your system.

## Build it with Fledge

Install Fledge as the README's [Installation](../../README.md#installation) says, in a `Gemfile` of a folder of its own outside this one, such as `~/fledge-builder`, and run `bundle install` there. Hello has no `Gemfile` to add Fledge to, so from that folder, build Hello by its path. Here Fledge's repository is in `~/Fledge`, and the build is on a Mac with Apple silicon:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ~/Fledge/examples/hello
Downloading fledge-runtime-0.17.0-arm64-darwin.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.17.0
dist/hello-arm64-darwin.tar.gz
$ dist/hello-arm64-darwin/hello 3; echo $?
Hello from Ruby 4.1.0 on arm64-darwin23
3
```
<!-- SPDX-SnippetEnd -->

The first build on a computer downloads the runtime, the Ruby Fledge puts in the app, and later builds reuse it. Fledge writes the app to `dist` in the folder you run it from: the archive, 25 MB, its `.sha256` beside it, and the app unpacked in `dist/hello-arm64-darwin/`, where `hello` runs `main.rb`. The app's Ruby names the macOS its runtime was built on, so its platform differs from your own Ruby's.

On each system, the same command builds that system's app: `dist/hello-x64-mingw-ucrt.zip`, which holds `hello.exe`, on Windows on x64, and a `.tar.gz` for your processor on Linux, such as `dist/hello-x86_64-linux.tar.gz`. Hello is a console app, so it gets an archive and no installer.

For a phone, name it first. On a Mac, `fledge build ios` writes an Xcode project, and on a Mac, Linux, or Windows, `fledge build android` writes a Gradle project:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ios ~/Fledge/examples/hello
Downloading fledge-runtime-0.17.0-ios.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.17.0
dist/Hello-ios
$ bundle exec fledge build android ~/Fledge/examples/hello
Downloading fledge-runtime-0.17.0-android.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.17.0
dist/Hello-android
```
<!-- SPDX-SnippetEnd -->

Open `dist/Hello-ios/Hello.xcodeproj` in Xcode, or run `./gradlew assembleDebug` in `dist/Hello-android`, to build the app. On the phone, Hello shows its name on one screen, and its line goes to the system log, since a phone has no terminal. [iPhone, iPad, and Android](../../doc/phones.md) says what each project needs and how to sign and submit it.

## Read the code

- [`main.rb`](main.rb): the four lines that run, and a comment on why each is there.
- [`fledge.yml`](fledge.yml): the one key, and why the file is there at all.

## Use this example if you need to

- See Fledge build an app before you point it at your own program.
- Build a lone script that has no `Gemfile`.
- Check that a computer has what `fledge build` needs, or that a phone's tools write and build Fledge's project.
- Start a new app from nothing: copy this folder, give `fledge.yml` your own `name` and `identifier`, and add a `Gemfile` when you need a gem.

[Read the source code →](main.rb)
