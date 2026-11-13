<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Research of 2026-11-12, before the prototype it argues for. Requested: written by agents and not reviewed line by line. ADRs cite these findings by this file.

# Phone extensions that no `extconf.rb` builds

On a phone, Fledge compiles a gem's extension only by running its `extconf.rb` with mkmf aimed at the phone, and refuses a gemspec whose `extensions` name a Rakefile, a `CMakeLists.txt`, or a `configure` (ADR 022). The maintainer, on 2026-11-12 (`decisions.md`): "Python and other languages that have Fledge-like tools must solve this somehow; so can we." This file answers four questions before any code:

1. What RubyGems runs for each kind of extension, and where it expects the built file.
2. How many real gems use each kind.
3. How other languages' tools aim a foreign build system at a phone.
4. What Fledge's own rules leave open.

Rust extensions through rb-sys are another agent's work and are left out here, except where they show up in the counts.

## In brief

- Of the 5,000 most-downloaded gems, 246 have extensions. 232 of those build with an `extconf.rb`, 14 with Rake, and 1 with `Cargo.toml`. **None builds with a bare `CMakeLists.txt` or `configure`.** Ranks 5,001 to 10,000 add 173 more: 156 `extconf.rb`, 16 Rake, 1 `Cargo.toml`, and again no CMake or `configure`.
- Of the 14 Rake gems, one builds extensions of Ruby's: digest-crc, at rank 173. Six link a library for Ruby's ffi to open at run time. Seven compile nothing: they install dependencies, write a path, or download a tool.
- RubyGems runs a Rakefile as `rake RUBYARCHDIR=DEST RUBYLIBDIR=DEST`. It runs `configure` with no `--host`, and CMake with only two output folders. Its own cross-compiling hook, `--target-rbconfig`, serves `extconf.rb` alone; the Rake, configure, and CMake builders warn that it is "not yet supported" and ignore it.
- Every tool studied aims a foreign build at a phone the same way. It sets one environment (`CC`, `CXX`, `AR`, flags), passes a CMake toolchain file through `CMAKE_TOOLCHAIN_FILE` and a `--host` triple to `configure`, and fakes the host language's view of the platform for any build script in that language. Where a build ignores all that, each tool falls back to a recipe per package.
- Only kivy-ios turns a build that links a shared module into a static one. It replaces the link command with `liblink`, which merges the objects with `ld -r`, records the libraries the link named, and archives the result. That is the prior art for Fledge's static extensions.

## 1. What RubyGems runs for each kind

All references are to RubyGems as Ruby 4.1.0-preview1 ships it: ruby/ruby at commit 2d08b5f42f2cbed4a4e6ecf8d62987a4f21f98c1 (`RUBY_REVISION` of the pinned Ruby), whose `lib/rubygems/ext/*.rb` are byte for byte the files installed with it (RubyGems 4.1.0.beta2).

**Choosing a builder.** `Gem::Ext::Builder#builder_for` matches the extension's path, in this order (`lib/rubygems/ext/builder.rb`, lines 196 to 211):

1. `/extconf/` gives `ExtConfBuilder`;
2. `/configure/` gives `ConfigureBuilder`;
3. `/rakefile/i` or `/mkrf_conf/i` gives `RakeBuilder`;
4. `/CMakeLists.txt/` gives a new `CmakeBuilder`;
5. `/Cargo.toml/` gives a new `CargoBuilder`.

**Where the result goes.** `#build_extensions` builds every extension into one folder, `dest_path = @spec.extension_dir`, and then touches `gem.build_complete` (lines 325 to 345). `#build_extension` runs each builder in the extension's own folder, passing it that folder, the build options, and `lib_dir`, the gem's first require path (lines 234 to 251). The extension folder is one of the gem's require paths, so `require` finds what a builder puts there.

