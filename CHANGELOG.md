<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1.pre.3] - 2026-10-27

### Added

- `fledge build` reads every compiled file of every native gem an app ships, and fails, naming the gem, the files, the library, and its license, when one has an LGPL or GPL library compiled in; nokogiri's builds for `arm64-darwin` and `x64-mingw-ucrt` compile in GNU libiconv, so they are refused, and its Linux builds ship.
- Compiled code in a gem Fledge has not reviewed fails the build until `fledge.yml` says what it holds, under `compiled`; sqlite3, nokogiri, ffi, pg, google-protobuf, and prism are reviewed.
- An LGPL library a gem ships as its own shared library, which another of its files loads, ships when `fledge.yml` names its file (`shared_library`) and where its source is (`source`).
- `notices/GEMS.txt` lists, under each gem, the libraries its compiled files hold, their licenses, and their files.
- `blessing` (SQLite), `PostgreSQL`, and `LicenseRef-krb5` (MIT Kerberos's NOTICE) are notice-only licenses.

### Changed

- In an app with a Gemfile, `ENV` is what `bundle exec` gives: Bundler's settings over the person's own, so `RUBYOPT` is `-r.../bundler/setup` followed by the person's `RUBYOPT`, and `BUNDLER_ORIG_*` records the person's values; `Bundler.original_env`, `with_original_env`, `unbundled_env`, and `with_unbundled_env` give the person's environment, with their `RUBYOPT`, `GEM_HOME`, and the rest. They gave an environment without the person's Ruby settings.

## [0.0.1.pre.2] - 2026-10-27

### Added

- `fledge build PATH` builds the program you already run: a file such as `exe/my_cool_app`, `bin/server`, or `main.rb`, or a folder, which means its gemspec's one executable or its `main.rb`. Its project, the nearest folder up with a `Gemfile`, `gems.rb`, gemspec, or `fledge.yml`, ships as `app/`, without `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, or the output folder.
- An app with a Gemfile ships the gems its `Gemfile.lock` locks for each target, without the `development` and `test` groups, installed beside Ruby's own gems, and runs with Bundler set up as `bundle exec` would, with Warbler's settings for a packed app (frozen, system gems, no auto-install, no version switch) in `app/.bundle/config`. The project's gemspecs ship evaluated.
- Gems download from the lockfile's gem server into `~/.cache/fledge/gems` (or `$XDG_CACHE_HOME/fledge/gems`), checked against the lockfile's `CHECKSUMS`; `vendor/cache` and RubyGems' own caches are looked in first.
- `fledge build` refuses, naming each gem and what to do: a target the lockfile does not lock, a gem without a checksum, a gem from git or from a folder outside the project, a gem with an extension that would have to be compiled, a gem that does not support Ruby 4.0.9, a Gemfile `ruby` other than 4.0.9, a lockfile the Gemfile has moved past, and a gem whose license asks more than keeping its notices (or declares none).
- An optional `fledge.yml` at the project's root: `name`, the app's name, and `licenses`, a gem's license where its gemspec declares none or the wrong one.
- `notices/GEMS.txt` in an app with gems: each gem, its license, where it came from, and the text of its license files; `fledge build` warns when a gem ships none.
- A built app's `fledge.cfg`, beside its program, names the program and Gemfile it runs; the program exits 66 when either it or its program is missing, and 70 when it is damaged or Bundler cannot set up the gems.

### Changed

- NAME, the built folder's and the program's name, is the gemspec's name, or else the project folder's, camelized (`my_cool_app` is `MyCoolApp`, `hello` is `Hello`), unless `fledge.yml` names it; it was the app folder's name as it was.
- A build failure may print several `fledge build:` lines, one for each problem.

## [0.0.1.pre.1] - 2026-10-27

### Added

- `fledge --help` (`-h`, `-?`) and `fledge --version` (`-v`), on standard output with exit status 0. A bare `fledge` and every usage error print a short usage and `Try 'fledge --help'.` on standard error and exit 2; a failed build exits 1.
- `fledge build [-t PLATFORM]... [-o DIR] [PATH]`: copies the app in PATH into a runtime for each target and writes `DIR/NAME-PLATFORM/` and `DIR/NAME-PLATFORM.tar.gz` (`.zip` for Windows), printing each archive's path. Targets: `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, `x64-mingw-ucrt`.
- Windows (`x64-mingw-ucrt`) apps: `NAME.exe` beside RubyInstaller 4.0.9-1's Ruby in `ruby\`, in a `.zip`, built from any platform.
- Runtimes download from the GitHub Release of Fledge's version into `~/.cache/fledge/runtimes` (or `$XDG_CACHE_HOME/fledge/runtimes`), checked against the release's `SHA256SUMS`; `FLEDGE_RUNTIME_DIR` names a folder of runtimes to use instead.
- Runtimes carry Ruby 4.0.9 from rv-ruby release `20261023` with its standard library, default gems, and bundled gems (not rv-ruby's extra bootsnap and msgpack), Ruby's own `bin/ruby` and the gems' executables, libxcrypt 4.5.2 as a shared library on Linux, libffi 3.5.2 in fiddle on Linux, and, in `notices/`, `NOTICES.txt` (every component, its license, how it ships, its source, and every license text) and `sbom.spdx.json` (an SPDX 2.3 SBOM), both from the license audit every runtime passes before it is archived. Linux apps need glibc 2.39 or newer.
- The Windows runtime carries Ruby 4.0.9 from RubyInstaller 4.0.9-1 (checked against its PGP signature) with its standard library, default gems, bundled gems, `ruby.exe`, `rubyw.exe`, the gems' wrappers, and DLLs (OpenSSL 3.6.5, libyaml 0.2.5, zlib 1.3.2, GMP 6.3.0, libffi, winpthreads), and Fledge's RubyGems defaults in place of RubyInstaller's.
- A built app runs `app/main.rb` as `ruby main.rb` would: no `-I` for the app's folder (load its files with `require_relative`) and no `--yjit`. The person's `RUBY*`, `GEM_*`, `GEMRC`, `BUNDLE_*`, and `BUNDLER_*` variables are hidden from Ruby's boot and the app's gems are the runtime's, but they are back in `ENV` before `main.rb` runs, so child processes see them.
- A built app's program exits 66 when its `app/main.rb` is missing and 70 when the rest of the runtime is broken, with `NAME: message` on standard error.
- Runtimes leave out nkf's JRuby-only Java sources (`ext/java`), from the gem's folder and from its cached `nkf-0.2.0.gem`.
- Each release attaches, per platform, the runtime, its SBOM (`.spdx.json`) and NOTICES (`-NOTICES.txt`), and for Linux and Windows the source of their LGPL libraries, libxcrypt and GNU MP (`-lgpl-sources.tar.gz`), with `SHA256SUMS` over all of them.
- `doc/licensing.md`: what ships in an app on each platform, under which license, and what each license asks of app developers.

[Unreleased]: https://github.com/setdef/Fledge/compare/v0.0.1.pre.3...HEAD
[0.0.1.pre.3]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.3
[0.0.1.pre.2]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.2
[0.0.1.pre.1]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.1
