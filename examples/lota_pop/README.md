<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Pop Example

The smallest game written with Lota: dots appear, you click or tap them, and a number counts how many you popped.

Lota (github.com/setdef/Lota) is a Ruby library for 2D games, built on the engine of LÖVE and SDL3. A game written with it is a folder of Ruby, and Fledge turns that folder into an app on each desktop and, with Lota's startup files, on iPhone, iPad, and Android. Pop is the least a Lota game can be, so that whatever goes wrong while you try it is about Lota and Fledge, not about the game.

## What it shows

- **A game that is only Ruby.** [`game/main.rb`](game/main.rb) draws circles and reads clicks, and [`game/conf.rb`](game/conf.rb) names the window. [`main.rb`](main.rb) starts the game as Lota's own fuser does. No file in the folder is C, Objective-C, Swift, Java, or Kotlin.
- **A gem that is not on RubyGems.org.** Lota publishes its gems with each release on GitHub. The `Gemfile` asks for `lota` at one version, and the build takes the gem from `vendor/cache`, checked against the SHA-256 in `Gemfile.lock` ([Gems in a Fledge app](../../doc/gems.md)).
- **A framework's own host on a phone.** SDL3 owns a phone's screen and starts the app its own way, so Lota brings the startup files that run Ruby inside SDL. `fledge.yml`'s `ios: host:` and `android: host:` name the folder, and `fledge build` lays those files over the project it writes (`doc/contributors/design/phone-projects.md`, "Host files"). You do not write them: they come in Lota's gem.
- **A windowed app.** `kind: windowed` in `fledge.yml` makes a double-clickable app on each desktop, with no console.

## Get Lota's gems

Lota's source and gems are under the AGPL-3.0-or-later, or a commercial license from setdef; a game built with Lota is distributed under one of them. This example's own files are MIT-0, so you can start your game from them.

Download Lota 0.8.0's gem for your computer, and its source gem for a phone, from [its release](https://github.com/setdef/Lota/releases/tag/v0.8.0) into this folder's `vendor/cache`, and check them against the release's `SHA256SUMS`. For a Mac with Apple silicon:

```sh
mkdir -p vendor/cache
cd vendor/cache
base=https://github.com/setdef/Lota/releases/download/v0.8.0
curl -LO "$base/lota-0.8.0-arm64-darwin.gem"
curl -LO "$base/lota-0.8.0.gem"
curl -LO "$base/SHA256SUMS"
shasum -a 256 --check --ignore-missing SHA256SUMS
cd ..
```

The other desktops' gems are `lota-0.8.0-x86_64-linux-gnu.gem`, `lota-0.8.0-aarch64-linux-gnu.gem`, `lota-0.8.0-x64-mingw-ucrt.gem`, and `lota-0.8.0-aarch64-mingw-ucrt.gem`. [`.github/scripts/lota-pop.sh`](../../.github/scripts/lota-pop.sh) does these steps, with the checksums pinned in it, for CI, and for a phone also unpacks the host:

```sh
.github/scripts/lota-pop.sh examples/lota_pop arm64-darwin   # a desktop
.github/scripts/lota-pop.sh examples/lota_pop                # a phone
```

For a phone, the host is in the source gem, at `ext/lota/phone/host`. Unpack the gem and copy that folder to `host` here, which is what the script does:

```sh
gem unpack vendor/cache/lota-0.8.0.gem --target tmp
cp -R tmp/lota-0.8.0/ext/lota/phone/host host
```

`vendor/cache` and `host` are the project's own files and are kept out of git, since they are Lota's.

## Run it with Ruby

Lota needs Ruby 4.1. In this folder:

```sh
bundle install --local
bundle exec ruby main.rb
```

A window opens with a score and dots that appear one a second, up to five. Click a dot to pop it. `POP_QUIT_AFTER=10 bundle exec ruby main.rb` quits after ten seconds and prints how many you popped, for a check that nobody watches.

## Build it with Fledge

Install Fledge as the README's [Installation](../../README.md#installation) says, in a `Gemfile` of a folder of its own outside this one, and build Pop by its path:

```sh
bundle exec fledge build ~/Fledge/examples/lota_pop
```

On each system, the same command builds that system's app. A phone's project needs the host first, as above:

```sh
bundle exec fledge build ios ~/Fledge/examples/lota_pop
bundle exec fledge build android ~/Fledge/examples/lota_pop
```

Lota's phone engines come prebuilt with its release, and the source gem pins them, so a phone build compiles no SDL3. Open `dist/Pop-ios/Pop.xcodeproj` in Xcode, or run `./gradlew assembleDebug` in `dist/Pop-android`, to build the app. [iPhone, iPad, and Android](../../doc/phones.md) says what each project needs and how to sign and submit it.

## Read the code

- [`game/main.rb`](game/main.rb): the dots, the score, and the click.
- [`game/conf.rb`](game/conf.rb): the window's title and size.
- [`main.rb`](main.rb): the three lines that start the game.
- [`fledge.yml`](fledge.yml): the app's name and identifier, and the two hosts.

## Use this example if you need to

- Start a Lota game that ships through Fledge: copy this folder, give `fledge.yml` your own `name` and `identifier`, and replace `game/`.
- See how a gem that is not on RubyGems.org, and a framework that brings its own phone host, go through `fledge build`.

[Read the source code →](game/main.rb)