**`make`.** `Builder.make` runs `make clean`, `make`, and `make install`, with `DESTDIR` and, when it is given a site folder, `sitearchdir` and `sitelibdir` (lines 24 to 71). It takes the `make` program from `MAKE`, then from `--with-make-prog` in the target's `configure_args`.

**`ExtConfBuilder`** (`lib/rubygems/ext/ext_conf_builder.rb`) runs `ruby extconf.rb`, adding `--target-rbconfig=PATH` when one is set (lines 26 to 30). It then runs `make` with a temporary site folder (line 41) and moves what `make install` put there into the extension folder (lines 55 to 58). It copies the result into `lib_dir` too, but not when cross-compiling (lines 45 to 53).

**`RakeBuilder`** (`lib/rubygems/ext/rake_builder.rb`, lines 9 to 38):

- It warns "--target-rbconfig is not yet supported for Rake extensions. Ignoring" (lines 12 to 14).
- For an `mkrf_conf` script, it first runs the script with `Gem.ruby` (lines 16 to 20). Such scripts customarily write a `Rakefile` of `task :default`.
- It then runs `rake` from `ENV["rake"]`, or from `Gem.bin_path("rake", "rake")` under `ruby -rrubygems` (lines 22 to 32), with `RUBYARCHDIR=DEST RUBYLIBDIR=DEST` and the build options (line 34).
- What happens next is the Rakefile's to decide. RubyGems expects nothing of it but an exit status of 0.

**`ConfigureBuilder`** (`lib/rubygems/ext/configure_builder.rb`, lines 9 to 26):

- It warns that `--target-rbconfig` is not yet supported (lines 12 to 14).
- Unless a `Makefile` exists, it runs `sh ./configure --prefix=DEST` with the build options and **no `--host`** (lines 16 to 20).
- It then runs `make`, which installs into the prefix (line 22).

**`CmakeBuilder`** (`lib/rubygems/ext/cmake_builder.rb`, lines 32 to 110):

- It warns the same (lines 41 to 43).
- It lists the gem's CMake presets (lines 85 to 109), then configures with `cmake DIR -B DIR/build -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=DEST -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=DEST`, plus `Gem::Command.build_args` and the options (lines 60 to 71).
- It builds with `cmake --build DIR/build --config release` (lines 73 to 81).
- It passes no toolchain file and no `BUILD_SHARED_LIBS`, so the `CMakeLists.txt` decides whether it links a module or a shared library.

**RubyGems' own hook for cross-compiling.** `Gem.set_target_rbconfig` loads another Ruby's `rbconfig.rb` as the target's (`lib/rubygems.rb`, lines 440 to 454). mkmf reads `--target-rbconfig=PATH` and loads that file into `MakeMakefile::RbConfig` in place of the running Ruby's (`lib/mkmf.rb`, lines 46 to 62). It is the mechanism Fledge's phone build already uses in another form, `-I ARCHDIR` (ADR 022). RubyGems has it for `extconf.rb` only.

## 2. How many real gems use each kind

**Method.** ecosyste.ms ranks RubyGems.org's gems by downloads (`https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages?sort=downloads&order=desc`, read on 2026-11-12). For each of the first 10,000 gems:

- Read the latest version's gemspec from RubyGems.org itself: the `metadata.gz` at the head of `https://rubygems.org/downloads/NAME-VERSION.gem`.
- Load it with RubyGems' own `Gem::Specification.from_yaml`.
- Classify each path in `extensions` as `Gem::Ext::Builder#builder_for` would.

The quick index's Marshal specifications could not serve: `Gem::Specification#_dump` leaves `extensions` out (`lib/rubygems/specification.rb`, lines 1387 to 1409 at the same commit). 64 of the first 5,000 could not be read. Most of those are JRuby-only gems, which have no `ruby`-platform `.gem` (403). Four are old gems whose `metadata.gz` is not at the head of the file.

