<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. None of these blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. Should `fledge.yml` carry an app's native libraries for phones?

**Context.** ADR 022 compiles a gem's C and C++ extension and links it into a phone's app. A gem such as Lota's also needs libraries built for the phone (SDL3 as an XCFramework per slice on iOS, and as `libSDL3.so` per ABI, with its Java `SDLActivity`, on Android). What developers control is the maintainer's to set (AGENTS.md, Questions): a `fledge.yml` key naming prebuilt libraries (`ios: frameworks: [...]`, `android: libs: [...]`) that Fledge copies and links into the project would widen it.

**Default.** No key. The gem's `extconf.rb` finds the library by `dir_config` and Bundler's `build.NAME` options, which Fledge passes through, and its flags reach the link; copying a library into the project, and an Android `Activity` other than Fledge's host, are the developer's or the framework's to change in the project Fledge writes (ADR 022, section 6).

**To reverse it.** Add the keys to `Fledge::Config`, copy the named libraries in `MobileProject::IOS` and `Android`, and say so in ADR 022.

**Recommendation (ADR 025, from the SDL3 spike).** No keys for libraries: the `extconf.rb` and `bundle config build.NAME` carried SDL3 to every target, and `fledge build` now links and carries what it links. One key for the host, `ios: host: DIR` and `android: host: DIR`, naming a folder of the project's files that `fledge build` copies over the project it writes (an SDL `main.m` and `Info.plist` change on iOS, an `SDLActivity` and SDL's Java files on Android), since no gem can carry them; without it, a framework changes the project after each build, as `examples/sdl_phone/host/apply.rb` does.
