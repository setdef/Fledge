# Runtimes

A runtime is the part of an app Fledge doesn't build per app: a relocatable CRuby with its standard library and default and bundled gems, Fledge's launchers, the tools a build needs on that platform, and the notices of everything in it. Fledge's CI builds one per platform from pinned inputs, and the release publishes them; the gem pins each by SHA-256 and downloads the one it needs (ADR 093). This document maps both halves: building runtimes in `tasks/`, and finding them in `lib/`.

## Where fledge build finds a runtime

`Runtimes#archive(platform)` answers a path to the platform's archive, `fledge-runtime-VERSION-PLATFORM.tar.gz`:

1. **`FLEDGE_RUNTIME_DIR`,** when set, is the only place it looks. A file there must match the pin, unless `FLEDGE_RUNTIME_DIR_UNCHECKED` is set; one with no pin is used, and said to be unchecked. This is how a contributor builds apps on a runtime built locally.
2. **The cache,** `XDG_CACHE_HOME/fledge/runtimes` or `~/.cache/fledge/runtimes`, when its copy matches the pin. One that doesn't is downloaded again.
3. **A download,** from `FLEDGE_RUNTIME_MIRROR/vVERSION` when set, or else from the release, into the cache, through `Download.save`: locked against a second process downloading the same file, retried on transient failures, given up when it stalls, and kept only once its SHA-256 matches.

The pins are `lib/fledge/SHA256SUMS`, one release's `sha256sum` output, shipped in the gem. A Fledge that pins nothing for a runtime refuses to download it. `Runtimes#at_hand` is the no-network form, for `--from`, which must not download.

`RuntimeContents.read` lists an archive with `tar` and reads its `rbconfig.rb` and `RUBY_DESCRIPTION` without unpacking it: the Ruby version and patch level, the arch, the gem folder and the gems it holds, its shared libraries, its RubyGems plugins, its executables, and its extension API folder. Gems, Linkage, and the CLI's Ruby check all read these instead of guessing.

## What a runtime holds

| Part | Where in the archive |
| - | - |
| Ruby, its standard library, default gems, and bundled gems | `bin`, `lib`, `include`, `libexec` (on Windows, under `ruby`) |
| the launchers | `launcher`, and on Windows `launcherw.exe` too |
| build tools | `tools`: on Windows rcedit, NSIS, and `llvm-readobj.exe`; on Linux the AppImage runtime |
| Ruby's description | `RUBY_DESCRIPTION`, which the build reads and the app doesn't carry |
| notices | `notices`, with the sources of LGPL components, written by the [license audit](license-audit.md) |

`Assembly::RuntimeFolder` moves all of it into the app except the launchers (which it copies once per program), `tools`, `RUBY_DESCRIPTION`, and what only compiling gems needs: other libraries' headers, static libraries other than `libruby-static`, and `pkgconfig`.

## Where each platform's Ruby comes from

`runtime/sources.yml` pins every input by version and SHA-256, and says which build of Ruby each platform starts from:

| Platforms | Ruby from | Built by |
| - | - | - |
| `arm64-darwin`, `x86_64-linux`, `aarch64-linux` | [jdx/ruby](https://github.com/jdx/ruby)'s relocatable builds (`build: jdx`) | `RuntimeBuilder::Darwin` and `::Linux`, through `::Unix` |
| `x64-mingw-ucrt`, `aarch64-mingw-ucrt` | RubyInstaller's head builds, checked against RubyInstaller's signing key, and kept as assets of a Fledge pre-release | `RuntimeBuilder::Windows`, on a Unix host with llvm-mingw for the launchers |
| `x86_64-linux-musl`, `aarch64-linux-musl` | Ruby's source, compiled in an Alpine image pinned by digest, with pinned OpenSSL, libyaml, libffi, and zlib | `RuntimeBuilder::Musl` |
| `ios`, `android` | Ruby's source, cross-compiled | [Phone runtimes](phone-runtimes.md) |

`tasks/ruby_archive.rb` builds a Ruby archive from source, with `ruby-build`'s pins in `sources.yml`, in place of another project's build, as an archive a platform's `build` can name.

The rest of a runtime build is the same on every platform: compile the launchers with hardening flags and check the result has the protections its platform allows (`RuntimeBuilder::Hardening`); prune what no Ruby code reads, and gems' build leftovers, while keeping every default and bundled gem (`::Pruning`); install `runtime/rubygems/operating_system.rb` as RubyGems' defaults, so the runtime looks for gems only in its gem folder, and on Windows loads RubyInstaller's DLL setup; write `RUBY_DESCRIPTION`; run the license audit; and pack the archive.

`RuntimeBuilder::Key` records everything a build depends on (the pins, the launcher's sources, the build tasks, the toolchain's versions), and a build whose key matches the last one reuses its runtime, saying so; a mismatch names what changed.

## The tasks

| Task | What it does |
| - | - |
| `rake runtime[PLATFORM]` | builds this computer's runtime, or PLATFORM's (such as `android` on a Mac or Linux), into `tmp/runtime` |
| `rake runtime:prove[PLATFORM]` | builds the runtime and runs CI's checks of apps built from it, before the push of a runtime change |
| `rake runtime:pin[RUN]` | writes `lib/fledge/SHA256SUMS` from the runtimes a CI run built, before a release is tagged |

## Traps

- **A runtime builds only on the platform it is for,** except Windows', which needs llvm-mingw and builds on the Unix hosts it is pinned for, and Android's.
- **A runtime's glibc floor is 2.28.** The Linux build names any of the runtime's files that needs a newer glibc, since every app built on that runtime would inherit the need.
- **Pins move together.** A Ruby pin appears in several places (`ruby`, `mobile.ruby`, `musl-ruby.ruby`, `ruby-build.ruby`); `runtime/upstreams.yml` says which pins each upstream moves, and [Project tools](project-tools.md) moves them.
- **`SHA256SUMS` is one release's.** Every line is one of that release's assets; `rake runtime:pin` writes them all, and a hand-edited line breaks every build of that platform.

## What this part doesn't do

- Build a runtime during `fledge build`. Developers never compile Ruby.
- Use the developer's Ruby, or a Ruby on the computer the app runs on.
- Change a released runtime. A fix is a new release.