| Ranks | Gems with extensions | extconf.rb | Rakefile or mkrf_conf | CMakeLists.txt | configure | Cargo.toml |
| --- | --- | --- | --- | --- | --- | --- |
| 1 to 1,000 | 73 | 68 | 6 | 0 | 0 | 0 |
| 1 to 5,000 | 246 | 232 | 14 | 0 | 0 | 1 |
| 5,001 to 10,000 | 173 | 156 | 16 | 0 | 0 | 1 |

A gem with two extensions counts once for each kind it has: google-protobuf has an `extconf.rb` and a Rakefile. Five of the first 5,000 depend on `rb_sys` (commonmarker, prometheus-client-mmap, tiktoken_ruby, parquet, tokenizers), and every one names an `extconf.rb`, so Rust hides among the `extconf.rb` gems; the one `Cargo.toml` is code_ownership's. Ten of ranks 5,001 to 10,000 depend on `rb_sys`. 75 of ranks 5,001 to 10,000 could not be read, for the same reasons.

**The Rake gems of the first 5,000.** Each was downloaded from RubyGems.org, its SHA-256 checked against RubyGems.org's API, and its extension's files read, not run.

| Rank | Gem | Extension | What its build does |
| --- | --- | --- | --- |
| 100 | unf 0.2.0 | `ext/mkrf_conf.rb` | Installs unf_ext only where `String#unicode_normalize` is missing, then writes `task :default`. |
| 115 | google-protobuf 4.36.2 | `ext/google/protobuf_c/extconf.rb` and `.../Rakefile` | The `extconf.rb` builds the extension. The Rakefile imports `lib/google/tasks/ffi.rake`, which builds a library for ffi with ffi-compiler, or warns and skips when ffi-compiler is missing (protocolbuffers/protobuf at tag v33.0, `ruby/lib/google/tasks/ffi.rake`, lines 50 to 100; the gemspec explains both, `ruby/google-protobuf.gemspec`, lines 29 to 39). |
| 173 | digest-crc 0.7.0 | `ext/digest/Rakefile` | For each of 28 `crc*` folders, runs `ruby -S extconf.rb` and `make`, and leaves `crcNN_ext.DLEXT` there (lines 16 to 46). The gem's `require_paths` are `ext` and `lib`, and `lib/digest/crc32.rb` line 89 runs `require 'digest/crc32/crc32_ext'` inside a `rescue LoadError`, so each CRC falls back to Ruby. |
| 291 | mimemagic 0.4.3 | `ext/mimemagic/Rakefile` | Writes `RUBYARCHDIR/mimemagic/path.rb`, naming the build computer's `freedesktop.org.xml`. |
| 507 | llhttp-ffi 0.5.1 | `ext/Rakefile` | `FFI::Compiler::CompileTask.new("llhttp-ext")`: a library for ffi. |
| 958 | http-parser 1.2.3 | `ext/Rakefile` | The same, `http-parser-ext`. |
| 1123 | sass-embedded 1.108.2 | `ext/sass/Rakefile` | Installs Dart Sass with npm, yarn, pnpm, or bun, and fetches protoc. |
| 1383 | ruby-debug-ide 0.7.5 | `ext/mkrf_conf.rb` | Installs debase, then writes `task :default`. |
| 1575 | karafka-rdkafka 0.32.0 | `ext/Rakefile` | Builds librdkafka with mini_portile2 (`configure --host`), and moves its shared library into `ext/` for ffi. |
| 1639 | rdkafka 0.31.0 | `ext/Rakefile` | The same file. |
| 1906 | scrypt 3.1.0 | `ext/scrypt/Rakefile` | `FFI::Compiler::CompileTask.new("scrypt_ext")`: a library for ffi. |
| 2154 | danger-swiftlint 0.37.5 | `ext/swiftlint/Rakefile` | Downloads SwiftLint. |
| 2300 | shoulda-callback-matchers 1.1.4 | `ext/mkrf_conf.rb` | Installs gems on Rubinius only, then writes `task :default`. |
| 4365 | ldclient-rb 5.5.6 | `ext/mkrf_conf.rb` | Requires openssl, then writes `task :default`. |

