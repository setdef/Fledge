<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `fledge.yml`'s `linux: system_typelibs`, the GObject introspection typelibs an app's gems load from the Linux distribution by namespace and version, such as `Gtk-4.0` for ruby-gnome's gtk4: started on a computer that lacks one, or a typelib it needs, the app names it and exits with status 72 before Ruby starts, where it stopped with Ruby's `GObjectIntrospection::RepositoryError` from inside the gem. A `.deb` depends on each one's `gir1.2-` package.
- `fledge.yml`'s `macos: carried_libraries`, for a gem that links a library from the developer's Mac, such as one Homebrew installed: `fledge build` copies each library listed from where the gem's files find it into the app's `lib/carried`, points the files that need it at the copy, and refuses a library that one of them needs and the list leaves out, one for another processor or a newer macOS than the app's, and one listed that nothing needs. Without the key, the refusal of such a gem names it.

### Changed

- A gem whose extension fails to compile shows its build output and a sentence naming the gem, with no Ruby backtrace of Fledge's compile script.
- **Breaking:** `fledge build android` refuses every app whose `build.gradle` sets `useLegacyPackaging = false` or sets none, not only an app with a gem's C or C++ extension, since Ruby's own extensions and encodings are now native libraries the package installer must extract.
- The Android runtime's Ruby is a shared library, `libfledgeruby.so`, with each extension of Ruby's standard library and bundled gems, and each encoding table, a native library of its own in `FledgeRuby.aar`, which an app's Ruby loads from the path a desktop's has it, so `$LOADED_FEATURES` and `RbConfig::CONFIG["archdir"]` are as under `ruby main.rb`; OpenSSL, libyaml, and libffi are in `openssl.so`, `psych.so`, and `fiddle.so`, no longer in `libfledgeruby.so`.
- On Android, RubyGems keeps a gem's compiled extension under `extensions/PLATFORM/4.1.0+5/`, as on a desktop Linux, where it was `4.1.0+5-static/`.
- The `x86_64-linux` and `aarch64-linux` runtimes take their Ruby 4.1.0-preview1 from jdx/ruby's build in place of rv-ruby's, so their openssl, zlib, and fiddle extensions carry OpenSSL 3.5.5, zlib 1.3.1, and libffi 3.5.1 (rv-ruby's carried OpenSSL 3.6.2, zlib 1.3.2, and libffi 3.5.2), and Fledge's launcher, `bin/ruby`, and libxcrypt in them are compiled in manylinux_2_28, so that no file of the runtime needs a glibc newer than 2.28.
- A glibc Linux app (`x86_64-linux`, `aarch64-linux`) runs on glibc 2.28 or newer, such as RHEL 8, Debian 10, and Ubuntu 20.04, where it needed 2.39.
- A gem compiled on a Linux whose glibc is newer than 2.28 no longer fails `fledge build`: the build warns that the app needs that glibc, and the app's `.deb` depends on it.
- A glibc Linux app trusts the computer's own CA certificates, as other Linux programs do, and the certificates it carries only on a computer with none.
- On Windows, `fledge build` counts a DLL of the runtime's as provided only where the app's Ruby looks for it, in `ruby_builtin_dlls`, Ruby's architecture folder, and Ruby's own DLL, and refuses a gem that needs one the runtime holds only elsewhere, such as beside another gem's extension, which before built an app that stopped at `require`.

### Fixed

- An `extconf.rb` that uses RubyGems, as sassc's reads `Gem::Platform.local`, compiles for iOS and Android.
- On iOS, a library for ffi that a gem's `extconf.rb` builds with no Init function, such as sassc's libsass, is embedded as a framework at the path the gem opens.
- On Android, a gem's build that runs `strip`, as sassc's does, runs the NDK's, which reads Android's libraries.
- On Windows, a gem compiled from source against MSYS2's libffi or zlib loads in the app, as under `bundle exec`: the app's Ruby searches Ruby's architecture folder for DLLs, as RubyInstaller's start-up does, and the Windows runtimes carry the fiddle gem's `libffi-8.dll` in `ruby_builtin_dlls` too. Before, an app over ffi, and so over every gem that goes through it, or over rugged, stopped at `require` with "126: The specified module could not be found".

## [0.17.0] - 2026-11-22

### Added

- `fledge.yml`'s `windows: visual_c_runtime`, for a gem whose DLL needs Microsoft's Visual C++ runtime: `local` copies the runtime's DLLs the gems need from the building computer's System32 into the app, and `central` ships none, for computers that have the Visual C++ Redistributable; started on a computer without it, such an app names the Redistributable and Microsoft's download and exits with status 72, before Ruby starts.
- An MSIX package of an app built with `windows: visual_c_runtime: central` declares a dependency on Microsoft's Visual C++ runtime framework package, `Microsoft.VCLibs.140.00.UWPDesktop`, which the Microsoft Store installs with it.
- The setup program of an app built with `windows: visual_c_runtime: central`, on a computer that lacks a DLL of the runtime its gems need, downloads Microsoft's Visual C++ Redistributable from Microsoft's permanent link and runs it before it installs the app; if the DLL is still missing, the person chooses to abort, retry, or install without it, and a silent install aborts.
- `defines_type: true` in a `file_associations` entry, for a file type of the app's own, such as a game's `*.lota`, with its one MIME type and its extensions: a windowed Linux app carries the type's definition in `share/mime/packages`, which its `.deb` installs, so that a desktop knows such a file by its name and offers the app for it. Before, a desktop knew no such file, and the app's `MimeType` matched nothing.

### Changed

- Windows 11 is the oldest Windows Fledge names for its apps, on x64 as on ARM64, where the README named Windows 10, which Microsoft stopped supporting on 2025-10-14. Nothing in an app changes.
- **Breaking:** a runtime in `FLEDGE_RUNTIME_DIR` is checked against the SHA-256 Fledge pins for it, as a download is, and one that does not match fails the build, naming both SHA-256s; it was used unchecked. To build with a runtime you built yourself, set `FLEDGE_RUNTIME_DIR_UNCHECKED=1`. A runtime used unchecked, so, or one Fledge pins nothing for, is named on standard error.

### Fixed

- `fledge build` judges only a gem's compiled files for the app's processor, so a gem that carries a library for each of several, as raylib-bindings carries `lib/libraylib.aarch64.so` beside `lib/libraylib.x86_64.so`, is no longer refused for what another processor's file needs; and a universal Mach-O file no longer stops a macOS build with "objdump could not read".
- A gem's compiled file for another processor no longer fails the oldest-glibc or oldest-macOS check, nor stops a `.deb` build with dpkg-shlibdeps's "cannot find library"; and a gem's macOS or Windows library no longer stops a `.deb` build with "no tool on this computer reads macho files".
- `fledge build` on Windows builds an app whose gems have executables when the temporary folder's name is outside ASCII, as it is under an account named `Jürgen` or `日本`; it failed at "Writing the gems' executables".
- `fledge build` ships a gem whose executable is named outside ASCII, such as `日本`; the runtime's RubyGems 4.1 gave the name as a BINARY string, and the build failed in `JSON.generate`.
- `fledge build` on Linux and macOS ships a gem whose library needs another the gem carries under a different file name, by the name that library gives itself (its SONAME, or its `@rpath/` install name on macOS), which the system's loader answers with that library once the gem has loaded it, as raylib-bindings' raygui and physac need `libraylib.so.600` and `@rpath/libraylib.600.dylib`; it refused the gem.
- `fledge build android` refuses an app with a C or C++ extension built as a file when the project's `build.gradle` sets no `useLegacyPackaging`, naming the line to add, where it warned and built an app that raised `LoadError` at the extension's `require`: the Android Gradle plugin's default keeps the native libraries stored, as `false` does.
- `fledge build` for Windows lets a gem's DLL need any DLL that is in System32 on every Windows, as delvewheel 1.13.2 lists them for x64 and for ARM64, such as Direct2D's `d2d1.dll` and DirectWrite's `DWrite.dll`, which LibUI's DLL needs; it refused every DLL but some fifty it knew.
- `fledge build` for Windows, refusing a gem whose DLL needs Microsoft's Visual C++ runtime (`VCRUNTIME140.dll`, `MSVCP140.dll`), says that Windows does not include it and names `windows: visual_c_runtime` and a build of the gem that links it statically, where it told the developer to rebuild the gem.
- `fledge build` on Windows archives an app whose name, or the name of a file in it, is outside ASCII: Windows PowerShell's .NET writes the `.zip`, with every name in UTF-8. Windows' `tar.exe` failed to open the archive of an app named `日本語ツール` under code page 1252, crashed on such a name inside the app, and wrote one such as `Prüfung ü` in a code page Expand-Archive does not unpack it from.
- `fledge --help` says what a phone build does with a gem's extension since 0.13.0 and 0.14.0: Rust and Rakefile extensions build, and on Android an `extconf.rb` extension is a native library that needs `useLegacyPackaging = true`. It had said they were refused, and linked in.
- On iOS, and among Android's Rust and Rakefile extensions, two gems whose extensions define a function or variable of one name, or one that defines a name of the runtime's libraries such as libyaml's, each call their own definition, as on a Mac, where the app answered with the other's without a word or stopped `fledge build` with "duplicate symbol"; `fledge build` refuses, naming both, a name that two static libraries several extensions link, or one and the runtime, both define.
- A desktop app's `PATH` starts with its Ruby's bin folder, as a developer's shell has the Ruby they run, so `system("rake")`, backquotes, `ruby -S`, and `system("ruby", ...)` find the app's own Ruby and its gems' commands, the lockfile's version inside the bundle, as under `bundle exec`, where before they found nothing or the person's own Ruby; `Bundler.original_env` and `with_unbundled_env` keep that folder first too, as under `bundle exec` they keep the developer's Ruby.
- A gem Fledge compiles for a desktop app ships with its folder as `gem install` leaves it, every file its build wrote there included, so a gem whose Ruby reads a file its build wrote outside its require paths, such as generated data, finds it in the app, as under `bundle exec`; before, only those require paths and shared libraries shipped, and the app raised `ENOENT` or `LoadError`. A gem whose build leaves a build tree, objects, or a `Makefile` carries them too.
- On iOS and Android, a file a gem's build writes in the gem's folder, such as data an `extconf.rb` generates outside the require paths, is in the app where the gem's Ruby reads it, when the build wrote it alike for every target of the phone; before, a phone's app carried none of it, and the gem raised `ENOENT` or `LoadError` there. Files the targets' builds wrote differently, such as each `Makefile`, and compiled files stay out.
- An Android app runs `ruby` and its gems' commands by name, as a desktop app does: its `PATH` starts with its Ruby's bin folder, and each gem's command there, the runtime's and the lockfile's, is a link to the app's `ruby` program, which runs RubyGems' wrapper for it, and which Ruby reads in that path's place for `ruby -S`, `load`, and `ruby PATH`, where before they found nothing.

## [0.16.0] - 2026-11-20

### Added

- `fledge build android` refuses an app with a C or C++ extension built as a file when the project's `build.gradle`, such as a host's copy made before 0.13.0, sets `useLegacyPackaging = false`, and warns when it sets none: the app built, and raised `LoadError` at the extension's `require`; a host's copy needs `useLegacyPackaging = true`, as the template has had since 0.13.0.

### Changed

- A desktop app is smaller, by about 70 MB unpacked on glibc Linux, 145 MB on musl Linux, and 2 MB on macOS: the static libruby that `mkmf` links its checks against comes without its debug information, which nothing reads.

## [0.15.0] - 2026-11-20

### Added

- On iOS, a library a gem's Rakefile builds for ffi to open, as llhttp-ffi's and scrypt's do, or that the gem's package holds built for the phone, is a framework of its own, `Frameworks/fledgeffi.GEM.PATH.framework`, which the app embeds, with a link from where the gem looks for it; `fledge build ios` had refused such a gem. Other compiled files a gem's package holds are left out of an iOS app, naming each.
- On Android, a library a gem's Rakefile builds for ffi to open, as llhttp-ffi's and scrypt's do, or that the gem's package holds built for the phone, is a native library of the app's own, `libfledgeffi.GEM.PATH.so`, linked as the app starts from where the gem looks for it. One that links the NDK's shared C++ runtime, as a C++ library ffi-compiler builds does, brings `libc++_shared.so` with it, stripped, and its license in the app's `notices/libc++_shared.txt`.
- `fledge build android` refuses an app whose extension files or libraries for ffi need a library that neither Android offers every app (the NDK's public libraries for API 26), nor Fledge's runtime, nor the app carries, naming the gem, the file, and the library, as a desktop build does.

### Fixed

- A desktop app ships each shared library a gem's build wrote outside the gem's require paths, at its path, as a gem whose Rakefile builds a library for ffi leaves it (scrypt, llhttp-ffi, and rdkafka from source); the app had raised `LoadError` for it.
- A desktop build finds the runtime's own gems after the lockfile's, as `gem install` does, so a gem built by a Rakefile builds with the runtime's rake when the lockfile locks no other.
- `fledge build` judges the patch level of a Gemfile's `ruby` as the Bundler the app runs does, whichever Bundler runs `fledge build`: Bundler before 4.1 refuses a Gemfile whose first version is a prerelease, such as `ruby ">= 4.1.0.a", "< 4.2"`, on a released Ruby, and Bundler 4.1 compares no patch level; such a range had been refused on a runtime that records no `RUBY_DESCRIPTION`, where the app's Bundler accepts it.
- On iOS and Android, a gem's Rakefile can require the gems its gem depends on, each with an extension compiled for the computer that runs `fledge build`, as ffi-compiler requires ffi, which compiles there with the libffi it bundles, whatever libffi that computer offers. A library for ffi such a build leaves is checked to be built for the phone, and one the gem's package holds for macOS or a desktop's Linux, which the build left as it was, is refused.
- On Android, a C++ extension, built as a file or linked into `libfledgeext.so`, links the NDK's shared C++ runtime, which the app then carries, where it linked a static copy, so an exception, a string, or an allocation crosses between it and a C++ library it links as on a desktop: an app whose extension caught an exception such a library threw aborted. An app with no C++ is unchanged; one with C++ is about 1.4 MB larger for each ABI.
- On Android, a shared C++ library an `extconf.rb` builds with CMake links the NDK's shared C++ runtime, as the app's other C++ libraries do, unless the build sets `ANDROID_STL` itself: the NDK's toolchain file linked a static copy into it, about 3.6 MB for each ABI, and an app whose library hid that copy, as the NDK asks, aborted when its extension caught an exception the library threw.
- `fledge build` judges the compiled files a git or path gem holds as a gem, those its gemspec lists and those under its require paths, and no longer refuses a gem for a test's fixture elsewhere in its folder, which still ships. With Fledge itself in the Gemfile from git, as the README says, a desktop build had been refused for Fledge's own test fixtures. A path gem's listed files outside its require paths are now judged too.
- A phone app's `notices/NOTICES.txt` no longer calls the first of Fledge's files the program the app's user runs: it says the app's host starts Ruby through them.
- An app with Fledge itself in its Gemfile from git carries no compiled file of Fledge's: its test fixtures, Mach-O, ELF, and PE files that App Store Connect would refuse in an iOS app, are kept as text.
- Fledge's gemspec reads its version without defining `Fledge::VERSION`, so `fledge build` of a project that locks another fledge from git or a folder keeps its own version, which names the runtimes it fetches, and warns of no constant defined twice.

## [0.14.0] - 2026-11-19

### Added

- On Android, the runtime loads `libfledgeext.so`, the library of the app's gems' extensions, itself before Ruby boots, so a framework's own host need not name it; a host that does keeps working unchanged.

### Changed

- On Android, a gem's C or C++ extension that an `extconf.rb` builds ships as a native library of the app's own, `libfledgeext.FEATURE.so`, which Ruby loads from where a desktop has its file, as a desktop's Ruby does, so `$LOADED_FEATURES` names that path; it had been linked into `libfledgeext.so`. Such an extension needs the Gradle project's `useLegacyPackaging = true`, which `fledge build android` writes. `libfledgeext.so` is still in every app with a compiled extension, for a host that names it, holding whatever is still linked in, and Fledge's own `MainActivity` no longer loads it.
- The comments in an iOS project's `project.yml` and in the extensions' registration unit, which `fledge build` writes, no longer cite the deleted record of how a phone's extensions are compiled.

### Fixed

- `fledge build` judges a Gemfile's `ruby` and each gem's `required_ruby_version` by the runtime's Ruby as RubyGems and Bundler see it, `4.1.0.preview1`, and `4.1.0.dev` on Windows, where it saw `4.1.0`: a Gemfile that asks for `4.1.0-preview1` builds everywhere but Windows, and one that asks for `4.1.0`, whose app would not start, is refused. Each runtime holds its Ruby's description in `RUBY_DESCRIPTION`, which no app carries.
- When a lockfile has no checksum for the Bundler it names, `fledge build` says to run `gem install bundler -v VERSION`, then `bundle lock --add-checksums`; the `bundle install` it advised wrote no checksum when the lockfile's Bundler is the one that came with Ruby.

## [0.13.0] - 2026-11-15

### Added

- `fledge build ios` and `fledge build android` take a gem whose gemspec names a Rakefile or an `mkrf_conf` script in `extensions`, running it as RubyGems does, with the phone's `rbconfig.rb`, for each of the phone's targets; such a gem had been refused. The extensions such a build makes with mkmf, as digest-crc's Rakefile does, are linked into the app, and `require` finds each by its path in the gem's require paths. A build that leaves any other shared library, such as one for ffi, fails naming the gem and the library.
- `installers: [msix]` makes a windowed Windows app's MSIX package, `NAME-PLATFORM.msix`, with the Windows SDK's MakeAppx, for the Microsoft Store, which signs it. `fledge.yml`'s new `windows` key gives its `msix_publisher`, which it needs, and `msix_name`; its logos are `ICON-44.png`, `-50`, and `-150`. `--sign` and `--sign-command` sign it; otherwise it is unsigned.
- On Android, the runtime carries a ruby program, which `RbConfig.ruby` and `Gem.ruby` name, so `system(RbConfig.ruby, ...)`, `IO.popen`, and backquotes start Ruby as on a desktop, with the app's gems; the app's own program started so runs as the app first ran it.
- On iOS and Android, a gem with a Rust extension built with rb-sys compiles for the phone, where it was refused: Cargo builds it as a static library for each of the phone's targets, which the app links. It needs Rust and Cargo with each target's standard library (`rustup target add`).
- On iOS and Android, a gem's `extconf.rb` can require the gems its gem depends on, such as rb_sys or mini_portile2.
- The iOS runtime carries the fiddle gem, with libffi 3.5.2 compiled in, as the Android runtime does; it had been left out.
- `fledge build ios` and `fledge build android` build the ffi gem with the libffi it bundles, and link with an extension whatever its `extconf.rb` adds to the Makefile's `LOCAL_LIBS` after mkmf, as ffi's does. A build that an extension's Makefile starts gets the phone's compiler in `CC` and `CXX`, and on Android `AR` and `RANLIB`.
- On Android, the runtime's Ruby has YJIT and ZJIT, compiled with Rust 1.99.1, each off until the app enables it with `RubyVM::YJIT.enable` or `RubyVM::ZJIT.enable`, as on a desktop; neither had been defined there.
- `require "mkmf"` loads in an iOS or Android app, as on a desktop: a phone's app carries Ruby's C headers (`include/`), where mkmf aborted for want of them. An app grows by about 1.6 MB before compression.

### Changed

- **Breaking:** an app with a `Gemfile` ships the `development` and `test` groups, as `bundle exec` loads them, so a program that requires a development gem finds it; it raised `LoadError` naming the gem. Fledge itself, in your `development` group, ships too. Leave a group out with Bundler's own setting, `bundle config set --local without GROUP` or `BUNDLE_WITHOUT`, which the app's `.bundle/config` keeps. A gem of a shipped group with no build for the platform fails the build, as `bundle install` there would.
- `fledge build` compiles a gem's extension against the runtime alone, and no longer downloads the runtime's build-only companion, `fledge-runtime-VERSION-PLATFORM-dev.tar.gz`; `FLEDGE_RUNTIME_DIR` needs only the runtimes.
- In an app with a `Gemfile`, `Bundler.frozen_bundle?` and `Bundler.settings[:frozen]` are nil, as under `bundle exec`; they were true. Bundler still sets up the app's gems frozen, and a `Bundler.reset!` reads the app's frozen `.bundle/config` again.
- On iOS and Android, `$stdout.sync` is false, as under `ruby main.rb`: `$stdout` still writes each line as it prints, as Ruby writes to a terminal, and `$stdout.tty?` stays false.
- On iOS and Android, an app's `ENV` no longer holds `SSL_CERT_FILE`: as under rv-ruby's Ruby on a desktop, `require "openssl"` sets `PORTABLE_RUBY_SSL_CERT_FILE` to the runtime's CA certificates, or to the file `SSL_CERT_FILE` names, which OpenSSL then trusts, on Android too.
- On Windows, a runtime's `ruby.exe` and `rubyw.exe`, which `RbConfig.ruby` and `Gem.ruby` name, are Fledge's, built from Ruby's `main.c` against RubyInstaller's DLL, in place of RubyInstaller's: `exec RbConfig.ruby, $0, *ARGV`, and any other start of the app's own program through them, runs the app's launcher again, so the restarted app has its gems set up, the person's `RUBYOPT`, `RUBYLIB`, and `GEM_HOME` hidden from its boot, and its AppUserModelID; a Ruby the app starts has the app's ANSI code page, UTF-8, so a gem's DLL loads through ffi there under a folder named outside ASCII; and it loads DLLs as the app's Ruby does, so `digest/blake3` loads in it on x64. A script other than the app's program, or one after a Ruby option, runs as plain Ruby.
- The Android project packs native libraries compressed (`useLegacyPackaging = true`), so the installer extracts them where Android lets the app run its ruby program; an installed app takes more space. Set it to `false` to keep them stored, without a ruby program.
- The iOS and Android runtimes leave out the win32-registry gem, which only Windows can load, as the macOS and Linux runtimes' Ruby does.
- The comment that begins every `fledge.cfg` names no ADR: `# Written by fledge build VERSION for PLATFORM: what this app's program runs.`
- The comment in the entitlements a signed macOS app's code carries names no ADR; the entitlements are the same.

### Removed

- Releases no longer publish `fledge-runtime-VERSION-PLATFORM-dev.tar.gz`, the build-only companion, nor pin it in `lib/fledge/SHA256SUMS`: each desktop runtime holds what it held.

### Fixed

- In a windowed macOS app, `$LOAD_PATH` names Ruby's standard library in `Contents/Resources`, as `RbConfig` and `$LOADED_FEATURES` do; it named it through `Contents/MacOS/lib`, so `$LOAD_PATH.include?(RbConfig::CONFIG["rubylibdir"])` was false where it is true under `ruby`.
- A download of a runtime or a gem that slows below 10 kB a second for 30 seconds is given up and tried again, as one that breaks off is; it could hang the build for as long as the server trickled. A download still going after 15 seconds says how far it got every 15 seconds.
- Builds running at once that need one runtime or gem download it once: the others wait for it, saying so, where they could write over each other's download and fail. The cache keeps an empty `.lock` file beside each file it downloads.
- On Android, closing a descriptor two `Dir`s hold, as `Dir.for_fd` on another `Dir`'s descriptor does, raises `Errno::EBADF` as on Linux, where bionic's fdsan ended the app. Fledge's Ruby has fdsan warn once in logcat, the level of Android 10, for the whole process, unless the app set a lower one.
- On Windows, in an app with a `Gemfile`, a variable of Bundler's spelled in another case, such as `Path` as Windows spells it, keeps that spelling in `ENV`, and `Bundler.original_env` is the same after a restart; a restart lost a person's `bundle_gemfile` from it. The app's own `BUNDLE_GEMFILE` keeps Bundler's spelling, so that a Ruby the app starts sets up the app's Gemfile, never one the person's own Bundler settings name.
- In an app with a `Gemfile`, `defined?(Psych)` is false until something loads Psych, as under `bundle exec`: Bundler takes the app's settings from the environment as it sets the app up, instead of reading its `.bundle/config` with RubyGems' YAML serializer, which defined a hollow `Psych` module.
- A desktop app carries the library mkmf links its test programs against, a static `libruby` on macOS and Linux and the import library of Ruby's DLL on Windows, so `have_func`, `have_library`, and `try_link` in an app's own running code work where a compiler is; they raised "The compiler failed to generate an executable file".
- An app with a gemspec loads the project's files that its gemspec requires before the program's first line, as Bundler does under `bundle exec`, so `MyCoolApp::VERSION` from `bundle gem`'s `lib/my_cool_app/version.rb` is defined from the start; it raised `NameError` until the program required the file.
- On Windows, `RubyInstaller` is defined in an app, as under `ruby.exe`, so a gem that tests `defined?(RubyInstaller)` takes the same branch: mysql2 0.5.6 loaded `libmysql.dll` by bare name instead, and could abort. `Win32` is defined too, and `$LOADED_FEATURES` lists the files and encodings RubyInstaller's start-up loads under `ruby.exe`, none of whose start-up runs.
- On iOS, Ruby's `[BUG]` crash report lists the C frames, as on macOS.
- On iOS and Android, a gem from git with an extension compiles; its build failed with `Errno::ENOENT` before it began.
- On iOS and Android, a gem whose Ruby loads its extension by its path, with `require_relative "name/name"` as `bundle gem --ext` wrote it from Bundler 2.2.0 to 4.0.0, finds it: `fledge build` puts a Ruby file that requires the linked extension where a desktop has the extension's file. It failed with a `LoadError`.
- On iOS and Android, a gem that requires its extension by the path of its file, with `.so` or `.bundle` (`require File.join(__dir__, "name.bundle")`), or by `.bundle` on iOS, finds the extension linked into the app, and so does a `require_relative` of an extension a Rakefile built; each failed with a `LoadError`.
- On iOS and Android, a require of a bundled gem's extension before its gem is active, such as `require "racc/cparse"`, activates the gem and loads the extension as on a desktop; it failed with a `LoadError`.
- On Windows, an app runs with UTF-8 as its ANSI code page, which its manifest declares, so a gem that opens a file or DLL through a Windows `A` function works when the app is installed under a folder named outside ASCII: a gem whose DLL ffi loads, such as libusb, failed to load there. In a windowed app `Encoding.find("locale")` is UTF-8 where `rubyw.exe` gives the system's code page; `doc/differences_from_ruby.md` says what else differs.
- On iOS and Android, a gem's `extconf.rb` no longer finds this computer's libraries through pkg-config, which gave the ffi gem a Mac's libffi for the Simulator; `PKG_CONFIG` is `false` in a phone's build, and a gem's `--with-pkg-config` option still names one.
- On iOS and Android, a gem whose `extconf.rb` writes `extconf.h` with `create_header`, as many do, has its extension's Init function renamed as Fledge registers it, so the app links on iOS and starts on Android; it failed with an undefined `Init_fledge_N` symbol.
- On iOS and Android, a phone's app has the prism gem, so `require "prism"` works, and so does requiring irb, minitest, rbs, rdoc, repl_type_completor, or typeprof: each bundled gem's extension keeps every symbol but its Init function to itself, so prism's own libprism no longer collides with libruby's.
- On Windows, `fledge build` compiles gems in a work folder named by its long names when `TMP` names the user folder by its 8.3 short name (`C:\Users\RUNNER~1`), so a gem whose build escapes a path for a shell, as nokogiri's through mini_portile2 does, compiles. It failed with "a gem's extension did not compile".
- On iOS and Android, `require "bigdecimal"` activates the bigdecimal gem and loads its Ruby, as on a desktop, so `BigDecimal#sqrt`, `#power`, `#**`, and `BigMath` are there; the same holds for nkf, and for fiddle on Android.
- On iOS and Android, `$0 =` and `Process.setproctitle` set the app's process title that `ps` shows, as on a desktop, at the length a desktop allows; they changed only `$0`.
- On Android, `Process.egid=`, `Process.gid=`, `Process.groups=`, `Process.initgroups`, and the group and user ID changes of `Process::GID`, `Process::UID`, and `Process::Sys` answer as Linux answers a process that may not change its IDs, succeeding for the app's own ID and raising `Errno::EPERM` for any other, instead of ending the app, which Android's seccomp filter stops for those calls; and `Process.uid=` sets the user ID as on Linux instead of ending it.
- On iOS, `File::Stat#readable?`, `#writable?`, `#executable?`, and `#grpowned?` answer for a file of another group, as `File.readable?` does, instead of raising `ArgumentError` (malloc: possible integer overflow).
- On Android, `fork`, `Process.fork`, `Process.daemon`, and `IO.popen("-")` run the child, which ended in Ruby's `[BUG]` handler (`pthread_rwlock_unlock`: EPERM).
- On Android, `Thread#name=` on a thread that has ended names it, instead of aborting the app.
- On musl Linux, `Thread#name=` on a thread that has ended names it, instead of crashing the app with a segmentation fault.
- On Android, `Process.maxgroups=` sets the most group IDs Ruby asks for, as on Linux, instead of raising `NotImplementedError`.
- On Android, `File.umask` and the `umask:` option of `Process.spawn`, `exec`, and `system` keep a mask's permission bits, as Linux does, instead of aborting the app for a mask with other bits set, such as `umask: -1`.
- On Android, `Dir.glob` and `Dir[]` with `base:` a `Dir` opened by a relative path find what they find on Linux, where they found nothing.
- On musl Linux, iOS, and Android, `require "io/nonblock"` activates the io-nonblock default gem, so `Gem.loaded_specs` has it, as on a desktop, and every default gem's specification lists the files a desktop's does.

## [0.12.0] - 2026-11-12

### Changed

- Breaking: the runtimes carry Ruby 4.1.0-preview1 in place of Ruby 4.0.9, so `fledge build` needs Ruby 4.1 to run it, and an app gets Ruby 4.1's standard library, default gems, and bundled gems (prism, tsort, and win32-registry join them; net-ftp and net-pop leave).
- Windows runs Ruby's main branch of 2026-11-10 (`ruby 4.1.0dev`, `0e25874222`, in folders named `4.1.0+6`), from RubyInstaller's head build, since RubyInstaller builds no preview, and every other platform runs 4.1.0-preview1 (in folders named `4.1.0+5`): rv-ruby release `20261023`'s builds on macOS and glibc Linux, and Ruby's source on musl Linux, iOS, and Android.
- The Windows runtimes add the `libz-1.dll` (zlib 1.4) that build's `zlib.so` needs and, on x64, the `libgcc_s_seh-1.dll` its `digest/blake3.so` needs, from MSYS2's packages, and the launcher finds the second in `ruby\bin\ruby_builtin_dlls`.
- On iOS and Android, the prism gem is left out for now, so in a phone's app `require "prism"` fails, and so does requiring a bundled gem that depends on it: irb, minitest, rbs, rdoc, repl_type_completor, or typeprof.

### Removed

- Breaking: Ruby 4.0. No runtime carries it, and the gem needs Ruby 4.1 or newer.

### Fixed

- An app whose `Gemfile.lock` names another Bundler under `BUNDLED WITH` than the runtime's runs with that Bundler, as `bundle exec` does: `fledge build` ships it, checked against its `CHECKSUMS` entry, and refuses a lockfile without one. It ran with the runtime's Bundler.

## [0.11.0] - 2026-11-10

### Fixed

- `fledge build` takes a gem's locked source build, as Bundler does, when its precompiled build's `required_ruby_version` excludes the runtime's Ruby, instead of refusing the precompiled build.

## [0.10.0] - 2026-11-08

### Changed

- Breaking: `fledge build --from` on an APP it cannot use (not a folder, not built by Fledge, built by another release or for another system) exits 1, a failed build, and no longer 2, a usage error.
- The Windows setup program registers one ProgID for each extension in `file_associations`, named from the identifier and a hash of the extension, within Microsoft's limits on a ProgID; reordering or renaming entries no longer renames it. An installed app keeps its earlier `IDENTIFIER.N` entries until it is removed by hand.

## [0.9.0] - 2026-11-08

### Added

- `fledge build --sign IDENTITY --notarize PROFILE` on macOS has Apple notarize the signed app with `xcrun notarytool` and the credentials the keychain profile PROFILE holds, then staples the ticket to the disk image and the bundle before the archive is packed; a console app's folder is notarized in a zip archive. A refused app fails the build with the issues Apple's log names. `--notarize` needs `--sign` with an identity that is not ad hoc.
- `fledge build --sign-command COMMAND` on Windows signs every program and library, the uninstaller, and the setup program with your own command, run through `cmd.exe` once per file with the file's path in place of `%1` or after the command, for a certificate in a cloud or hardware service such as Azure Artifact Signing; `FLEDGE_SIGN_COMMAND` gives the command when the command line gives neither `--sign` nor `--sign-command`. A command that exits nonzero fails the build, naming the file. `--sign` and `--sign-command` together are a usage error.

## [0.8.0] - 2026-11-08

### Changed

- Fledge is now licensed under the MIT license; each app's `notices/NOTICES.txt` says so.

### Removed

- A Windows app no longer carries `notices/MODIFIED.txt`, and `fledge build` no longer reads `SOURCE_DATE_EPOCH` or fails on one that is not a whole number of seconds: Fledge's launcher is MIT, which asks for no notice of changes.

### Fixed

- `fledge build` tries a runtime's or a gem's download again after 2, 4, and 8 seconds when the server answers 408, 429, or a 5xx, or the connection fails or breaks off, saying so on its output, instead of failing the build at once; a missing file, a refused login, or a SHA-256 mismatch still fails at once, and every try is checked against its pin. A body cut short by a broken connection is now such a failure, where it was reported as a SHA-256 mismatch.
- `fledge build --sign` on macOS runs codesign again after 5, 10, 20, and 40 seconds when Apple's timestamp server does not answer ("The timestamp service is not available." or "A timestamp was expected but was not found."), instead of failing the build at once; any other codesign failure still fails at once.
- A `with` that names only `development` or `test`, such as `BUNDLE_WITH=development` or the same in the project's `.bundle/config`, no longer ships that group's gems.

## [0.7.0] - 2026-11-07

### Added

- A Windows app carries `notices/MODIFIED.txt`, which names each of its programs, says that `fledge build` changed that copy of Fledge's AGPL launcher on the date of the build (`SOURCE_DATE_EPOCH` when it is set; one that is not a whole number of seconds fails the build) by writing into it, with rcedit, the version information and icon it lists, and says where the launcher's source and those steps are. A Windows runtime's `notices/NOTICES.txt` names the file. `fledge build --from` leaves the old app's behind and writes the new app's.

### Fixed

- On macOS and Linux, an app started with an environment entry that holds no `=` and begins as a Ruby setting does, such as a bare `RUBYOPT`, which a program can pass with `execve`, runs as under `ruby` instead of hanging in its launcher.

## [0.6.0] - 2026-11-05

### Added

- `fledge build --from APP [PATH]` builds PATH's project into a copy of APP, an app the same Fledge release built for this computer, with APP's runtime, gems, `Gemfile`, and `Gemfile.lock`, and the project's own name, identity, archive, and installers, downloading, installing, and compiling nothing. A project with a `Gemfile`, `gems.rb`, or gemspec, or whose `fledge.yml` has `programs`, `linux: system_libraries`, `ios`, or `android`, is refused; an APP from another release or for another platform is a usage error. On Windows it takes the program and rcedit from APP's `build_tools`, or else from the release's runtime, which must then be in `FLEDGE_RUNTIME_DIR` or the cache.
- `fledge.yml` takes `description`, one line, `long_description`, and `homepage`, an http or https URL: the description is a Linux desktop entry's `Comment`, a `.deb`'s synopsis, and a Windows program's `Comments`; the long description is a `.deb`'s extended description; the homepage is a `.deb`'s `Homepage` and the setup program's `URLInfoAbout` and `HelpLink`. A project without them builds the same files.
- `fledge.yml` takes `license_file`, a UTF-8 file in the project: the Windows setup program shows it on a page before it installs (a silent install shows none), and a `.deb` installs it as `/usr/share/doc/PACKAGE/copyright`. `linux: deb_changelog` names a changelog a `.deb` installs as `/usr/share/doc/PACKAGE/changelog.gz`, compressed with `gzip -n -9`.
- `fledge.yml`'s `macos: build`, one to three whole numbers between periods, such as `"1.2.417"`, is a windowed Mac app's `CFBundleVersion` in place of the version's first three numbers.
- `file_associations` in `fledge.yml`: the files and folders a windowed app opens, each with a `name`, a `role` (`viewer` or `editor`), and `extensions`, `mime_types`, and `content_types`, or `folders: true`. macOS's `Info.plist` declares them as document types ranked `Alternate`; the Windows setup program adds the app to each extension's "Open with" and to every folder's menu, under `HKCU\Software\Classes`, and its uninstaller removes them; the Linux desktop entry, in the folder, the AppImage, and the `.deb`, lists their MIME types and runs the program with their paths (`%F`).
- `build_tools: true` in `fledge.yml` puts in the app what `fledge build --from` needs that a system lacks, in its `tools` folder: on Windows the runtime's launchers, rcedit, and NSIS, and on Linux AppImage's runtime. `--from` takes them from APP before it looks for a runtime, so an app with Fledge in its `Gemfile` builds from itself, on Windows too, with no runtime on the computer; the app it writes carries them only if its own `fledge.yml` sets `build_tools`.

### Changed

- The Gradle wrapper in an `fledge build android` project retries its Gradle download four times (`retries=4`, `retryBackOffMs=5000` in `gradle-wrapper.properties`) instead of failing on the first 5xx.
- A windowed Linux app takes the icon PNGs its project has, at least one of `-16`, `-32`, `-64`, `-128`, `-256`, and `-512`, instead of needing all six; `fledge build` warns on standard error naming each one missing, and the AppImage's top icon is the 256-pixel one, or else the largest.

### Fixed

- On Windows, `fledge build` writes and reads archives in folders whose names are not ASCII, such as `-o "Prüfung 日本"`, which `tar.exe` could not change into; and a tool's failure written in the console's code page is quoted instead of ending the build with a Ruby error.

## [0.5.1] - 2026-11-05

### Fixed

- On iOS and Android, each line an app's Ruby prints reaches the system log when it is printed, not when the program ends: `$stdout` is in sync mode before the program runs whenever standard output is not a terminal, as on a phone it never is, so `$stdout.sync` is true there where `ruby main.rb` in a terminal reports false.

## [0.5.0] - 2026-11-05

### Added

- `FLEDGE_RUNTIME_MIRROR` names a server to download runtimes from instead of Fledge's GitHub Release, holding the release's files at its paths, as `MIRROR/vVERSION/NAME`. Every download is checked against the SHA-256 the gem pins, a mirror that serves other bytes fails the build naming both SHA-256s, and a file the mirror lacks fails the build rather than coming from the release.
- `fledge build` writes beside the archive and each installer its SHA-256 in `FILE.sha256`, one line as `sha256sum` prints it, which `sha256sum -c` checks and a package manager's recipe names. It is not printed, so standard output is unchanged.
- `fledge.yml`'s `linux: system_libraries` lists, by soname, the libraries a project's gems load from the Linux distribution, such as `[libwebkit2gtk-4.1.so.0, libgtk-3.so.0]`. On Linux `fledge build` takes a gem whose compiled files need one, refuses one listed that no gem needs, makes a `.deb` depend on the packages that provide them (found with dpkg-shlibdeps, from dpkg-dev), and has the app's program name one the computer lacks, and exit with 72, before Ruby starts. A gem that needs a library nothing provides is still refused, and the message now names the key.
- Every app built for Linux or Windows carries, in `notices/sources/`, the source of the LGPL libraries and installer tools whose licenses ask for it, exactly as published, with how the runtime's copy was built: libxcrypt, AppImage's runtime, and libfuse on Linux (musl Linux: AppImage's runtime and libfuse), GNU MP and NSIS on Windows. `notices/NOTICES.txt` names that folder first and the release's `-lgpl-sources.tar.gz`, which stays, second, so the source goes wherever the app goes. This makes a glibc Linux runtime, and an app built with it, about 5.3 MB larger, a musl Linux one about 4.6 MB, and a Windows one about 4.0 MB.

### Changed

- Breaking: an app gets the Ruby that runs `fledge build`, its minor version at the patch level Fledge ships, so `fledge build` on a Ruby whose minor version has no runtime, such as a 4.1 preview, fails and says so, instead of building the app with Ruby 4.0.
- `fledge --help` says that a PATH that is a bare word Fledge reads as a platform, `ios` and `android` today and any platform a later release adds, is read as that platform, so write `./NAME` for a folder of that name; and that changing `identifier` makes a new app to each system.
- Breaking: a windowed program under `programs` in `fledge.yml` with no `name` takes the app's name (`name`, else the gemspec's or the folder's, camelized), not its file's, so `gui/main.rb` builds `MyGame.app` and `MyGame.exe` instead of `main.app` and `main.exe`. A console program keeps its file's name. Give the windowed program `name:` to keep the old one; a project whose windowed program would now share a name with another program fails the build, naming both.
- The schema of `fledge.yml` names itself by the release's tag, `https://raw.githubusercontent.com/setdef/Fledge/vX.Y.Z/lib/fledge/config.schema.json`, not by `trunk`, and that is the modeline to use, with the tag your `Gemfile` names: `trunk`'s schema describes what comes next, which your Fledge may refuse. A modeline that names `trunk` still works.

### Fixed

- On Windows, an app started through a symbolic link to its program, as winget links a portable package's program into its Links folder, runs; it had looked for its files beside the link and exited with 66, saying `fledge.cfg` was missing.
- On macOS, `fledge build` tries `hdiutil create` again, after 2, 4, 8, and 16 seconds, when it fails with "Resource busy" because another process holds its scratch volume, as happens now and then on GitHub's macOS runners; it had failed the build at once.
- On iOS, an app launched with `OS_ACTIVITY_DT_MODE` in its environment, whatever its value, as a developer tool may launch it, leaves its standard output and standard error to that tool instead of forwarding them to os_log, which copied each line back to standard error until the app froze. Without it, the lines go to os_log as before.
- On Windows, `fledge build` takes a gem whose compiled files link DLLs every Windows has in System32 for windows, input, graphics, and sound (`avrt`, `cfgmgr32`, `comctl32`, `d3d9`, `d3d11`, `dinput8`, `dsound`, `dwmapi`, `dxgi`, `hid`, `imm32`, `setupapi`), as a game library's precompiled Windows gem does; it had refused such a gem, saying the app could not load the DLL on another computer.
- On macOS and Linux, an app's `notices/NOTICES.txt` and SBOM, and `doc/licensing.md`, count `bin/ruby` among the files that hold Fledge's AGPL code, beside the launcher and the RubyGems defaults file; they had named only those two, though `bin/ruby` has carried Fledge's code since 0.3.0.

## [0.4.0] - 2026-11-04

### Added

- `fledge build ios` and `fledge build android` run a gem's `extconf.rb` with `CMAKE_TOOLCHAIN_FILE` naming a CMake toolchain file for each of the phone's targets, so a library the `extconf.rb` builds with CMake (3.21 or later) is built for each iOS slice and Android ABI and linked into the app; such a library had been built for the computer running the build.

### Changed

- When `Gemfile.lock` has an empty `CHECKSUMS` entry, which `bundle lock --add-checksums` leaves for a gem only `vendor/cache` holds, `fledge build` says after Bundler's message how to fill it: write the SHA-256 of each of the gem's `.gem` files into its entry.

### Fixed

- On macOS and Linux, the launcher and the runtime's `bin/ruby` keep an explicit `LC_ALL` or `LC_CTYPE`, `C` included, as `ruby` does; they had turned it into a UTF-8 locale. A C locale from `LANG`, or from no locale variable at all, still becomes UTF-8.
- `require "mkmf"` works in a built app on macOS, Linux, and Windows: runtimes now carry Ruby's C headers (`include/`), and the build-only companion no longer does. Runtimes grow by about 0.4 MB.
- On macOS and Linux, `binding.irb` opens IRB in an app with a Gemfile that does not lock irb, as under `bundle exec`; it had failed with Bundler's frozen-lockfile error naming `Gemfile.lock`.
- `fledge build` leaves every folder an earlier build went to out of the app, not only the current `--out`, so a build into `dist` and then one into `out` no longer ships the first build inside the second. The folder a build makes, or finds empty, gets a `CACHEDIR.TAG`, and any folder in the project that holds a valid one stays out of the app.
- On a phone, a C extension whose `extconf.rb` names the C++ runtime (`-lc++` or `-lstdc++`), as one over a C++ library does, links as a C++ one: with `-lc++` on iOS, and on Android with the NDK's C++ runtime linked in, instead of a `libc++_shared.so` the app does not carry.

## [0.3.0] - 2026-11-03

### Fixed

- On macOS and Linux, a runtime's `bin/ruby`, the Ruby `RbConfig.ruby` names, turns a bare C locale into a UTF-8 one as the launcher does, so a Ruby an app starts, a restart, or a gem's executable reads a folder whose name is not ASCII as UTF-8, and sets up the app's gems there; it had read such a folder as US-ASCII, and Bundler failed.
- On macOS and Linux, `exec RbConfig.ruby, $0, *ARGV`, and any other start of the app's own program through `RbConfig.ruby`, runs the app's launcher again, in the same process, so the restarted app has its gems set up and the person's `RUBYOPT`, `RUBYLIB`, and `GEM_HOME` hidden from its boot, and on macOS keeps its bundle; it had run as plain Ruby, which those settings could break. A script other than the app's program, or one after a Ruby option, still runs as plain Ruby. On Windows, start the app's `NAME.exe` again to restart it.
- In a macOS `.app`, `$0` and `__FILE__` name the app's program in `Contents/Resources/app`, the folder `__dir__` and Ruby's prefix name, so `File.dirname(__FILE__)` is `__dir__`; they had named it through the link in `Contents/MacOS`.
- On macOS, `fledge build` refuses a gem whose compiled file names a library the gem carries as `@rpath/NAME` or `@loader_path/NAME` that dyld would not find there, such as one reached only through a run path of `/opt/homebrew/lib`, naming the file and the run paths it searched; it had accepted any library of the same file name.
- `fledge build` says that a gem's server has no file for the gem, and to put it in `vendor/cache` or lock the gem to the source that has it, when the server answers 404 or 410, or when RubyGems.org answers 403 to a request without a login; it had told the developer to set a login.
- `fledge build` no longer copies RubyGems' "Successfully built RubyGem" report into its log for each gem whose executables it writes.

## [0.2.1] - 2026-11-03

### Fixed

- The first published release of the 0.2.0 changes: `v0.2.0`'s tag has no release, because a host of a runtime's pinned source was down. Downloads of pinned sources now fall back to hash-checked mirrors.

## [0.2.0] - 2026-11-03

### Added

- `fledge build ios` and `fledge build android` compile a gem's C and C++ extension (an `extconf.rb`) for the phone's targets and link it into the app, where `require` finds it by the name `create_makefile` gave. iOS needs Xcode; Android needs the NDK (`ANDROID_NDK_ROOT`, or the SDK's `ndk/` folder) on a Mac or Linux. The mobile runtimes gain `fledge_ruby_add_extension` for a host that registers its own extensions. A library the `extconf.rb` links, such as SDL3, links too: a static library with each iOS slice's own extensions, each framework whole, and a shared library from the extension's `-L` folders into the APK beside the extensions.
- A JSON Schema of `fledge.yml`, `lib/fledge/config.schema.json` in the gem, for editors that run Red Hat's YAML language server: put `# yaml-language-server: $schema=https://raw.githubusercontent.com/setdef/Fledge/trunk/lib/fledge/config.schema.json` on the file's first line to complete its keys and values and mark what `fledge build` would refuse.
- `programs` in `fledge.yml` lists several programs of one project, each with a `path` and its own `name`, `kind`, `identifier`, and `icon`; `fledge build` builds them all into one folder that shares one runtime, one copy of the project, and one set of gems. At most one is windowed, and the installers are its; on macOS the console programs live in its bundle's `Contents/MacOS`, linked from the folder. A path that names one of the programs builds it alone. A project without `programs` builds as before.
- `ios: { host: DIR }` and `android: { host: DIR }` in `fledge.yml` name a folder in the project whose files `fledge build ios` or `fledge build android` copies over the project it writes, before XcodeGen runs, so they survive every build: each replaces Fledge's file at its path, such as `Host/main.m` or `MainActivity.java`, or joins the project, and the build names the files it replaced on the error stream; the host folder itself is left out of the app's copy of the project. Fledge fills its `@@NAME@@` marks in a copy of its `project.yml`, Gradle files, manifest, `strings.xml`, or `MainActivity.java`. A host that is not a folder in the project fails the phone's build; desktop builds ignore both keys.

### Changed

- `fledge.cfg` gives each program of a multi-program app a section, `[NAME]`, which each copy of the launcher finds by its own file name; a copy renamed by hand exits with 66. Launchers from 0.1.0 and earlier refuse such a file.
- A phone's gem with an extension that no `extconf.rb` builds (Rake, CMake, Cargo) or that is Rust fails the build with a message naming the gem, as every extension did before.

## [0.1.0] - 2026-11-02

Versions now follow ordinary 0.MINOR.PATCH numbering; the `0.0.1.pre.N` form ended at 0.0.1.pre.17. Nothing else about how releases are made or fetched changed: a release is still a git tag and a GitHub Release with the runtimes, and `fledge build` downloads the runtimes for its own version.

### Added

- A windowed app on glibc Linux (`x86_64-linux`, `aarch64-linux`) can have a `.deb` installer, `NAME-PLATFORM.deb`, which `dpkg-deb` builds; ask for it with `installers: [appimage, deb]` in `fledge.yml` (it is not in the default list). `apt install ./NAME-PLATFORM.deb` installs the app in `/usr/lib/IDENTIFIER` with its desktop entry and icons where desktops look, needing glibc 2.39 or newer, and removing the package removes them. Without `dpkg-deb` the build fails, saying to install dpkg.

## [0.0.1.pre.17] - 2026-11-01

### Added

- Gem servers that need a login, or that Bundler mirrors, work as under Bundler: `fledge build` asks each server through the mirror (`bundle config mirror.URL`) and with the login (`bundle config HOST USER:PASSWORD`, or one in the Gemfile's source URL) Bundler's settings give it, and a server that refuses the login fails the build with the gem's name and how to set one.
- A gem from git with `submodules: true` ships with its submodules checked out.
- A gem from a folder outside the project (`path: "../shared"`) ships in `app/vendor/cache/NAME`, where Bundler looks for a copy of a path gem.
- A path gem with an extension, inside the project or outside, and a project that is a gem with an extension, is compiled for the runtime's Ruby, and its compiled files replace those compiled for the developer's own.
- The executables of the gems an app ships, other than the project's own, are written into the runtime's `bin/` (`ruby/bin` on Windows) as the runtime's own gems' are, and run with no Ruby on the person's computer; find one at `File.join(Gem.bindir, NAME)` (`NAME.bat` on Windows).

### Changed

- The groups an app ships follow Bundler's `with` and `without` settings: a group declared `optional: true` ships only when the project's settings (`BUNDLE_WITH`) name it, and the app's `.bundle/config` carries both settings, so its Bundler sets up the groups that shipped.

### Fixed

- A build no longer fails when an app locks a gem with a RubyGems plugin that the runtime has a loader for, such as the `rdoc` that `irb` asks for: the runtime's loader stays.

## [0.0.1.pre.16] - 2026-11-01

### Added

- Windows on ARM64, `aarch64-mingw-ucrt`: `fledge build` on Windows 11 on ARM64 builds an app that runs there natively, from a runtime of RubyInstaller 4.0.9-1's ARM64 build, with every Windows feature: the GUI launcher, version information and icon, the NSIS installer, and `--sign`. Its tools (rcedit, NSIS, `llvm-readobj`) run under Windows' x64 emulation. A gem must publish an `aarch64-mingw-ucrt` build or compile there; sqlite3 2.10.2 does neither.

## [0.0.1.pre.15] - 2026-11-01

### Added

- musl Linux targets, `x86_64-linux-musl` and `aarch64-linux-musl`, for Alpine and other distributions built on musl: `fledge build` on such a computer builds an app (and, for a windowed one, its desktop entry and AppImage) that runs there with no Ruby, from a runtime Fledge's CI builds from Ruby 4.0.9's source in Alpine, with OpenSSL 3.6.5, libyaml 0.2.5, libffi 3.5.2, and zlib 1.3.2 compiled into its extensions, YJIT, and musl's own `crypt`. A compiled gem may need only musl's C library and zlib, as PEP 656's musllinux wheels may.

## [0.0.1.pre.14] - 2026-11-01

### Added

- `fledge build --sign IDENTITY` signs a desktop app with your own identity, after Fledge has written everything into it and before it archives it: on macOS, with a code signing identity from your keychain (or `-` for ad hoc), every Mach-O program and library, the bundle, and the disk image, by `codesign`, with the hardened runtime, a secure timestamp, and the entitlements `com.apple.security.cs.allow-unsigned-executable-memory` (for YJIT) and `com.apple.security.cs.disable-library-validation`; on Windows, with the SHA-1 thumbprint of a code signing certificate in your store, every `.exe`, `.dll`, and `.so`, and the NSIS setup program and its uninstaller, by the Windows SDK's `signtool`, with SHA-256 and a timestamp from DigiCert's server. Linux and phone builds refuse it. Unsigned builds are the default, as before. Fledge does not notarize.

## [0.0.1.pre.13] - 2026-11-01

Nothing an app's developer or its users can observe changed: this release proves, on every platform, that Ctrl-C and a closed terminal end a built console app as they end `ruby main.rb`, and that a Windows console's code page reaches it as it reaches `ruby.exe`.

## [0.0.1.pre.12] - 2026-11-01

### Changed

- `fledge build` checks every runtime and build-only companion it downloads, and every one it finds in its cache, against the SHA-256 its own gem pins in `lib/fledge/SHA256SUMS`, never against what the release says, so a release asset replaced after its version was tagged fails the build. A cached runtime that does not match is downloaded again. A Fledge between releases, which pins no runtimes of its own version, says to install a release or set `FLEDGE_RUNTIME_DIR`.
- Each release's `SHA256SUMS` is the gem's `lib/fledge/SHA256SUMS`, byte for byte.

## [0.0.1.pre.11] - 2026-11-01

### Changed

- `fledge build` reads the compiled files of an app's gems with the system's own tools rather than its own readers of ELF, Mach-O, and PE: on macOS, Xcode's command line tools' `objdump`, and on Linux binutils' `objdump`, each needed only when the app's gems carry compiled files; on Windows, LLVM 23.1.4's `llvm-readobj`, which the Windows runtime carries in `tools/` (ADR 013).
- `fledge build` judges only the compiled files of its own system's format (ELF on Linux, Mach-O on macOS, PE on Windows) for the libraries they need; a gem that carries another system's files no longer fails the build for them.

## [0.0.1.pre.10] - 2026-11-01

### Added

- `fledge build ios` writes an Xcode project for an app on iPhone and iPad (iOS 15 and later, arm64), on a Mac with Xcode and XcodeGen, and `fledge build android` a Gradle project for Android (API 26 and later, targeting API 36, native libraries aligned for 16 KB pages), with Gradle 9.8.2's wrapper, on a Mac, x86-64 Linux, or Windows: `DIR/NAME-ios/` and `DIR/NAME-android/`, around the release's mobile runtime, with the app's project, its gems, the runtime's notices, and a small host app that runs the app's program and sends its output to os_log or logcat. Neither signs anything; you sign and submit the app.
- A phone's app takes `fledge.yml`'s `identifier` (required) as its bundle identifier or `applicationId`, its `name`, its `version` (Android's `versionCode` from its first three numbers), and its icon: `ICON-1024.png` for iOS, and `ICON-48.png`, `-72`, `-96`, `-144`, and `-192` for Android.
- A phone's app ships each gem's `ruby` build, set up by Bundler with `force_ruby_platform`, so its `Gemfile.lock` must lock `ruby`; a gem with an extension to compile fails the build.
- An iOS project's privacy manifest names the required-reason APIs Ruby calls: file timestamps (C617.1) and system boot time (35F9.1).
- The mobile runtimes' embedding API gains `fledge_ruby_run_app`, and on Android `FledgeRuby.runApp` and `startApp`, which run the app `fledge.cfg` names, with Bundler set up for its Gemfile, as the desktop launcher does.

### Fixed

- On iOS, a line of an app's output too long for one os_log entry no longer loses a space where it is split: the entries are cut before whitespace, which the unified log trims from an entry's end.

## [0.0.1.pre.9] - 2026-10-28

### Added

- Mobile runtimes, as release assets beside the desktop ones, with their SBOMs and NOTICES: `fledge-runtime-VERSION-ios.tar.gz`, holding `FledgeRuby.xcframework` for iOS and iPadOS devices and the Simulator (`arm64-ios`, `arm64-ios-simulator`), and `fledge-runtime-VERSION-android.tar.gz`, holding `FledgeRuby.aar` for Android's arm64-v8a and x86_64 (`aarch64-linux-android`, `x86_64-linux-android`). Each is CRuby 4.0.9 built from source as an interpreter, with its extensions linked in, OpenSSL 3.6.5, libyaml 0.2.5, on Android libffi 3.5.2, every default and bundled gem as a gem (fiddle left out on iOS), Mozilla's CA certificates, and a UTF-8 locale, started by a small embedding API (`fledge_ruby_run`, `fledge_ruby_forward_output`, and on Android `org.setdef.fledge.FledgeRuby`) that sends standard output and standard error to os_log or logcat. `fledge build` does not build mobile apps yet.

## [0.0.1.pre.8] - 2026-10-28

### Changed

- **Breaking:** `fledge.yml`'s `icon` names the icon's files without an extension, as Briefcase's does (`icon: icons/app`), and each platform takes its own, as you make it: `icons/app.icns` on macOS, `icons/app.ico` on Windows, and `icons/app-16.png`, `-32`, `-64`, `-128`, `-256`, and `-512` on Linux. Fledge no longer makes them from one PNG; an `icon` that ends in `.png` fails, saying what to write.
- **Breaking:** on a computer with no FUSE, an AppImage says so and runs only when asked to extract itself (`APPIMAGE_EXTRACT_AND_RUN=1` or `--appimage-extract-and-run`), as every AppImage does; it no longer extracts itself unasked.
- A built app's archive is written, and a runtime unpacked, by the computer's own tar: GNU tar on Linux, bsdtar on macOS, and `System32\tar.exe` on Windows 10 and 11, which writes the `.zip`.
- On macOS, a windowed app's `Info.plist` is written by `plutil`, the bundle is signed ad hoc by `codesign`, and its disk image is made by `hdiutil`, all of which come with macOS. The disk image is a Mac OS Extended volume, as create-dmg makes, rather than the case-sensitive one Fledge wrote.
- On Windows, a program's version information and icon are written by rcedit 2.0.0 (MIT), which Windows runtimes carry in `tools/rcedit.exe` and no app holds; the runtime's folder of build tools, `installer/`, is now `tools/`. Linux apps' hicolor icons are the six sizes Briefcase asks for, no longer eight.
- A Linux app's AppImage begins with AppImage's own type 2 runtime, release 20251108, as AppImage publishes it (MIT, with libfuse 3.15.0, LGPL-2.1, squashfuse, zstd, zlib, mimalloc, and musl linked in), and its file system is written by `mksquashfs` with appimagetool's options, so building one needs squashfs-tools 4.4 or newer (`apt install squashfs-tools`). Each Linux release's source bundle now holds the runtime's source and libfuse's, and every Linux app's notices name them.
- A Windows app's NSIS installer is compressed with LZMA, NSIS's default, in place of zlib, and compiled by NSIS 3.13's own `makensis.exe`, which the Windows runtime now carries in `tools/nsis` with the stub, plug-ins, and Modern UI. NSIS's LZMA module is under the Common Public License 1.0; each Windows release's source bundle now holds NSIS's source, and every Windows app's notices say where it is.

### Removed

- **Breaking:** `fledge build` builds only for the computer it runs on; `-t` and `--target` are gone, and say so. Build the macOS app on a Mac, the Windows app on Windows, and each Linux app on Linux, as Tauri and Briefcase do.
- The `fledge-makensis-VERSION-PLATFORM.tar.gz` release assets, and the download of makensis: a Windows installer is built on Windows with the runtime's NSIS.

## [0.0.1.pre.7] - 2026-10-28

### Added

- Installers for windowed apps, each built beside its archive from any computer: `NAME-arm64-darwin.dmg`, a disk image of the app's bundle with a link to Applications, which hdiutil verifies and whose bundle stays signed; `NAME-x64-mingw-ucrt-setup.exe`, an NSIS installer that installs for the person who runs it, with no administrator, into `%LOCALAPPDATA%\Programs\NAME`, makes a Start menu shortcut carrying the app's identifier as its AppUserModelID (so Windows shows the app's notifications), offers an unchecked desktop shortcut, registers an uninstaller, and installs silently with `/S`; and `NAME-PLATFORM.AppImage` for Linux, which runs from its own FUSE mount, or extracts itself and runs where there is no FUSE.
- `fledge.yml` takes `installers`, a list of `dmg`, `nsis`, and `appimage`, or `[]`; a windowed app gets all three by default, and a console app none.
- `fledge build` prints each installer's path after its archive's.
- Linux runtimes carry `installer/appimage-runtime`, Fledge's build of AppImage's type 2 runtime (MIT), with squashfuse (BSD-2-Clause) and zlib compiled in and no libfuse, which it loads from the computer; the Windows runtime carries `installer/nsis/`, NSIS 3.13's stubs, plug-ins, and Modern UI (zlib license). No app's folder or archive holds either.
- Each release carries `fledge-makensis-VERSION-PLATFORM.tar.gz`, NSIS 3.13's makensis for each computer that builds apps, which `fledge build` downloads for an NSIS installer.

## [0.0.1.pre.6] - 2026-10-28

### Added

- Windowed apps: `kind: windowed` in `fledge.yml` builds an `.app` bundle for macOS, signed ad hoc so it runs on Apple Silicon and passes `codesign --verify --strict --deep`; a program Windows starts without a console, from the new `launcherw.exe` every Windows runtime carries; and, for Linux, the folder with `IDENTIFIER.desktop` and the icon in `share/icons/hicolor/`. Each builds from any computer.
- `fledge.yml` takes `kind`, `identifier`, `version`, `icon`, `publisher`, and `copyright`. A windowed app needs an `identifier`; `version` defaults to the gemspec's (or `0.0.0`), and `publisher` to its authors.
- Every Windows app's program carries version information (FileDescription, which Task Manager shows, ProductName, CompanyName, LegalCopyright, and the versions) and, with an `icon`, the app's icon.
- `icon` is one square PNG of at least 1024x1024 pixels, which Fledge makes into an `.icns` for macOS, icon resources for Windows, and hicolor PNGs for Linux.
- On Windows, an app with an `identifier` takes it as its AppUserModelID when it starts.

## [0.0.1.pre.5] - 2026-10-28

### Removed

- `fledge build` no longer judges an app's gems by their licenses, which are the app developer's to decide: a GPL, AGPL, MPL, or LGPL gem, a gem whose license is unknown, and one that declares none all ship, and an LGPL gem no longer needs its source pinned.
- A native gem's compiled files may hold any library: nokogiri's precompiled builds for `arm64-darwin` and `x64-mingw-ucrt`, and its build from source on Windows, which link GNU libiconv in, now ship. Compiled code no longer needs a review in Fledge's map or a `compiled` entry in `fledge.yml`, and a Rust extension's crates are no longer read with `cargo metadata` or judged.
- `notices/GEMS.txt`, and the warning for a gem that ships no license file. Each gem ships with its own files, its license files among them, in its own folder; `notices/` holds the notices of what Fledge itself puts in an app.
- **Breaking:** `fledge.yml`'s `licenses` and `compiled` keys. A `fledge.yml` that still has either fails the build, as any key Fledge does not know does; `name` is the one key left.

## [0.0.1.pre.4] - 2026-10-27

### Added

- `fledge build` compiles a gem with an extension to compile (one published only as source, such as redcarpet, or one from git) when the target is the platform it runs on, against the runtime's own Ruby: Xcode's command line tools on macOS (for macOS 14 and later), the C compiler on Linux, RubyInstaller's MSYS2 UCRT64 tools on Windows, and cargo for a Rust extension. `bundle config build.NAME` options reach the gem's `extconf.rb`, and `notices/GEMS.txt` says each gem was compiled, with which options.
- For any other target, such a gem fails the build, naming it and saying to build on that platform or choose a precompiled version.
- nokogiri ships for `arm64-darwin` when built from source on a Mac (`force_ruby_platform: true`, with `bundle config build.nokogiri --disable-xml2-legacy`), using macOS's own iconv.
- Git gems ship, from any computer, at the commit the lockfile locks, fetched into `~/.cache/fledge/git`: each gem's own folder of the checkout, where Bundler keeps it, with its gemspec evaluated, and none of the rest of its repository; a git gem's extension compiles as above.
- A Rust extension's crates, read from its build's `Cargo.lock` with `cargo metadata`, are listed in `notices/GEMS.txt` (those compiled in, and those that ran only while it compiled), and each must be under a license that asks nothing beyond notices.
- Each release carries `fledge-runtime-VERSION-PLATFORM-dev.tar.gz`, the runtime's build-only companion of Ruby's headers and libraries, which `fledge build` downloads only to compile a gem, and never ships.
- An LGPL gem ships, as its own files that whoever receives the app may replace, when its exact source is pinned: the gem itself when it is built for every platform or from git, and for a precompiled build its source package of the same version, which the lockfile must lock (`bundle lock --add-platform ruby`); `notices/GEMS.txt` names the source and what the LGPL asks. ratatui_ruby 1.5.2 ships this way.
- ratatui_ruby's precompiled builds are reviewed: each one's Rust crates, for its operating system, are listed in `notices/GEMS.txt`.
- `Unicode-3.0`, `Unicode-DFS-2016`, and `WTFPL` are notice-only licenses.
- `notices/GEMS.txt` quotes the license texts in a gem's `LICENSES/` folder.

### Changed

- A gem's compiled file that needs a shared library neither its operating system (on Linux, what manylinux_2_39 allows), the runtime, nor the gem itself provides fails the build.
- A path gem inside the project whose gemspec has an extension fails the build, since Bundler never compiles one.
- Which lockfile platforms, and which builds of a gem, fit a target is judged as the built app's Bundler judges it, from the runtime's own platform (`arm64-darwin-23` on macOS): a lockfile platform or gem built for `arm64-darwin-23` now fits `arm64-darwin`, and one built for `arm64-darwin-24` does not.

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

[Unreleased]: https://github.com/setdef/Fledge/compare/v0.17.0...HEAD
[0.17.0]: https://github.com/setdef/Fledge/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/setdef/Fledge/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/setdef/Fledge/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/setdef/Fledge/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/setdef/Fledge/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/setdef/Fledge/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/setdef/Fledge/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/setdef/Fledge/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/setdef/Fledge/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/setdef/Fledge/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/setdef/Fledge/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/setdef/Fledge/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/setdef/Fledge/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/setdef/Fledge/releases/tag/v0.5.0
[0.4.0]: https://github.com/setdef/Fledge/releases/tag/v0.4.0
[0.3.0]: https://github.com/setdef/Fledge/releases/tag/v0.3.0
[0.2.1]: https://github.com/setdef/Fledge/releases/tag/v0.2.1
[0.2.0]: https://github.com/setdef/Fledge/releases/tag/v0.2.0
[0.1.0]: https://github.com/setdef/Fledge/releases/tag/v0.1.0
[0.0.1.pre.17]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.17
[0.0.1.pre.16]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.16
[0.0.1.pre.15]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.15
[0.0.1.pre.14]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.14
[0.0.1.pre.13]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.13
[0.0.1.pre.12]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.12
[0.0.1.pre.11]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.11
[0.0.1.pre.10]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.10
[0.0.1.pre.9]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.9
[0.0.1.pre.8]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.8
[0.0.1.pre.7]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.7
[0.0.1.pre.6]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.6
[0.0.1.pre.5]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.5
[0.0.1.pre.4]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.4
[0.0.1.pre.3]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.3
[0.0.1.pre.2]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.2
[0.0.1.pre.1]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.1
