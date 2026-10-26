<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

Decisions that belong to the maintainer (AGENTS.md, Provenance) wait here. None of them blocks work: each names the default the work proceeds on, chosen to be easy to reverse, and how to reverse it. When a question is answered, record the answer in an ADR or a plan, and remove it from this list.

## 1. What license covers the files Fledge copies into the apps people ship?

**Context.** Fledge's code is AGPL-3.0-or-later, like the maintainer's other projects. Most of Fledge only runs on the developer's machine, so its license binds Fledge and not the apps it builds. But some of Fledge travels inside every app: the C launcher, and any Ruby, scripts, or templates the runtime adds. If those are AGPL-3.0-or-later, every app built with Fledge arguably combines with AGPL code and carries its obligations, including apps whose authors chose a permissive or proprietary license. A game made with Lota, a desktop app made with Tokra, and a terminal tool made with Rooibos would all inherit the question. Prior art leans permissive here: LÖVE, which a fused game ships whole, is Zlib; PyInstaller's bootloader is GPL with an exception that lets it ship inside apps of any license; Ruby's own license and BSD-2-Clause cover the interpreter the runtime ships.

**Default.** Everything in this repository stays AGPL-3.0-or-later, the launcher included, until this is answered. The launcher (`runtime/launcher/`) and the RubyGems defaults file every runtime carries (`runtime/rubygems/operating_system.rb`) now exist under it, and each runtime ships the AGPL text in `notices/fledge/` with a pointer to the source. No runtime has been released, so nothing has shipped to anyone yet.

**Options.** License the runtime files (the launcher and anything else copied into apps) permissively, such as MIT-0 or Zlib, and keep the rest of Fledge AGPL-3.0-or-later; or keep AGPL-3.0-or-later with an exception, in the style of GCC's Runtime Library Exception or PyInstaller's bootloader exception, that lets the runtime files ship inside an app of any license.

**To reverse.** The runtime files already sit in their own directory, `runtime/`; set their SPDX headers and a `REUSE.toml` annotation to the chosen license (adding its text to `LICENSES/`), and update ADR 001's consequences and the README's license section.

## 2. Is an app a folder with a main.rb?

**Context.** `fledge build` needs to know what an app is: which file starts it, what is on its load path, and what gets copied. LÖVE's answer is a folder with a `main.lua`, and Lota follows it with a folder with a `main.rb`. A Ruby developer might instead expect a gem-like layout (`exe/NAME` and `lib/`), a Gemfile, or a configuration file naming the entry point.

**Default.** An app is a folder with a `main.rb`. The launcher runs `main.rb` with the app's folder on the load path, and `fledge build` copies the whole folder. This is what `exe/fledge`'s help header says.

**To reverse.** Change the launcher's entry point and the folder `fledge build` copies, the help header's FILES section, ADR 001, and Plan 001. Adding a configuration file later that names a different entry point would not break apps laid out this way.

## 3. What provenance statement does fledge --help end with?

**Context.** `exe/fledge` follows `codeslurp`'s help header. Below the header, `codeslurp` carries a declare-ai.org creative statement ("created with significant assistance from Amp, using generative AI. The process was human-controlled through creative prompts."). Fledge is *requested*, not human-controlled line by line, so that statement would not be true of it. `exe/fledge` instead carries a plain-English statement: "Fledge is requested: an AI agent built it, with little or no review from a person. Its gates (tests, linters, and delivery to computers that have never seen Ruby) review it instead." The statement sits below the closing `###`, so `fledge --help` does not print it; only someone reading the source sees it.

**Default.** Keep the plain-English statement, in the source only.

**Options.** Use a declare-ai.org statement that fits requested work, if one does; print the statement as part of `fledge --help`; or move it to the README.

**To reverse.** Edit the comment below the `###` line in `exe/fledge`. To print it, move it above the `###` line; `test/cli_test.rb` asserts it is not printed today, so change that test with it.

## 4. Are -V, and help on standard error for a bare fledge, the CLI conventions you want?

**Context.** `fledge --version` has the short form `-V`, as the help header says, while Lota and Rooibos use `-v`. A bare `fledge` with no arguments prints help to standard error and exits 1, as `git` does, while Lota and Rooibos print usage to standard output and exit 0. Both are public CLI surface, and the frameworks that wrap Fledge may want to match it.

**Default.** `-V`, and help to standard error with exit status 1 for a bare `fledge`, as specified for this skeleton. `-V` leaves `-v` free for a future `--verbose`, as Python's and Rust's tools do.

**To reverse.** Change the matching `when` branches in `Fledge::CLI#call`, the help header in `exe/fledge`, `test/cli_test.rb`, and the CHANGELOG entry.

## 5. What is NAME in dist/NAME-PLATFORM?

**Context.** The help header says `fledge build` writes `DIR/NAME-PLATFORM/`, but not where NAME comes from. It becomes the folder and archive name a person downloads, and on Windows likely the executable's name too.

