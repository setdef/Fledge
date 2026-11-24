<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Drop Example

A file drop for an office or home network, on [Sinatra](https://sinatrarb.com/) and [Puma](https://puma.io/): start it on one computer, and every phone and computer on the network sends it files, and takes them, in a browser.

Moving a file from a phone to the computer beside it, or between two computers that share no account, is a small chore with no small tool. A web server solves it, since every device has a browser, but the person who would run one has no Ruby, and should not have to learn what Puma is. Drop is that server as an app: they start it, it prints an address and a password, and anyone on the network opens the address, signs in, and sends files to the `Drop` folder in that person's home folder, or downloads the files they put there.

## What it shows

- **A server as a console app.** `kind: console` gives Drop a terminal window on every system, which shows the address and the password, and closing it stops Drop ([Serve the computers on your network](../../doc/desktop_apps.md#serve-the-computers-on-your-network)).
- **Gems with compiled extensions.** Puma and its nio4r are C extensions, published only as source, so `fledge build` compiles them for the app's Ruby, and building Drop needs a compiler ([Gems with compiled extensions](../../doc/gems.md#gems-with-compiled-extensions)).
- **Every desktop.** The `Gemfile.lock` locks every platform Fledge builds for, so the same project builds on macOS, on Linux with glibc or musl, and on Windows on x64 or ARM64.
- **What a server on a network needs.** Drop listens on every address, prints this computer's private IPv4 addresses, asks for a password it makes as it starts, refuses forms that other web pages send, writes uploads into the person's home folder and never into the app's own, and sets `$stdout.sync` so what it prints reaches a pipe or a log at once.

## Run it with Ruby

With Ruby 4.1 and a C compiler, in this folder:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
$ bundle exec ruby main.rb
```
<!-- SPDX-SnippetEnd -->

Drop prints where it keeps the files, an address for each of this computer's private addresses, and the password, which is new each time it starts. Open the address on another device, sign in with any user name and that password, and send a file. Press Ctrl-C to stop. With `-o 127.0.0.1`, which keeps Drop to this computer, it prints one address:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec ruby main.rb -o 127.0.0.1
Drop is sharing /Users/you/Drop
On a phone or computer on this network, open
  http://127.0.0.1:4567/
and sign in with the password 4kmwappb (any user name).
Press Ctrl-C to stop.
```
<!-- SPDX-SnippetEnd -->

Drop takes Sinatra's options: `-p PORT` for another port than 4567, Sinatra's, and `-o 127.0.0.1` to keep it to this computer.

> [!WARNING]
> Drop speaks plain HTTP. The password and every file cross the network unencrypted, so run it only on a network you trust.

## Build it with Fledge

Install Fledge as the README's [Installation](../../README.md#installation) says, in a `Gemfile` of a folder of its own outside this one, such as `~/fledge-builder`, and run `bundle install` there. Then, from that folder, build Drop by its path. Here Fledge's repository is in `~/Fledge`, and the build is on a Mac with Apple silicon, with Xcode's command line tools for the compiler:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ~/Fledge/examples/file_drop
Downloading mustermann-3.1.1.gem from https://rubygems.org/
Downloading nio4r-2.7.5.gem from https://rubygems.org/
Downloading puma-8.1.2.gem from https://rubygems.org/
Downloading rack-3.2.9.gem from https://rubygems.org/
Downloading rack-protection-4.2.2.gem from https://rubygems.org/
Downloading rack-session-2.1.2.gem from https://rubygems.org/
Downloading rackup-2.3.1.gem from https://rubygems.org/
Downloading sinatra-4.2.2.gem from https://rubygems.org/
Downloading tilt-2.9.0.gem from https://rubygems.org/
Compiling native gems for arm64-darwin with the runtime's Ruby
Building native extensions. This could take a while...
Building native extensions. This could take a while...
Writing the gems' executables for arm64-darwin
dist/Drop-arm64-darwin.tar.gz
```
<!-- SPDX-SnippetEnd -->

Fledge downloads the gems the lockfile locks, compiles Puma's and nio4r's extensions against the app's own Ruby, and writes the archive, 28 MB, with its `.sha256` beside it. Unpacked, `dist/Drop-arm64-darwin/Drop` starts Drop and takes the same options as `ruby main.rb`.

On each system the same command builds that system's app, once a compiler is there: Xcode's command line tools on a Mac, a C compiler and `make` on Linux, and RubyInstaller's MSYS2 tools (`ridk install`) on Windows. Windows gets `dist/Drop-x64-mingw-ucrt.zip`, holding `Drop.exe` (or `aarch64-mingw-ucrt` on ARM64), and Linux a `.tar.gz` for its processor and C library, such as `dist/Drop-x86_64-linux.tar.gz` or `dist/Drop-aarch64-linux-musl.tar.gz`. Drop is a console app, so it gets an archive and no installer. The first time Drop listens on Windows, Windows Defender Firewall asks whether to let it accept connections from the network.

## Read the code

- [`main.rb`](main.rb): the whole server. The settings at its top say why Drop listens where it does, asks for a password, and refuses other sites' forms. `keep` names an upload safely on any system, and numbers it beside a file of the same name, as a browser numbers a download.
- [`views/layout.erb`](views/layout.erb) and [`views/index.erb`](views/index.erb): the one page, a form to send files and a list to take them, which follows the device's light or dark setting.
- [`fledge.yml`](fledge.yml): why Drop is a console app.

## Use this example if you need to

- Ship a web app that a person starts on their computer and others open from their phones.
- Ship gems that compile a C extension, such as Puma.
- Find the address other devices on the network reach this computer at.
- Keep a small server to the people who know its password.

[Read the source code →](main.rb)
