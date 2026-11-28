# How Fledge works

You already know how a Ruby program runs on your computer: Ruby is installed, Bundler installs the gems `Gemfile.lock` locks, compiling any that need it, and `bundle exec ruby main.rb` starts the program with those gems set up. Each of those steps needs something the person you'd hand the program to doesn't have: a Ruby, a compiler, and the knowledge to use them. Fledge does those steps once, on your computer, and hands them the result.

## An app is a folder that runs as `bundle exec` does

An app Fledge builds is a folder with four things in it:

- **A runtime:** CRuby, the Ruby you run, built to work from any folder. A Ruby from a version manager or a package manager records the absolute paths it was built for, and links the libraries of the computer it was built on, so a copy of it breaks on another computer. A runtime records no paths, and carries the libraries Ruby needs, such as OpenSSL and libyaml.
- **Your project,** copied whole into the app's `app` folder, as it is on your computer.
- **Its gems,** each the one `Gemfile.lock` locks: a gem from a gem server checked against the lockfile's checksum, a gem from git taken at the commit the lockfile locks, and either one compiled for the runtime's Ruby when it has a C extension.
- **A launcher,** a C program named for your app. It is what a person runs: it starts the runtime's Ruby on your program, in the launcher's process, the way Ruby's `ruby` program does, and sets up the gems the way `bundle exec` does.

Nothing unpacks when the app starts, and nothing is installed: the app starts as `ruby` starts. Moving the folder, or running it from a USB stick, changes nothing.

## The program runs as it does under `ruby`

Fledge's promise is that your program behaves as it does under `ruby main.rb`, or `bundle exec`. The runtime is CRuby, with its whole standard library and every default and bundled gem; C extensions, YJIT, and Ruby's behavior are CRuby's. The launcher passes Ruby the same kind of command line `ruby` gets, sets up Bundler as `bundle exec` does, and puts the runtime's `bin` folder first on `PATH`, so a `ruby` your program starts is the runtime's.

That promise also covers the computer of the person who runs the app. A Ruby they have installed, a `RUBYOPT`, or a `GEM_HOME` in their environment, could otherwise change what your program loads. The launcher sets those variables aside before Ruby starts, and gives them back to your program's `ENV` afterwards, as `bundle exec` leaves them, so that a program your app starts sees the person's settings, and your app's gems never did.

### Where an app differs from `ruby main.rb`

A few differences stay, each because removing it would break the app where it runs. A double-click starts a program with no locale, in which `ruby` reads a folder named outside ASCII as US-ASCII, so the launcher chooses a UTF-8 locale. A person may start the app from any folder, so the launcher runs the program by its absolute path. The person's Ruby settings stay out of the app's boot, so `RUBYOPT` changes nothing there. And a phone forbids things a desktop allows, such as starting a program.

[Differences from `ruby main.rb`](../reference/differences.md) lists every difference your code can observe, on each platform, and what to do about each. Fledge's parity checks, which compare a program in a built app with the same program under Ruby on each platform, fail on any difference not on that list; [Parity](../contributors/design/parity.md) says how they work. Any other difference you find is a bug in Fledge: report it on [the Fledge forum](https://forum.setdef.com/c/fledge).

### What Fledge gives your program: nothing

Fledge adds no module, method, or helper for your program to call, on a desktop or a phone. If your program needs a window, a game loop, or a platform's widgets, that comes from your Ruby code or a gem, the same one you'd use under `ruby`. So the program you test with `ruby main.rb` is the program you ship, and a program built for Fledge runs without it.

## Each platform's app is built on that platform

`fledge build` builds the app for the computer it runs on, and nothing else. A gem's C extension compiles with that platform's compiler, against that platform's libraries; a Mac app is signed with Apple's `codesign`; a Windows app's resources and installer come from Windows tools. Doing each of those on another system means emulating its tools, and an app built that way was never built by the system it is for. So you build the macOS app on a Mac, the Windows app on Windows, and the Linux app on Linux, by hand or with a CI service that has runners of each.

A phone is the exception, because it builds nothing itself: Fledge writes the phone's project on a desktop, and Xcode or Gradle builds the app there.

## Runtimes come from Fledge's release

Fledge's CI builds each platform's runtime, checks what it holds against Fledge's license policy, and publishes it with each release. Each version of the `fledge` gem pins the SHA-256 of its release's runtimes, and `fledge build` downloads the one it needs once, checks it against that pin, and caches it. So every app built with one version of Fledge carries the same runtime, byte for byte, and you need no toolchain to build a Ruby.

Fledge builds its runtimes to a license policy: no GPL code, and LGPL libraries only as separate files a person may replace, with their source published beside the runtime. Each app carries the runtime's notices. Your gems are yours to choose, and their licenses yours to comply with: Fledge judges no gem by its license.

## Fledge checks before it ships

A build fails, with a message that says what to change, when the app would fail on someone else's computer:

- when `Gemfile.lock` doesn't match the `Gemfile`, lacks the checksum of a gem from a gem server, or locks no build of a gem for the platform;
- when a gem's compiled file needs a library that neither every computer of the platform, nor the runtime, nor the gem itself provides, unless `fledge.yml` says where it comes from;
- when a compiled file needs a newer macOS than the app's minimum;
- when the project's `fledge.yml` holds a typo, or a value no system can take.

It warns when a gem's compiled file needs a newer glibc than the runtime's, since the app then runs only on newer Linux distributions.

## What Fledge doesn't do

- **Hide your code.** The app holds your project's Ruby files as they are; anyone can read them.
- **Make one file.** An app is a folder, packed as an archive; a windowed app gets installers too, and its AppImage is one file that runs the app.
- **Update an app.** A new version is a new build; how people get it is up to you or your installer's platform.
- **Build for other platforms.** See [Each platform's app is built on that platform](#each-platforms-app-is-built-on-that-platform).
- **Publish to a store.** For the Microsoft Store, Fledge builds an MSIX package, which you submit. For an iPhone or Android app, it writes the Xcode or Gradle project, which you build, sign, and submit. It builds nothing for the Mac App Store.

## Where Fledge comes from

The design follows programs that ship a runtime beside the program they run: LÖVE's fused games, which join a game to LÖVE's executable so that a player never meets LÖVE or Lua; PyInstaller and Briefcase, which ship a Python program with a Python; and python-build-standalone, whose prebuilt, relocatable Pythons, pinned by hash, are what Fledge's runtimes are to Ruby.