**Default.** NAME is the app folder's base name (`examples/hello` builds `dist/hello-x86_64-linux/`), as LÖVE's fused games take the developer's chosen file name. The launcher inside the folder is renamed to NAME too, so a person runs `hello-x86_64-linux/hello`. An app whose name would collide with a folder in the runtime (`app`, `lib`, `libexec`, `notices`, in any case) is refused with a message asking to rename the folder.

**To reverse.** Add a `--name` option or a configuration file, and update the help header and Plan 001.

## 6. Who cuts releases?

**Context.** Releases are git tags and GitHub Releases, never RubyGems.org (ADR 001, section 7). Ferro lets agents run its tag task once the gate and CI pass for a commit. A release publishes runtimes that other people's apps will carry, which is publishing outside the repository.

**Default.** Only the maintainer tags or releases. Agents may push `trunk` once the gate passes, and nothing else.

**To reverse.** Add a scripted tag task, as Ferro's `release:<name>:tag`, and say in AGENTS.md (Releasing) when agents may run it.

## 7. Is glibc 2.39 an acceptable floor for Linux apps?

**Context.** rv-ruby's Linux builds call functions glibc added in 2.38 and 2.39 (`pidfd_spawnp`, `pidfd_getpid`, `__isoc23_strtol`, `strlcpy`), so an app built on them needs glibc 2.39 or newer: Ubuntu 24.04, Debian 13, and Fedora 40 or newer run it; Debian 12 and Ubuntu 22.04 do not (the Unix launcher spike, Plan 001). Building the launcher in an older image cannot lower the floor, because the requirement comes from rv-ruby's objects.

**Default.** Accept 2.39. Delivery runs on Ubuntu 24.04 and Debian 13; the spike also passed Fedora 43.

