<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a mini_portile2 bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://github.com/flavorjones/mini_portile/issues/new, with the title below, and everything after the line as the body (GitHub takes Markdown).

Why mini_portile2 and not SQLite: the `config.sub` that rejects the name is GNU's own (SQLite 3.54.1 ships it unchanged as `autosetup/autosetup-config.sub`, timestamp 2024-05-27), and it rejects `x86_64-w64-windows-gnu` just as it rejects `aarch64-w64-windows-gnu`; it accepts `windows` as a kernel only with `msvc` (its "validate the OS-kernel combination" block). Any autoconf project that mini_portile2 configures with clang targeting MinGW would fail the same way; SQLite is only where it was met. The name an autoconf `--host` takes for MinGW is `aarch64-w64-mingw32`, which that `config.sub` accepts.

Before filing: search mini_portile2's issues and pull requests for "clang", "windows-gnu", "detect_host", and "aarch64-mingw" (the tracker was not searched: agents here cannot reach it); check that `detect_host` on main still takes the `Target:` line as it is; check whether GNU config's current `config.sub` (https://git.savannah.gnu.org/cgit/config.git/tree/config.sub) has since learned `windows-gnu`, which would make the bug narrower (projects carrying an older `config.sub`) but not go away; and read the body start to finish as your own words. Found when sqlite3 2.10.2 would not compile on Windows 11 on ARM64 with RubyInstaller's ARM64 Ruby, whose compiler is MSYS2's CLANGARM64 clang. The reproduction below ran on macOS, with Apple clang 21 standing in for that clang (both print the same normalized triple); the whole `gem install sqlite3` on ARM64 Windows was not run for this report, and the suggested fix has not been run.

- **Title:** With clang targeting MinGW, `detect_host` gives `--host=aarch64-w64-windows-gnu`, which autoconf's `config.sub` rejects
- **Version:** mini_portile2 2.8.9

---

`MiniPortile#detect_host` takes the host triple from the `Target:` line of `$CC -v` (`lib/mini_portile2/mini_portile.rb`, lines 529 to 545 at 2.8.9), and `configure_defaults` passes it to `configure` as `--host` (lines 415 to 421). GCC prints a GNU triplet there, `x86_64-w64-mingw32`. clang prints LLVM's normalized triple instead: for `--target=aarch64-w64-mingw32` it prints `Target: aarch64-w64-windows-gnu`, and for `x86_64-w64-mingw32`, `x86_64-w64-windows-gnu`. autoconf's `config.sub` does not know those names, so `configure` stops before it starts.

This is what happens to sqlite3 on Windows on ARM64: sqlite3 2.10.2 publishes no `aarch64-mingw-ucrt` build, so `gem install sqlite3` compiles it, and its `extconf.rb` builds SQLite through `MiniPortile` with no host of its own (`minimal_recipe`, `ext/sqlite3/extconf.rb`, lines 153 to 165). RubyInstaller's ARM64 Ruby compiles extensions with MSYS2's CLANGARM64 clang, so `configure` gets `--host=aarch64-w64-windows-gnu` and SQLite's `config.sub` (GNU's, timestamp 2024-05-27) says:

```
Invalid configuration 'aarch64-w64-windows-gnu': Kernel 'windows' not known to work with OS 'gnu'.
```

## Reproduction

With any clang, on any system:

```sh
CC="clang --target=aarch64-w64-mingw32" ruby -e '
  gem "mini_portile2", "2.8.9"
  require "mini_portile2"
  recipe = MiniPortile.new("sqlite3", "3.54.1")
  p [recipe.host, recipe.send(:configure_defaults).first]'
# => ["aarch64-w64-windows-gnu", "--host=aarch64-w64-windows-gnu"]
```

Then, from the tarball sqlite3 2.10.2 carries (`ports/archives/sqlite-autoconf-3540100.tar.gz`):

```sh
sh sqlite-autoconf-3540100/autosetup/autosetup-config.sub aarch64-w64-windows-gnu
# Invalid configuration 'aarch64-w64-windows-gnu': Kernel 'windows' not known to work with OS 'gnu'.
sh sqlite-autoconf-3540100/autosetup/autosetup-config.sub aarch64-w64-mingw32
# aarch64-w64-mingw32
```

`x86_64-w64-windows-gnu` fails the same way, so an x64 build with clang (MSYS2's CLANG64) would meet it too.

## Suggested fix

Map LLVM's MinGW spelling back to GNU's in `detect_host`, so that `--host` is a name autoconf knows, leaving every other triple as it is:

```ruby
@detect_host = m[1].sub(/-windows-gnu\z/, "-mingw32")
```

`*-w64-windows-gnu` is LLVM's normalization of `*-w64-mingw32` (the two name the same target), so the result is the triple the compiler was asked for. A recipe that sets `host` itself is not affected.