ffi-compiler takes `ENV['CC'] || RbConfig::CONFIG['CC']` and links with `-bundle` on macOS or `-shared` elsewhere (ffi/ffi-compiler at 2acb3b6c4ed51cffa8aab2acd142cf7d626312d7, `lib/ffi-compiler/compile_task.rb`, lines 115 to 121 and 263 to 267).

**The Rake gems of ranks 5,001 to 10,000** were read the same way. None builds an extension of Ruby's that builds today:

- Ten Ruby-GNOME gems (poppler, gdk_pixbuf2, rsvg2, atk, gdk3, clutter, gtksourceview3, clutter-gtk, and clutter-gstreamer at 4.4.0, and red-parquet at 26.0.1) name `dependency-check/Rakefile`. It checks a system library with pkg-config, and installs it with native-package-installer when it is missing (poppler 4.4.0's file, lines 17 to 44).
- lexxy 1.0.4 builds JavaScript with Yarn, and only when installed from git. eyes_universal 4.76.0 unpacks a server binary. naether 0.15.11 fetches Java jars. sup 1.4's `ext/mkrf_conf_xapian.rb` installs the xapian-ruby gem.
- webp-ffi 1.0.0 builds a library for ffi.
- xmlparser 0.6.81 builds an extension of Ruby's through mkrf. But its Rakefile requires `rake/gempackagetask` and `rake/rdoctask`, which Rake 13 no longer has (`lib/rake/` of rake 13.4.2 holds `packagetask.rb` only), so it fails on any current Ruby.

**What the counts say.**

- A bare `CMakeLists.txt` or `configure` is vanishingly rare among gems developers use. The gems that build such code do it from an `extconf.rb`, which Fledge already compiles and aims CMake for (ADR 027). rugged's `ext/rugged/extconf.rb` runs `cmake` for libgit2 (libgit2/rugged at 975853bd634a90407dc5c0f88aeff7dd5c1b44e7, lines 16 to 42), and nokogiri's runs libxml2's `configure` through mini_portile2 (sparklemotion/nokogiri at v1.18.10, 680374099b3570b97471f822acc978cc847fee46, `ext/nokogiri/extconf.rb`, lines 438 to 484). Neither was tried on a phone here.
- The Rake gems split three ways:
  - **Extensions of Ruby's, built by mkmf under Rake:** digest-crc.
  - **Libraries for Ruby's ffi:** six gems, and webp-ffi in ranks 5,001 to 10,000. A phone app opens no library at run time, so linking these is a separate question: ffi would have to find a symbol linked into the app.
  - **Install-time scripts that compile nothing:** seven gems, and fourteen more in ranks 5,001 to 10,000. On a phone these need only to run without failing, or to be left alone.

## 3. How other tools aim a foreign build at a phone

Code citations give the repository, the commit, the file, and the lines. Findings marked *checked* were read again, line by line, by the agent that wrote this file. The rest come from the research agents' reading at the same commits.

### cibuildwheel (pypa/cibuildwheel at 38712beeeaad4eb3f37077fde13964285f084b1c)

**Android** (`cibuildwheel/platforms/android.py`):

- It runs CPython's `android.py env` and copies each `export` into the build's environment (lines 431 to 448). CPython's `Platforms/Android/android-env.sh` sets `AR`, `CC=$toolchain/bin/${clang_triplet}${ANDROID_API_LEVEL}-clang`, `CXX`, `RANLIB`, and the rest (python/cpython at eb7cd6e636d7a01891b11b1e3b22e9fb4ea45412, lines 43 to 52), and `LDFLAGS` with `-Wl,-z,max-page-size=16384` (lines 62 to 71).
- *Checked:* `create_cmake_toolchain` writes `toolchain.cmake` and puts its path in the build's `CMAKE_TOOLCHAIN_FILE` (lines 320 to 324). The file sets `CMAKE_SYSTEM_NAME Android`, `CMAKE_SYSTEM_PROCESSOR`, `CMAKE_SYSTEM_VERSION 1` "to inhibit all of CMake's own NDK handling code", and the find-root paths (lines 329 to 348). Its comment: "we use environment variables as the single source of truth for compiler flags and paths".
- It rewrites the target's sysconfig data, blanking its flags so that the environment alone decides them "for any non-Python build systems which the build script may call" (lines 355 to 403).
- `CIBW_HOST_TRIPLET` turns on `_cross_venv.py`, which fakes `os.uname`, `sys.platform`, and `platform.android_ver` for the build's Python (lines 21 to 64 of that file).

**iOS** (`cibuildwheel/platforms/ios.py`):

- It writes no CMake toolchain file.
- It makes a cross virtual environment whose `sys.platform`, `platform`, and `sysconfig.get_platform()` say iOS (`resources/ios-support/_cross_arm64_iphoneos.py`, lines 11 to 79).
- Its compilers are wrapper scripts on `PATH` that CPython's iOS build carries: `arm64-apple-ios-clang` runs `xcrun --sdk iphoneos clang -target arm64-apple-ios$IPHONEOS_DEPLOYMENT_TARGET "$@"` (CPython's `Platforms/Apple/iOS/Resources/bin/`).
- It cuts `PATH` to a minimum so that Homebrew's macOS libraries cannot leak into an iOS binary (lines 270 to 334).

