# Build without reaching GitHub

Each app carries a Fledge runtime, a Ruby built to run from any folder. `fledge build` downloads the runtime for its platform from Fledge's GitHub release the first time it needs it, checks it against the SHA-256 this version of Fledge pins, and keeps it in its cache. This guide covers building on a computer that can't, or shouldn't, reach GitHub.

## Where fledge looks

fledge takes the first of these that applies:

1. **`FLEDGE_RUNTIME_DIR`**, when it is set: a folder of runtime archives. fledge looks there and nowhere else.
2. **The cache**, `$XDG_CACHE_HOME/fledge/runtimes`, or `~/.cache/fledge/runtimes` when `XDG_CACHE_HOME` is not set.
3. **`FLEDGE_RUNTIME_MIRROR`**, when it is set: a server that holds copies of the release's files, which fledge downloads from into the cache, in place of GitHub.
4. **Fledge's release** on GitHub, downloaded into the cache.

Whichever it is, fledge checks the runtime against the SHA-256 this Fledge pins for it, and refuses one that differs: a runtime in the cache that doesn't match is downloaded again, and one from a mirror or a folder fails the build, naming both hashes.

## Fill the cache ahead of time

On a computer that can reach GitHub, one build fills the cache for its platform. Copy `~/.cache/fledge/runtimes` to the same place on the offline computer, and its builds find the runtime there. A runtime's file name carries its version and platform, such as `fledge-runtime-0.17.0-x86_64-linux.tar.gz`, so runtimes of several versions and platforms can share a cache.

## Keep the runtimes in a folder

To keep runtimes with a project, or on a shared drive, download them from [Fledge's release](https://github.com/setdef/Fledge/releases/tag/v0.17.0) into a folder, and point fledge at it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ export FLEDGE_RUNTIME_DIR=/srv/fledge-runtimes
$ bundle exec fledge build
```
<!-- SPDX-SnippetEnd -->

fledge then reads no cache and downloads nothing. A folder that lacks the platform's runtime fails the build, naming the file it expected.

## Mirror the release

A company that proxies downloads can serve the release's files from its own server. fledge downloads `MIRROR/v0.17.0/NAME`, so lay the files out by release tag:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ export FLEDGE_RUNTIME_MIRROR=https://artifacts.example.com/fledge
$ bundle exec fledge build
Downloading fledge-runtime-0.17.0-x86_64-linux.tar.gz from https://artifacts.example.com/fledge/v0.17.0
```
<!-- SPDX-SnippetEnd -->

A mirror that lacks the file, or serves other bytes, fails the build. fledge never falls back to GitHub when a mirror is set, so a build that passes got its runtime from the mirror.

## A runtime you built yourself

A runtime built from Fledge's source has a SHA-256 no release pins. Put it in `FLEDGE_RUNTIME_DIR`, and tell fledge to use it unchecked:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ export FLEDGE_RUNTIME_DIR=~/src/fledge/tmp/runtime
$ export FLEDGE_RUNTIME_DIR_UNCHECKED=1
```
<!-- SPDX-SnippetEnd -->

fledge says on standard error, each time, that it used a runtime unchecked. A Fledge that pins no SHA-256 for its platform's runtime downloads none, and builds only from a runtime folder.

## Gems

The runtime is one download; the gems are others. fledge takes each gem's `.gem` file from the project's `vendor/cache`, from RubyGems' caches, or from its own cache before it downloads it, so `bundle cache --all-platforms` on a connected computer readies a project for an offline one. See [Ship gems from private servers, git, and folders](gem-sources.md).

## Downloads that stall

fledge gives up on a download that moves less than 10,000 bytes a second for 30 seconds, and reports a long download's progress on standard error every 15 seconds. It tries a download that fails for a moment (a dropped connection, a stall, or a server's 408, 429, or 5xx answer) three more times, after 2, 4, and 8 seconds, and never tries again one the server refused. Two builds that need the same file at once download it once: the second waits for the first.
