<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `fledge --help` (`-h`, `-?`) and `fledge --version` (`-v`), on standard output with exit status 0. A bare `fledge` and every usage error print a short usage and `Try 'fledge --help'.` on standard error and exit 2; a failed build exits 1.
- `fledge build [-t PLATFORM]... [-o DIR] [PATH]`: copies the app in PATH into a runtime for each target and writes `DIR/NAME-PLATFORM/` and `DIR/NAME-PLATFORM.tar.gz` (`.zip` for Windows), printing each archive's path. Targets: `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, `x64-mingw-ucrt`.
- Windows (`x64-mingw-ucrt`) apps: `NAME.exe` beside RubyInstaller 4.0.9-1's Ruby in `ruby\`, in a `.zip`, built from any platform.
- Runtimes download from the GitHub Release of Fledge's version into `~/.cache/fledge/runtimes` (or `$XDG_CACHE_HOME/fledge/runtimes`), checked against the release's `SHA256SUMS`; `FLEDGE_RUNTIME_DIR` names a folder of runtimes to use instead.
- Runtimes carry Ruby 4.0.9 from rv-ruby release `20261023` with its standard library, default gems, and bundled gems (not rv-ruby's extra bootsnap and msgpack), Ruby's own `bin/ruby` and the gems' executables, libxcrypt 4.5.2 as a shared library on Linux, libffi 3.5.2 in fiddle on Linux, and license notices in `notices/`. Linux apps need glibc 2.39 or newer.
- The Windows runtime carries Ruby 4.0.9 from RubyInstaller 4.0.9-1 (checked against its PGP signature) with its standard library, default gems, bundled gems, `ruby.exe`, `rubyw.exe`, the gems' wrappers, and DLLs (OpenSSL 3.6.5, libyaml 0.2.5, zlib 1.3.2, GMP 6.3.0, libffi, winpthreads), and Fledge's RubyGems defaults in place of RubyInstaller's.
- A built app runs `app/main.rb` as `ruby main.rb` would: no `-I` for the app's folder (load its files with `require_relative`) and no `--yjit`. The person's `RUBY*`, `GEM_*`, `GEMRC`, `BUNDLE_*`, and `BUNDLER_*` variables are hidden from Ruby's boot and the app's gems are the runtime's, but they are back in `ENV` before `main.rb` runs, so child processes see them.
- A built app's program exits 66 when its `app/main.rb` is missing and 70 when the rest of the runtime is broken, with `NAME: message` on standard error.
