# Ship gems with C extensions

A gem with a C extension, such as `sqlite3` or `nokogiri`, arrives in one of two forms: precompiled, as a build for one platform, or as source that compiles when it installs. `fledge build` handles both, and checks that every compiled file can load on a computer other than yours. This guide covers what each platform needs from you.

## Compile from source

When `Gemfile.lock` locks a gem as source (its platform is `ruby`), fledge compiles it with the runtime's Ruby and RubyGems, as `gem install` would, with any build options you gave Bundler (`bundle config set build.GEM ...`). So the build computer needs what compiling needs, as for any `bundle install`:

| Platform | The computer that builds needs |
| - | - |
| macOS | Xcode's command line tools (`xcode-select --install`) |
| Linux | a C compiler and `make`, such as Debian's and Ubuntu's `build-essential`, and the development package of each library the gem compiles against |
| Windows | MSYS2's toolchain, as RubyInstaller's `ridk install` sets it up; fledge puts it on the build's `PATH`, as `gem install` does |

When a gem's extension fails to compile, fledge prints the compiler's output and one line naming the gem, and stops.

> [!WARNING]
> Some gems' `extconf.rb` skips the build and exits successfully when a library it needs is missing. The app would then carry the gem without its extension, and fail when the program requires it. fledge warns when a gem that lists an extension leaves no shared library: read the build's output above the warning, and install what it names.

## Use a precompiled build

A gem's precompiled builds are locked only for the platforms in `Gemfile.lock`'s `PLATFORMS`. When the lockfile has no build for the platform you're building on, fledge says so and names the command to add it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle lock --add-platform x86_64-linux
```
<!-- SPDX-SnippetEnd -->

Run it on any computer, commit the lockfile, and build again. fledge picks the build Bundler would pick on each platform, and falls back to the source build when a precompiled one requires a Ruby other than the runtime's.

## Linux: the glibc an app needs

A compiled file needs the glibc it was compiled against, or a newer one. Fledge's Linux runtime runs on glibc 2.28 and later, and `fledge build` records in the app's `fledge.cfg` the newest glibc any compiled file needs. When a gem raises that floor, fledge warns, and the app runs only where glibc is that new.

To keep an app running on older distributions:

- For a gem compiled from source, build on a Linux with an older glibc, such as AlmaLinux 8, whose glibc is 2.28.
- For a precompiled gem, lock a build for an older glibc if the gem has one, or compile it from source on an old-glibc Linux, with `force_ruby_platform: true` on its line in the `Gemfile`.

A `.deb` depends on the glibc the build recorded.

## Linux: libraries from the distribution

fledge refuses a gem whose compiled file needs a library that neither every Linux distribution, nor Fledge's runtime, nor the gem itself provides, since the app could not load it on another computer. When every computer the app goes to gets that library from its distribution, such as GTK for a desktop app, list it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
linux:
  system_libraries: [libgtk-3.so.0]
```
<!-- SPDX-SnippetEnd -->

Write each library's name as it appears in the gem's compiled file, which the refusal shows. The app then checks for each listed library when it starts, before Ruby does, and when a computer lacks one, says which one to install from the distribution's packages, and exits with status 72. A `.deb` depends on the package that provides each.

Libraries a program opens itself, with Fiddle or FFI, appear in no compiled file, so fledge cannot find them. Name the packages that provide them in `deb_depends`, so that a `.deb` installs them:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
linux:
  deb_depends: ["libadwaita-1-0 (>= 1.4)"]
```
<!-- SPDX-SnippetEnd -->

The same goes for GObject introspection data that a gem such as `gtk4` reads while the app runs: list it in `system_typelibs`, and the app checks for it at start.

## Linux with musl

Fledge has runtimes for Alpine and other Linux distributions with musl. A gem built for glibc cannot load there, so fledge refuses it, and says to use the gem's musl build or have Bundler compile it from source, with `force_ruby_platform: true` on its line in the `Gemfile`. Build the musl app on a musl Linux, such as in an Alpine container.

## macOS: the oldest macOS

Fledge's macOS apps run on macOS 26.0 and later. fledge compiles gems with `MACOSX_DEPLOYMENT_TARGET=26.0`, and refuses a compiled file that needs a newer macOS. A gem whose file needs a newer one usually sets a deployment target in its `extconf.rb`; the refusal shows the file, so you can check.

## macOS: libraries from this computer

A gem compiled on your Mac may link a library you installed, such as one from Homebrew. fledge refuses it until you list the library, and then the app carries a copy:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
macos:
  carried_libraries: [libSDL3.0.dylib]
```
<!-- SPDX-SnippetEnd -->

fledge copies each listed library into the app's `lib/carried`, and points every file that loads it at the copy. When a carried library loads another one, fledge names it, and you list it too.

> [!WARNING]
> You distribute each carried library with your app, so you need the right to distribute it. Read its license first.

## Windows: Microsoft's Visual C++ runtime

A gem's DLL built with Microsoft's compiler may need the Visual C++ runtime (`vcruntime140.dll`, `msvcp140.dll`), which Windows does not include. fledge refuses such a gem until `fledge.yml` says how the app comes by the runtime:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
windows:
  visual_c_runtime: central
```
<!-- SPDX-SnippetEnd -->

- `central` ships none. The app checks for each DLL at start, and when one is missing, names it and says where to download Microsoft's Visual C++ Redistributable. The setup program installs the Redistributable when it is missing.
- `local` copies the DLLs from your computer's System32 into the app. Microsoft allows that only to licensed Visual Studio users.

A gem built so that it links the runtime statically (`/MT`) needs neither.

## Gems on a phone

A phone's app takes every gem's source build. fledge compiles the extensions an `extconf.rb` or a Rakefile builds, including Rust extensions through `rb_sys`, for each phone target, and links them into the app. [Build for iPhone and Android](phones.md) covers it.

## What fledge doesn't judge

fledge checks whether each compiled file can load where the app goes, and nothing about a gem's license: the gems your app depends on are yours to choose, and their licenses yours to comply with.