The result on both phones is a shared object in a wheel.

### crossenv (benfogle/crossenv at 61088b9a1ac1276c75f166b503bcbcb299ca9207)

- A wrapper `python` sets `_PYTHON_PROJECT_BASE`, `_PYTHON_HOST_PLATFORM`, `_PYTHON_SYSCONFIGDATA_NAME`, and `PYTHONHOME`, then runs the build Python (`crossenv/scripts/pywrapper.py.tmpl`, lines 19 to 52). Every Python the build starts therefore reads the target's sysconfig.
- Compilers come from that sysconfig (`crossenv/__init__.py`, lines 310 to 352). It does nothing for CMake, Meson, or `configure`.
- Its README says it builds "*most* Python packages", and that "in some cases manual intervention may still be necessary" (`README.rst`, lines 21 to 23).

### Briefcase and mobile-forge (beeware/briefcase at f9fc4cb9d1d5cd61474cfed2f1160a3952ce263f; beeware/mobile-forge at 36ad209fd2ee2d4a4e6c5205803711f9e9c35844)

**Briefcase** compiles nothing for a phone: it installs only binary wheels (`src/briefcase/commands/create.py`, lines 110 to 113).

**mobile-forge** builds those wheels from recipes, and has been frozen since cibuildwheel took over iOS (README, lines 3 to 15).

- A recipe for a C library runs its own `build.sh` with `HOST_TRIPLET`, `BUILD_TRIPLET`, and `PREFIX` (`src/forge/build.py`, lines 432 to 451), as `./configure --host="$HOST_TRIPLET" --build="$BUILD_TRIPLET"` (`recipes/libjpeg/build.sh`, lines 7 to 13).
- Its CMake builder was never written: `CMakePackageBuilder._build` is `pass` (lines 458 to 462).
- Its iOS `configure` scripts need a patched `config.sub` that knows `ios*-simulator` (README, lines 228 to 244).
- Of 26 recipes, 9 carry patches.

**How iOS loads a binary module.** CPython's testbed moves each `.so` into a framework of its own and leaves a `.fwork` file pointing at it (`Platforms/Apple/testbed/Python.xcframework/build/utils.sh`, lines 93 to 179, at the CPython commit above).

### Chaquopy (chaquo/chaquopy at 502ad46fe81532150b74fb6d299c4d85f5c61b03)

`server/pypi/build-wheel.py`:

