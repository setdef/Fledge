<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Building from an app already built

An app that [Fledge](../README.md) built already holds a Ruby and your gems, each built for its platform. `fledge build --from APP` copies such an app and puts another project in place of the app's project. A project that needs no other gems becomes an app with nothing else on the computer: no Bundler, no network, and no compiler. This guide is mostly for people who make frameworks, so that their users can make apps without installing Ruby.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build --from dist/Player-arm64-darwin my_game
dist/MyGame-arm64-darwin.tar.gz
```
<!-- SPDX-SnippetEnd -->

The new app runs `my_game`'s program with `Player`'s `Gemfile`, `Gemfile.lock`, and gems. Fledge gives it `my_game`'s name, identity, archive, and installers, as `fledge build` would, and keeps nothing of `Player`'s project or identity.

## What `--from` refuses

- A project with a `Gemfile`, `gems.rb`, or gemspec.
- A project whose `fledge.yml` has `programs`, `linux: system_libraries`, `ios`, or `android`, since for each of those, Fledge would change the Ruby or the gems.
- An app that another Fledge release built, or that Fledge built for another platform. `--from` builds only from an app that the same Fledge release built for the platform you build on.

## Ship an app that builds apps

A framework can publish an app for its users to build from. Put Fledge in the framework's `Gemfile` as an ordinary gem, outside the `development` group, and the app carries Fledge and runs `fledge build --from` on itself.

Some systems lack tools that `--from` needs. On Windows it needs a fresh program, [rcedit](https://github.com/electron/rcedit), and [NSIS](https://nsis.sourceforge.io/), and on Linux an AppImage needs AppImage's runtime. Set `build_tools: true` in the framework's `fledge.yml`, and its app carries them in its `tools` folder. Without them, Fledge takes them from the release's runtime in `FLEDGE_RUNTIME_DIR` or Fledge's cache (see [Runtimes](runtimes.md)), and never downloads them. An app built `--from` carries them only if you set `build_tools` in its `fledge.yml` too.

An AppImage also needs `mksquashfs` on the computer. No app may carry it, since it is under the GPL.
