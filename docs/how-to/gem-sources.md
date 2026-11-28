# Ship gems from private servers, git, and folders

fledge ships the gems `Gemfile.lock` locks, from wherever the lockfile says they come from: a gem server, a git repository, or a folder. This guide covers what each needs.

Fledge reads the lockfile as `bundle install --frozen` would. When the `Gemfile` has moved past it, or a gem it needs is missing, fledge says so in Bundler's words, and you run `bundle lock` and build again.

## Gems from a gem server

fledge checks every gem it ships against the SHA-256 in the lockfile's `CHECKSUMS` section. Bundler 4 writes checksums for a new lockfile. For an older lockfile, add them:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle lock --add-checksums
```
<!-- SPDX-SnippetEnd -->

fledge looks for each `.gem` file, in order, in the project's `vendor/cache`, in RubyGems' caches, and in its cache, and uses the first whose SHA-256 matches. Otherwise it downloads the file from the server the lockfile lists. A file whose SHA-256 differs from the lockfile's is refused, wherever it came from.

### A private server

fledge logs in to a server with the credentials Bundler has for it, so a project that installs with Bundler builds with fledge:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle config set --local gems.example.com USER:PASSWORD
```
<!-- SPDX-SnippetEnd -->

Bundler also reads them from an environment variable named for the host, such as `BUNDLE_GEMS__EXAMPLE__COM`. fledge sends the credentials only to that host, and never prints them. When the server refuses, fledge says whether it had a login, and how to set or check one.

### No network, or a gem no server has

Put the `.gem` files in the project's `vendor/cache`, as `bundle cache --all-platforms` does, and fledge takes them from there. `vendor/cache` stays out of the app's copy of the project.

A version that only a Ruby ships, as a default gem, is one no server holds, and the lockfile can have no checksum for it. fledge says so; pin the gem in the `Gemfile` to a released version, and lock again.

## Gems from git

fledge takes a git gem at the full commit the lockfile locks, never at a branch's newest commit, and clones the repository into its cache. It needs `git` on `PATH`. A gem whose `Gemfile` line asks for `submodules: true` gets them, at the commits the repository locks. The app holds the gem where Bundler keeps git gems, so `bundle exec` in the app finds it there.

## Gems from a folder

A gem from a folder (`path:` in the `Gemfile`) ships with the project when the folder is inside the project. One with a C extension compiles for the runtime's Ruby, wherever it is, and the compiled files replace any you compiled for your Ruby.

A gem from a folder outside the project ships where Bundler looks for its copy, in `vendor/cache`. fledge takes the gem from the project's `vendor/cache` when you keep a copy there, or else from the folder in the `Gemfile`'s `path:`. The path must end in the folder's name, since the copy takes that name: `path: "../my-gem"` works, and `path: ".."` does not.

## Which gems ship

fledge ships the gems `bundle exec` would set up on the platform it builds for:

- Development and test gems ship, since `bundle exec` sets them up. Leave a group out with Bundler's setting, as on any computer: `bundle config set --local without development test`.
- An optional group (`group :tools, optional: true`) ships only when you ask for it, with `bundle config set --local with tools`.
- A gem limited to other platforms, such as `platforms: :windows`, ships only in that platform's app.
- A gem the runtime's Ruby already has, at the same version, is the runtime's.

The app's `.bundle/config` carries these choices, so `bundle exec` inside the app sets up the same gems.

## The Bundler version

When `Gemfile.lock` says `BUNDLED WITH` a version other than the runtime's Bundler, the app ships that Bundler and runs with it, as `bundle exec` would. Its checksum must be in the lockfile too, which Bundler writes only for a Bundler it installed as a gem: run `gem install bundler -v VERSION`, then `bundle lock --add-checksums`.