- It sources `android-env.sh` and replaces `CC`, `CXX`, and `LD` with wrapper scripts (lines 571 to 624).
- It sets `LDSHARED="$CC -shared"` (lines 626 to 629).
- *Checked:* it writes `chaquopy.toolchain.cmake` and exports `CMAKE_TOOLCHAIN_FILE` "unconditionally, because we don't know whether the package requires CMake" (lines 717 to 719 and 737 to 775).
- A recipe's own build is then plain: `cmake .. -DCMAKE_INSTALL_PREFIX=$PREFIX`, or `./configure --host=$HOST`.
- Of 126 recipes, 61 carry patches. The README now sends new work to cibuildwheel (`server/pypi/README.md`, lines 3 to 7).

### PEP 730 and PEP 738 (python/peps at 155e5bee7d985ef30555b496eb994d24a591f70b)

**PEP 730 (iOS)** puts each binary module in a framework of its own (`peps/pep-0730.rst`, lines 104 to 123).

- It considered static builds and rejected them under "Supporting static builds" (lines 493 to 522), for "very slightly reduced app startup time" against two kinds of binary module.
- It leaves cross-building third-party modules to "tools like crossenv and cibuildwheel" (lines 350 to 358).

**PEP 738 (Android)** loads `libpython3.x.so` with `dlopen`, and every module links against it (`peps/pep-0738.rst`, lines 221 to 240).

### python-for-android (kivy/python-for-android at 1c9a4b4f817847bd8505d972d1a0e6f965929a88)

- `Arch.get_env` builds one environment for every recipe (`pythonforandroid/archs.py`, lines 109 to 233):
  - `CC` and `CXX` are the NDK's clang, with the target flags inside `CC` itself;
  - `AR`, `RANLIB`, `STRIP`, and `OBJCOPY` are the NDK's `llvm-*` tools;
  - `LDSHARED` is `CC -pthread -shared` (lines 36 to 41).
- `CompiledComponentsPythonRecipe` runs the package's own `setup.py build_ext` in that environment (`pythonforandroid/recipe.py`, lines 1074 to 1100).
- `MesonRecipe` writes a Meson cross file (lines 1517 to 1556).
- Recipes that wrap a C library call its build directly:
  - `./configure --host=TRIPLE` (`recipes/libffi/__init__.py`, lines 24 to 35);
  - `cmake -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=...` (`recipes/snappy/__init__.py`, lines 17 to 24).
- Results are shared libraries. There are 169 recipes with 100 patches.

### kivy-ios (kivy/kivy-ios at fd363d49eddb5ac06766348738bd89c7d46007f8)

This is the closest analogue to Fledge: static libraries, linked into one iOS executable.

- **Compilers.** `GenericPlatform.get_env` writes `CC` and `CXX` as shell wrappers around `xcrun -find -sdk SDK clang` with `--sysroot` and `-arch` built in, "because the ./configure test with the preprocessor (aka CC -E) without CFLAGS ... fails for cross compiled projects" (`kivy_ios/toolchain.py`, lines 193 to 256).
- **configure.** Recipes run it with `--host=TRIPLE --enable-static=yes --enable-shared=no` (`recipes/freetype/__init__.py`, lines 13 to 31).
- **Extension modules.** *Checked:* `CythonRecipe.get_recipe_env` sets `LDSHARED` to `tools/liblink` (`toolchain.py`, lines 1197 to 1206), and `liblink` stands in for the link of each module (`kivy_ios/tools/liblink`, lines 1 to 110):
  1. It keeps the link's `-l`, `-L`, and `-F` options and writes them to `OUTPUT.libs`.
  2. It writes an empty file where the `.so` was asked for.
  3. It merges the objects with `ld -r` into `OUTPUT.o`.
- **Archives.** `biglink` then archives every module's `.o` with `ar` (`tools/biglink`, lines 40 to 73).
- **Names.** Module init functions are renamed `PyInit_PACKAGE_MODULE` so that two cannot clash (`tools/cythonize.py`, lines 16 to 45). The app's importer finds each by name in the executable (`recipes/python3/dynload_shlib.patch`, lines 8 to 14).
- There are 47 recipes with 25 patches.

