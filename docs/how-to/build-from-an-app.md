# Build an app from another app

`fledge build --from APP` builds a new app from one fledge already built: it keeps that app's runtime and gems, and takes a new project from the folder you give it. It resolves no gems, compiles none, and downloads no runtime. Use it when the new app's Ruby code differs from the old one's and its gems don't.

## Build from a built app

Say `dist/Engine-x86_64-linux` is an app fledge built, with a game engine's gems. A folder, `../rocket-run`, holds a new game: its `main.rb`, the rest of its Ruby files, and a `fledge.yml`, with no `Gemfile`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Rocket Run
version: "1.0.0"
kind: windowed
identifier: com.example.RocketRun
icon: art/icon
```
<!-- SPDX-SnippetEnd -->

Build it from the engine:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build --from dist/Engine-x86_64-linux ../rocket-run
```
<!-- SPDX-SnippetEnd -->

The new app has the engine's runtime, gems, `Gemfile`, and lockfile, the new project's files, and its own identity, icon, and installers. None of the engine's identity comes along. What the engine's gems need from the system, such as the libraries its `fledge.yml` lists in `system_libraries`, comes along, so the new app checks for them at start, and a `.deb` depends on them.

## What the new project may hold

`--from` takes its gems from the old app, so the new project may not change them:

- no `Gemfile`, `gems.rb`, or gemspec;
- no file at a path the old app takes from its project, such as its `Gemfile.lock` or a gem it carries from a folder;
- no `programs`, and no `system_libraries`, `carried_libraries`, `visual_c_runtime`, `ios`, or `android` in its `fledge.yml`, since each changes the runtime or the gems.

The old app must have been built by this same version of Fledge, for this platform. fledge refuses one built by another version, or for another platform, and says so.

## From inside an app, on a computer with no Ruby

An app that carries Fledge as one of its gems can run `fledge build --from` itself, with the Ruby it carries, to build new apps from itself on a computer with no Ruby installed. Two systems need tools that a computer may lack: Windows needs the runtime's launchers, rcedit, and NSIS, and Linux needs the AppImage runtime for an AppImage. Have the app carry them:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
build_tools: true
```
<!-- SPDX-SnippetEnd -->

The app then holds them in its `tools` folder, and `fledge build --from` uses them in place of the runtime it would otherwise look for. macOS has its tools already. A Windows app built without `build_tools` can still be built from, when this computer has this Fledge's Windows runtime in its cache or in `FLEDGE_RUNTIME_DIR`.

An app built with `--from` carries the tools only when its own `fledge.yml` sets `build_tools` too.

## On macOS

The new app gets a bundle of its own, with its `Info.plist` and signature. fledge copies the old app's launcher and signs the copy ad hoc before it uses it, so nothing of the old app's signature carries over. Sign the new app as any other, with `--sign`.
