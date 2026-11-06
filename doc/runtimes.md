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

The first time you build for a platform, Fledge downloads its runtime from Fledge's [GitHub Release](https://github.com/setdef/Fledge/releases), checks it against the SHA-256 that Fledge carries for it, and keeps it in `~/.cache/fledge` (or `$XDG_CACHE_HOME/fledge`). Because of that check, any copy of the release is as good as the release:

- **A server of yours.** Copy the release's files to it, one folder per tag, as `vVERSION/NAME`, and set `FLEDGE_RUNTIME_MIRROR` to its address, such as `https://files.example.com/fledge`. Fledge stops the build on a file that does not match or that the server lacks.
- **No network.** Set `FLEDGE_RUNTIME_DIR` to a folder of runtime archives, and Fledge never downloads one.

## Updating Fledge

Change the tag in your `Gemfile` and run `bundle update fledge`. Each version of Fledge pins the SHA-256 of every runtime it downloads.

A new version of Fledge may move your app's Ruby to a newer patch, such as 4.0.9 to 4.0.10, and you'll find each move in the [CHANGELOG](../CHANGELOG.md). Only you move it to another minor version, by running Fledge with that Ruby.

Fledge is 0.x, so a minor version can break your build: read the CHANGELOG before you update. From 1.0, Fledge will change the command, `fledge.yml`, or what a built app holds only in a major version.