### Flutter and Dart's build hooks (flutter/flutter at 3b04b3b21d614748b0b1c18b22795b69dea4ddc5; dart-lang/native at b21ef2da3c580377f9465eac7f8ce22a097c0de6)

**Flutter's `plugin_ffi` template.**

- On Android it builds the plugin's `CMakeLists.txt` through the Android Gradle plugin's `externalNativeBuild`, which supplies the NDK's toolchain (`packages/flutter_tools/templates/plugin_ffi/android.tmpl/build.gradle.tmpl`, lines 34 to 53).
- On iOS it skips CMake and compiles the sources through a CocoaPods podspec (`ios.tmpl/projectName.podspec.tmpl`, lines 20 to 26).

**Dart's `native_toolchain_c`** calls the compiler itself, with `--target` and the sysroot, and never CMake or `configure` (`pkgs/native_toolchain_c/lib/src/cbuilder/run_cbuilder.dart`, lines 118 to 302). Static linking is "Not yet supported in the Dart and Flutter SDK" (`pkgs/code_assets/lib/src/code_assets/link_mode.dart`, lines 167 to 169).

### Tauri, cargo-mobile2, cc-rs, and cmake-rs

Commits: tauri-apps/tauri at 5edd31c8a8914674c217b21a660a914823da2dae; tauri-apps/cargo-mobile2 at 3b3184683b0c3fd6fdac5e7953428dac6eef51e2; rust-lang/cc-rs at 2215a2c6919217141d909d7be84a6481ddc032ba; rust-lang/cmake-rs at 42ffb61d1a21b2c182ecbc106984d10ffefb9789.

- **cargo-mobile2** runs `cargo build --target TRIPLE` with `TARGET_CC`, `TARGET_CXX`, and `TARGET_AR` set to the NDK's tools (`src/android/target.rs`, lines 238 to 266).
- **Tauri** requires a `staticlib` on iOS and hands `libNAME.a` to Xcode (`crates/tauri-cli/src/mobile/ios/xcode_script.rs`, lines 272 to 309).
- **cc-rs** reads target-scoped variables (`CC_aarch64_apple_ios`, `TARGET_CC`, `CC`; `src/lib.rs`, lines 5457 to 5473) and always makes a static archive (lines 2243 to 2245).
- **cmake-rs** sets `CMAKE_SYSTEM_NAME` `iOS` or `Android` when no toolchain file is given (`src/lib.rs`, lines 450 to 507), and stands aside for the NDK's file when `ANDROID_ABI` is set (lines 414 to 420).

### What recurs

1. **One environment aims every build.** `CC`, `CXX`, `AR`, and `RANLIB` name the phone's tools, with the target built into the compiler command or a wrapper script. Each tool says so outright: cibuildwheel's "single source of truth", python-for-android's `get_env`, kivy-ios's wrappers, cargo-mobile2's `TARGET_*`.
2. **CMake gets a toolchain file through `CMAKE_TOOLCHAIN_FILE`,** which CMake 3.21 and later read from the environment (cibuildwheel, Chaquopy). On Android it is the NDK's own `android.toolchain.cmake`, or a file that switches CMake's NDK handling off. Fledge already does this (ADR 027).
3. **`configure` gets `--host`** (Chaquopy, mobile-forge, python-for-android, kivy-ios), and on iOS often a patched `config.sub`. Ruby's own iOS build sidesteps the patch: its `configure_args` record `--host=aarch64-apple-darwin`, with the iOS target in `CC` (the Fledge iOS runtime's `rbconfig.rb`, `CONFIG["configure_args"]`).
4. **The host language is told it is the target,** for any build script written in it: crossenv's sysconfig name, cibuildwheel's cross environments. Ruby's counterpart is the target's `rbconfig.rb`, which Fledge already hands mkmf, and RubyGems' `--target-rbconfig`.
5. **A recipe per package is the fallback.** Patches and flags appear in about a third to a half of each corpus: Chaquopy 61 of 126, mobile-forge 9 of 26, python-for-android 100 patches over 169 recipes, kivy-ios 25 over 47.
6. **Everyone but kivy-ios ships shared objects.** Only kivy-ios intercepts a module's link to make it static (liblink, `ld -r`, `ar`, renamed init functions).