**Options.** Ask rv-ruby for builds against an older glibc, or build Ruby ourselves in an older image (ADR 001's fallback).

**To reverse.** Change the pins in `runtime/sources.yml` to older-glibc builds, and add a Delivery job on the oldest distribution you want to reach.

## 8. How should runtimes carry libxcrypt, which is LGPL?

**Context.** On Linux, libruby calls `crypt(3)` (`String#crypt`) from libxcrypt, which is LGPL-2.1-or-later. rv-ruby ships it as a static `libcrypt.a`, and the spike linked that into the launcher, which would put LGPL code inside every app's executable with no way for its recipient to relink it. The license of what ships inside apps is the maintainer's call (question 1).

**Default.** The runtime builds libxcrypt 4.5.2, the release rv-ruby uses, from its pinned source as a shared library with rv-ruby's configure options, ships it as `lib/libcrypt.so.2`, and links the launcher against it with a `DT_RPATH` of `$ORIGIN/lib` (searched before `LD_LIBRARY_PATH`). Its license and source address are in `notices/libxcrypt/`. Delivery checks that the dynamic linker loads the runtime's copy, even with a bogus `libcrypt.so.2` on `LD_LIBRARY_PATH`. A person can replace the file with their own build, which is what the LGPL asks.

**Options.** Link statically and ship the launcher's object files so it can be relinked (LGPL section 6a); link the system's `libcrypt.so.1` (absent on some distributions, such as a minimal Fedora); or build Ruby without `crypt` and make `String#crypt` raise.

**To reverse.** Change `RuntimeBuilder::Linux` in `tasks/runtime_builder.rb` (`build_libxcrypt`, `copy_libcrypt`, and the link line), `runtime/launcher/unix.c`'s comment, the `libxcrypt` notice in `runtime/sources.yml`, and Delivery's libcrypt check in `.github/scripts/deliver.sh`.

## 9. Do runtimes ship Ruby's bundled gems?

**Context.** ADR 001 says the standard library ships whole. Ruby 4.0 splits it in two: default gems (json, openssl, psych, and others), which load with a plain `require`, and bundled gems (csv, bigdecimal, minitest, rbs, and others), which Ruby installs as ordinary gems. The bundled gems are about 20 MB of a 50 MB runtime folder, and an app can name the ones it uses in a Gemfile once vendoring gems exists.

**Default.** Runtimes ship the standard library and default gems, and leave out bundled gems with their caches and docs. `require "csv"` fails in a built app until vendoring gems lands. A macOS runtime archive is 8.6 MB, a Linux one 10 MB.

**To reverse.** Drop the pruning of `gems/`, `specifications/`, and `extensions/` from `RuntimeBuilder.prune_gems` in `tasks/runtime_builder.rb`, and its test.

## 10. Should Ruby see the launcher's path?

**Context.** Inside a built app, `$0`, `__FILE__`, and `$PROGRAM_NAME` are `ROOT/app/main.rb`. Nothing tells the app where the program the person ran lives, or what it is called, which an app needs to restart itself or to print usage with its own name.

**Default.** Nothing is exposed. An app can use `File.expand_path("..", __dir__)` for its folder.

**Options.** An environment variable the launcher sets (such as `FLEDGE_EXECUTABLE`), a constant the launcher defines before `main.rb` runs, or a small Ruby file the launcher requires first.

**To reverse.** Add it in `runtime/launcher/unix.c` (and the Windows launcher), and document it in the README.

## 11. Should apps be able to reach the person's own Ruby environment?

**Context.** The launcher removes every `RUBY*`, `GEM_*`, `GEMRC`, `BUNDLE_*`, and `BUNDLER_*` variable before Ruby starts, so nothing of the person's Ruby changes the app. Child processes the app starts inherit that scrubbed environment, so an app that runs the person's own `ruby` or `bundle` (a developer tool built with Fledge, say) runs it without their settings.

**Default.** Scrub, and keep nothing.

**Options.** Keep the original values under other names (such as `FLEDGE_ORIGINAL_RUBYOPT`) for apps that want to restore them.

**To reverse.** Have `scrub_environment` in `runtime/launcher/unix.c` copy each value to a renamed variable before removing it.

## 12. Is musl Linux (Alpine) out of scope?

**Context.** rv-ruby's musl builds link the standard library's C extensions into its own `bin/ruby` (`--with-static-linked-ext`), and the static libruby it ships has none of them, so a launcher linked against it fails with "cannot load such file -- monitor.so" (the Unix launcher spike). `fledge build` on Alpine says it has no runtime for the platform and asks for `--target`.

**Default.** No musl targets until rv-ruby's musl builds change or Fledge builds Ruby itself.

**To reverse.** Add `x86_64-linux-musl` and `aarch64-linux-musl` to `Fledge::Platform::NAMES`, pins to `runtime/sources.yml`, and runtime and Delivery jobs to CI.

## 13. Is this the fledge build surface you want?

**Context.** `fledge build` gained behavior the help header did not spell out before, all of it public surface.

**Default.**
- A built app's folder holds the program `NAME`, the app in `app/`, Ruby in `lib/`, the CA bundle in `libexec/cert.pem`, and license notices in `notices/` with a `README.txt` index.
- It prints the path of each archive it writes, one per line, on standard output, and download progress on standard error.
- A new build replaces `DIR/NAME-PLATFORM/` and its archive.
- Everything in the app's folder ships except `.git` and the output folder, when the output folder is inside the app's folder. `--out` may not be the app's folder itself.
- `--target=PLATFORM` and `--out=DIR` work as well as the two-word forms, and `--` ends the options.
- The environment variable `FLEDGE_RUNTIME_DIR` names a folder of runtime archives to use instead of downloading; CI and Fledge's own tests use it.
- Downloaded runtimes are kept in `$XDG_CACHE_HOME/fledge/runtimes`, or `~/.cache/fledge/runtimes`, on macOS as on Linux.

**To reverse.** Change `Fledge::CLI::Build`, `Fledge::Runtimes`, `Fledge::App::NEVER_SHIPPED`, the help header in `exe/fledge`, and their tests.

## 14. How should a Fledge version pin its runtimes?

**Context.** ADR 001 says `fledge build` checks each runtime's SHA-256 against the value pinned in the Fledge version that asked for it. But a version's runtimes are built by the release workflow for that version's tag, after the code is tagged, so the tagged code cannot contain their hashes.

**Default.** `release.yml` publishes a `SHA256SUMS` beside the runtimes, and `fledge build` checks each download against it. That catches a damaged download, but not a release whose assets and sums were both replaced.

**Options.** Make runtime builds reproducible, commit their hashes, then tag; or release in two steps, building runtimes from one commit and pinning their hashes in the next, which is tagged; or sign the sums.

**To reverse.** Have `Fledge::Runtimes#pinned_sha256` read hashes from a file in `lib/` instead of the release, and change `release.yml` to match.

## 15. What does hello print on macOS?

**Context.** Plan 001 said hello prints the target's RubyGems platform name. Ruby has no value that is exactly that on every platform: `RUBY_PLATFORM` and `Gem::Platform.local` are `x86_64-linux`, `aarch64-linux`, and (on Windows) `x64-mingw-ucrt`, but on macOS they carry the Darwin version rv-ruby was built for, `arm64-darwin23` and `arm64-darwin-23`.

**Default.** hello prints `RUBY_PLATFORM`, Ruby's own name for where it runs, as the Windows spike also does, so Delivery expects `Hello from Ruby 4.0.9 on arm64-darwin23` on macOS.

**To reverse.** Change `examples/hello/main.rb`, the expected platform in ci.yml's Delivery matrix, and `test/built_app_test.rb`.

## 16. What does a person see when a built app's folder is broken?

**Context.** The launcher can fail before Ruby starts: its folder renamed to `bin` or `lib` (Ruby would then look for its library one folder up), `app/main.rb` missing, or a path too long. A person who ran an app never asked for Ruby, so the message should not be about Ruby.

**Default.** The launcher prints `NAME: message` on standard error, naming the app, and exits with status 70 (`EX_SOFTWARE` from sysexits). An app's own failures exit with the app's status.

**To reverse.** Change `fail` and `EXIT_BROKEN_RUNTIME` in `runtime/launcher/unix.c`.

