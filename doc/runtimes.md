<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Runtimes and Ruby versions

A runtime is the copy of Ruby that [Fledge](../README.md) puts in each app: CRuby, its standard library, its bundled gems, and the launcher, built to run from any folder on one platform.

## Which Ruby your app gets

Your app gets the Ruby you run Fledge with. Fledge has a runtime for each Ruby it supports, Ruby 4.0 today, at the patch level on the [README](../README.md)'s Ruby badge. On a Ruby it has no runtime for, such as a 4.1 preview, `fledge build` stops and says so.

Name your Ruby in a `.ruby-version` file, which version managers and CI's [`setup-ruby`](https://github.com/ruby/setup-ruby) read, so that every computer that builds your app builds it with the same Ruby. With `ruby file: ".ruby-version"` in your `Gemfile`, Bundler holds every computer to it too.

## Where runtimes come from

The first time you build for a platform, Fledge downloads its runtime from Fledge's [GitHub Release](https://github.com/setdef/Fledge/releases), checks it against the SHA-256 that Fledge carries for it, and keeps it in `~/.cache/fledge` (or `$XDG_CACHE_HOME/fledge`). A download that fails for a moment, with a server error or a broken connection, is tried again after 2, 4, and 8 seconds; one the server does not have, or that does not match, stops the build at once. The gems your app locks download the same way. Because of the check, any copy of the release is as good as the release:

- **A server of yours.** Copy the release's files to it, one folder per tag, as `vVERSION/NAME`, and set `FLEDGE_RUNTIME_MIRROR` to its address, such as `https://files.example.com/fledge`. Fledge stops the build on a file that does not match or that the server lacks.
- **No network.** Set `FLEDGE_RUNTIME_DIR` to a folder of runtime archives, and Fledge never downloads one.

## Updating Fledge

Change the tag in your `Gemfile` and run `bundle update fledge`. Each version of Fledge pins the SHA-256 of every runtime it downloads.

A new version of Fledge may move your app's Ruby to a newer patch, such as 4.0.9 to 4.0.10, and you'll find each move in the [CHANGELOG](../CHANGELOG.md). Only you move it to another minor version, by running Fledge with that Ruby.

Fledge is 0.x today, so any new version can break your build. Read the CHANGELOG before you update.

### What 1.x keeps

From 1.0, Fledge follows [Semantic Versioning](https://semver.org/). In a minor version, Fledge only adds: a new option, `fledge.yml` key, or installer, and your build stays as it was until you choose to use it. In a patch, Fledge only fixes. Only a major version, such as 2.0, changes any of these:

- **The command.** `fledge build`, its options and their defaults, its exit statuses, and the paths it prints on standard output, one per line.
- **`fledge.yml`.** Every key, the values each accepts, and each default.
- **The files `fledge build` writes.** The app's folder, its archive, each installer, the `.sha256` beside each, and their names.
- **What your code and your users meet in a built app.** Each program's name and place, your project in `app/`, the `notices/` folder, a Mac app's `NAME.app`, a Linux app's desktop entry and icons, and the folder each installer puts the app in.
- **How your code runs.** Fledge may remove a [difference from `ruby main.rb`](differences_from_ruby.md), but never add one.
- **Ruby and the systems your users run.** Every Ruby minor version 1.0 has a runtime for, Ruby 4.0 today, and the oldest system each platform runs on, as the [compatibility table](../README.md#compatibility) lists them.
- **Phone projects.** The folders of the project Fledge writes, the files in it you may replace, and the functions your host code calls to start Ruby.
- **Runtime downloads.** The names of the release's files, `FLEDGE_RUNTIME_DIR`, and `FLEDGE_RUNTIME_MIRROR`.

Any version may change what you should not depend on:

- **Where the runtime sits inside an app.** Ask Ruby where things are, with `__dir__`, `RbConfig.ruby`, and `Gem.dir`, and your code keeps working when Fledge moves a folder, as it might to meet a store's rules.
- **What `fledge build` prints on standard error.** Fledge improves its messages from release to release. A script that runs Fledge should check its exit status and read standard output.
- **Fledge's Ruby classes.** Run the `fledge` command, and don't call `Fledge::` code from your own.