## 4. Fledge's constraints

- **Its own system and tools** (ADR 010): Xcode on a Mac for iOS, the NDK on a Mac or Linux for Android. Fledge downloads no toolchain onto a developer's computer.
- **Static, linked, and registered** (the former ADR 011, now ADR 079, ADR 022): every extension becomes an archive, linked into the app's executable on iOS or `libfledgeext.so` on Android, and registered with Ruby under the name `require` asks for.
- **The developer's gems are theirs** (ADR 007): Fledge runs each gem's own build and changes none of its files.
- **Every input is pinned** (AGENTS.md): a recipe database of Fledge's own would be one more input to pin and keep, for others' gems.
- **Code is a liability** (`decisions.md`, 2026-10-28): reuse RubyGems' builders and Ruby's own tools, and write only what none does.
- **The app's code is unchanged** (decisions 9 and 10): a gem whose Ruby says `require 'digest/crc32/crc32_ext'` finds its extension.

## 5. Options for Fledge

1. **Aim RubyGems' own builder at the phone, and intercept the shared link.**
   - Run `Gem::Ext::Builder`'s builder for the extension under this computer's Ruby, as a desktop build does (the former ADR 006, now ADR 091).
   - Every Ruby the build starts reads the phone's `rbconfig.rb` (prior art 4).
   - `CC` and `CXX` are wrappers of the phone's compilers (prior art 1 and kivy-ios's wrappers).
   - When the build links a shared library, the wrapper merges the objects with `clang -r`, renames `Init_NAME` as Ruby's `ext/extmk.rb` renames an extension it links in, and writes a static archive where the library was asked for (kivy-ios's liblink).
   - Once the build is done, each archive found where `require` looks (the gem's require paths, or the folder RubyGems installs into) is an extension, named by its path.
   - The same environment carries `CMAKE_TOOLCHAIN_FILE` for CMake and `--host` for `configure`, the next two kinds.
2. **A recipe per gem**, as python-for-android, kivy-ios, Chaquopy, and mobile-forge carry. This is a database of others' gems for Fledge to pin, patch, and keep, against ADR 007 and "code is a liability". The Python corpora show recipes are needed for the remainder, not instead of an environment.
3. **Ask each gem's author for an `extconf.rb`.** This is today's refusal, which the maintainer's words of 2026-11-12 overrule.
4. **Shared libraries, as Python ships them:** one framework per extension on iOS (PEP 730), and `dlopen` on Android (PEP 738). It reverses ADR 022's static design and the iOS runtime's `--disable-dln`. It would serve ffi libraries too, but that is a different question from extensions of Ruby's.
5. **Build each extension's sources directly, ignoring the gem's build**, as Flutter's iOS podspec does. This drops the gem's own configuration, which ADR 022 already rejected for `extconf.rb`.

Option 1 is the one the prior art supports. It is each tool's common core (an environment, a toolchain file, `--host`, a faked host platform), plus the one prior art for a static result from a shared link. It adds no recipe. A Rakefile that does something no environment reaches, such as hard-coding `cc` or reading the build computer's files, still fails or misbuilds. In the Python corpora, that remainder is where recipes live.

## Sources not read

- RubyGems.org's weekly PostgreSQL dumps (`https://rubygems.org/pages/data`) carry downloads but not gemspecs, so they could not classify extensions.
- No `CMakeLists.txt` or `configure` gem was found to read among the first 10,000 gems. Finding one past them would take a reading of every gemspec on RubyGems.org.
