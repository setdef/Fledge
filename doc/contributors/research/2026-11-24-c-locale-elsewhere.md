<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-24 on how other Ruby packagers, other languages' packagers, and other Rubies behave when a program starts with no locale or in the C locale. Requested: written by an agent and not reviewed line by line. They add to `2026-11-13-c-locale.md`, which measured stock Ruby; they decide nothing.

# The C locale elsewhere: what packagers and Rubies do

Fledge's launcher makes Ruby use UTF-8 where `ruby main.rb` would use US-ASCII (`doc/differences_from_ruby.md`, "The locale"). Question #115 asks whether to keep that difference. This note reads how others meet the same start: a program that runs with no `LANG` or `LC_*`, or with `LANG=C`, as a double-click, a service manager, or a phone gives it.

Every file below was read through GitHub's API on 2026-11-24, at the commit named beside it. Nothing was run: these are readings of source, not measurements. Where a search found nothing, the note says "no hit", which shows only that the search found nothing, and not that the code has none. Redmine (`bugs.ruby-lang.org`), Python's documentation site, and graalvm.org could not be fetched; what a note below says of them comes from a file in a repository, or from `2026-11-13-c-locale.md`.

## Ruby packagers

**Traveling Ruby** (trubygems/traveling-ruby, `main` at 1b61f30e). Its tutorial's wrapper script, which the app developer writes and ships beside the runtime, starts Ruby with `-E UTF-8`: `exec "$LIBDIR/ruby/bin/ruby" -E UTF-8 -rbundler/setup -I "$LIBDIR/app/lib" "$LIBDIR/app/gem.rb" "$@"` (`docs/TUTORIAL.md`, line 110, and the same flag at line 152 for Rails). It sets no `LANG` or `LC_ALL` there, and `-E` is the only encoding handling in the tutorial. The runtime itself carries no locale code: `linux/internal/build-ruby.sh` has no `LANG`, `LC_`, or `encoding` line. `-E` sets `Encoding.default_external` and, through it, the filesystem encoding on Unix (`ruby.c`, lines 2517 to 2533, and `encoding.c`, lines 1689 to 1691, at ruby/ruby 7d0fa886); it does not change `Encoding.locale_charmap`, and `2026-11-13-c-locale.md` reads the load path's tagging as following the locale, not `-E`. Whether `-E UTF-8` alone mends the Bundler failures that note found was not measured. phusion/traveling-ruby (`main` at 0eac139b) holds no tutorial file; a search for `UTF-8` found only `traveling_ruby_restore_environment.rb`'s `# encoding: utf-8` and `.editorconfig`.

**Tebako** (tamatebako/tebako). The current `main` (e50ed3cb) is a rewrite in Rust. Its spawn code scrubs `RUBYOPT` and `RUBYLIB` from the child (`crates/tebako-cli/src/runner.rs`, lines 10 to 14) and a search of the repository for `setlocale`, `LC_CTYPE`, `LC_ALL`, and `default_external` found no code that touches the locale (`LC_ALL` appears only in `ci/macos-floor-symbol-check.sh`). The legacy C++ launcher, tag `legacy-v1/v0.15.9` (1bef3ed6), `src/tebako-main.cpp`, has no `setlocale`, `LANG`, `LC_`, or `setenv`; its only encoding code converts the executable's path to UTF-8 on Windows (`WideCharToMultiByte(CP_UTF8, ...)`, lines 96 to 145). So a Tebako app takes stock Ruby's behavior. Whether a Tebako app fails in a C locale was not run.

**ruby-packer** (pmq20/ruby-packer, last commit 677baf23, 2021-01-03). It carries Ruby's source, and its `ruby/main.c` has Ruby's own `setlocale(LC_CTYPE, "")` (line 151) and nothing else about the locale; a search of the repository for `setlocale` found only Ruby's files. Stock behavior.

**OCRAN** (largo/ocran, `main` at ae82f5c6). Windows only. A search for `encoding`, `LANG`, and `setlocale` found no hit. A Windows Ruby has had UTF-8 as `Encoding.default_external` since Ruby 3.0 (`doc/NEWS/NEWS-3.0.0.md`, lines 190 and 191, Feature #16604), so OCRAN has nothing to do.

**Where Ruby is deployed, not packaged.** The official Docker image sets `ENV LANG C.UTF-8` (docker-library/ruby, `Dockerfile.template`, line 36, `master` at 39856313), and Heroku's Ruby buildpack exports `LANG` as `en_US.UTF-8` by default (heroku/heroku-buildpack-ruby, `lib/language_pack/ruby.rb`, line 347, `main` at 1057d662). Both put the locale in the process's environment, where every program started from it sees it. Fledge exports nothing.

I found no other Ruby packager, and did not look beyond these.

## Other languages' packagers

**Briefcase** (BeeWare, Python). Its templates start the embedded CPython with an isolated configuration and force UTF-8. The macOS template's `main.m`: `PyPreConfig_InitIsolatedConfig`, then `preconfig.utf8_mode = 1` under the comment "Enforce UTF-8 encoding for stderr, stdout, file-system encoding and locale", then `preconfig.configure_locale = 1` (beeware/briefcase-macOS-Xcode-template, `{{ cookiecutter.format }}/{{ cookiecutter.class_name }}/main.m`, lines 68 to 78, `main` at 812e92df). The iOS template's `main.m` does the same (beeware/briefcase-iOS-xcode-template, lines 59 to 69, `main` at eccb2cde) and, before it, exports `LANG` itself: "iOS doesn't export an LANG environment variable; that variable is needed to set the locale correctly on startup", `setenv("LANG", "<locale identifier>.UTF-8", 1)` (lines 42 to 44). The Android template has no locale code that I found (a search for `utf` found only XML declarations); its Python is not the template's work, and I did not read Chaquopy.

**PyInstaller** (pyinstaller/pyinstaller, `develop` at 2bca40d1). The bootloader keeps CPython's rule. It starts Python with `utf8_mode = -1`, "default: auto-select based on locale" (`bootloader/src/pyi_pyconfig.c`, line 191), passes it on (line 350), sets `configure_locale = 1` (line 354), and lets the person override it with `-X utf8`. A test requires that a built program is in UTF-8 mode under `LC_CTYPE=C` and `LC_ALL=C` and `POSIX` on Linux and macOS (`tests/functional/test_misc.py`, lines 108 to 121). That is CPython's PEP 540, on purpose, in the packaged program.

**CPython's rule, for reference** (python/peps `main` at af21ad1e, `pep-0540.rst`): UTF-8 mode "is automatically activated when using the 'POSIX' locale" (lines 23 and 24), and "the POSIX locale enables the locale coercion (PEP 538) and the UTF-8 mode (PEP 540)" (lines 151 to 153). `2026-11-13-c-locale.md` and `launcher.md` already cover it and the differences between PEP 538 and what Fledge does.

**python-build-standalone** (astral-sh, `main` at 36dc10b3). A distribution of CPython, not a launcher. Its `docs/quirks.md` and `docs/running.md` say nothing about the locale or encodings (no line matches `locale`, `LANG`, `LC_`, `utf`, or `encoding` in either, beyond unrelated words). It leaves CPython's rule as it is.

**Tauri** (tauri-apps/tauri, default branch at ec000790). A search of the Rust sources for `setlocale` and `LC_ALL` found no hit. Rust's own `OsString` is the platform's bytes: "On Unix systems, strings are often arbitrary sequences of non-zero bytes, in many cases interpreted as UTF-8" (rust-lang/rust, `library/std/src/ffi/os_str.rs`, lines 25 and 26), so a Rust program's paths do not depend on the locale. Whether a webview or GTK sets the locale under Tauri was not read.

**Electron** (electron/electron, `main` at 26919e55). It asks the platform for the person's locale to choose the app's language, and it is careful not to change the process's: on Linux it sets `LC_ALL` for the duration of the call and then "reset[s] to the original `LC_ALL` since we should not be changing it" (`shell/browser/electron_browser_main_parts.cc`, lines 446 to 487). Its asar code records the cost of the C locale on a path: "On Linux, `FromUTF8Unsafe()` re-encodes through the C library locale and returns an empty path for non-ASCII input in the 'C' locale. Node mode never calls `setlocale()`, so it is always in the 'C' locale", and so it builds the path from the bytes (`shell/common/asar/asar_util.cc`, lines 231 to 235). So Electron's answer is to avoid the locale where it handles paths, not to set one.

**LÖVE** (love2d/love, `main` at def24510). A search for `setlocale` found no hit. Its filesystem module converts paths to UTF-8 itself on Windows (`src/modules/filesystem/physfs/Filesystem.cpp`, lines 674 and 755 call `to_utf8`) and Lua strings are bytes, so a game's paths do not pass through a Ruby-like encoding tag.

**Go** (golang/go, `master` at 87bf4e8d). `src/os/file.go` has no line about the locale or an encoding; a Go string is bytes, in practice UTF-8 (`src/strings/strings.go`, line 7, points to Go's note on UTF-8 strings). Paths do not depend on the locale.

**Flutter's embedders** were not read.

## The Rubies

**MRI** (ruby/ruby `master` at 7d0fa886). `Encoding.locale_charmap` is `nl_langinfo(CODESET)` on Unix (`localeinit.c`, lines 55 to 61), and its own documentation shows `LANG=C` giving `"ANSI_X3.4-1968"` (lines 71 to 74), glibc's name for US-ASCII. The default external encoding is that locale's, "UTF-8 on Windows and the locale on other operating systems" (`encoding.c`, lines 1744 to 1746; `ruby.c`, lines 2517 to 2533, where `IF_UTF8_PATH(uenc, lenc)` picks UTF-8 only when `UTF8_PATH` is defined, which `ruby.c` lines 563 to 566 do for `_WIN32` alone). The filesystem encoding follows `default_external` on every Unix and is UTF-8 on Windows (`localeinit.c`, lines 117 to 137). `NEWS-3.0.0.md` records the Windows change (Feature #16604); `NEWS.md` at `master` has no line about `locale` or `default_external`, and a search of `localeinit.c`, `encoding.c`, and `ruby.c` for `android` found nothing, so I found no special case for Android or any other platform and no change to the C locale. Bug #18495 (which `2026-11-13-c-locale.md` cites) was not read.

**JRuby** (jruby/jruby `master` at e8896dbd). It has no `nl_langinfo`. Its "locale" encoding is the JVM's default charset: `getLocaleEncoding()` is `Charset.defaultCharset().name()` looked up as a Ruby encoding, falling back to ASCII-8BIT if unknown (`core/src/main/java/org/jruby/runtime/encoding/EncodingService.java`, lines 195 to 213, "rb_locale_charmap...mostly"; the constructor does the same at lines 69 to 71). `Encoding.default_external` is the `-E` value or else that locale encoding (`Ruby.java`, lines 660 to 671), and the filesystem encoding follows it on Unix (line 677) while Windows takes `Options.WINDOWS_FILESYSTEM_ENCODING` (`EncodingService.java`, lines 478 to 497). The JDK's default charset is "UTF-8, unless changed" from JDK 18 (openjdk/jdk `master` at 3ee1e3c1, `src/java.base/share/classes/java/nio/charset/Charset.java`, lines 630 to 638, which also says `file.encoding=COMPAT` restores the one that "typically depends on" the operating system's `native.encoding`). So on a current JDK, JRuby gives UTF-8 for all three in a C locale, because the JVM stopped asking the locale, not because JRuby decided. The same JRuby on JDK 17 or older, or with `-Dfile.encoding=COMPAT`, would take the locale's, which the JDK takes from the environment; that was not run. Whether a JVM's file-name encoding (`sun.jnu.encoding`) follows the locale was not found in what I read.

**TruffleRuby** (oracle/truffleruby, `master` at 8d37cfad). It follows MRI and tells the person. `setupLocale` copies CRuby's `setlocale(LC_CTYPE, "")` (`src/main/java/org/truffleruby/RubyLanguage.java`, lines 941 to 962), and `EncodingManager` reads `nl_langinfo(CODESET)` (or `Charset.defaultCharset()` when embedded), takes `default_external` from `-E` or the locale (`EncodingManager.java`, lines 97 to 113 and 132 to 157), and, when the locale encoding is US-ASCII, logs a warning: "Encoding.find('locale') is US-ASCII ... this often indicates that the system locale is not set properly. Set LANG=en_US.UTF-8 and see ..." (lines 162 to 171), downgraded to a configuration-level message when `LANG=C` and `LC_ALL=C` are both set, "the parent process seems to explicitly want a C locale". Its page "Setting Up a UTF-8 Locale" (`doc/user/utf8-locale.md`) tells the person to set `LANG`: "You need a UTF-8 locale to run some Ruby applications. For example, we have found that RubyGems and ruby/spec need such a locale." So TruffleRuby leaves the C locale as US-ASCII and says it breaks RubyGems.

**Natalie** (natalie-lang/natalie, `master` at 255185b2). It follows MRI: `nl_langinfo(CODESET)` becomes `s_locale`, which becomes `s_default_external` and `s_filesystem` (`src/encoding_object.cpp`, lines 279 to 291).

**mruby** (mruby/mruby `master` at 087c6885). "mruby does not have an `Encoding` class. Strings are treated as byte sequences by default", with UTF-8 awareness a compile-time flag (`doc/limitations.md`, lines 164 to 169). No locale to meet.

**Artichoke** (artichoke/artichoke): a search for `default_external` found no hit; not read further.

## In short

| Project | In a C or absent locale | Sets the process's locale or `LANG`? |
|---|---|---|
| Traveling Ruby | Runtime stock; tutorial wrapper adds `-E UTF-8` | No |
| Tebako | Stock; nothing found | No |
| ruby-packer | Stock (Ruby's `main.c`) | No |
| OCRAN | Windows; UTF-8 since Ruby 3.0 | No |
| Docker's Ruby image, Heroku buildpack | Deployment sets UTF-8 | Yes, `LANG` exported |
| Briefcase macOS and iOS | CPython forced to UTF-8 mode | iOS exports `LANG`; macOS no |
| PyInstaller | CPython's automatic UTF-8 mode, tested | No |
| python-build-standalone | CPython's rule | No |
| Tauri, LÖVE, Go, Rust | Paths are bytes; no locale code found | No |
| Electron | Avoids the locale for paths; restores `LC_ALL` | No |
| MRI | US-ASCII; UTF-8 only on Windows | No |
| JRuby | JVM default charset: UTF-8 since JDK 18 | No |
| TruffleRuby | As MRI, with a warning and a UTF-8 locale guide | No |
| Natalie | As MRI | No |
| mruby | No encodings | Not applicable |

## What it means for Fledge's difference

These are findings, not a decision.

1. **No Ruby packager I read changes the encoding in its runtime.** Tebako and ruby-packer leave stock Ruby's behavior, OCRAN has none to leave on Windows, and Traveling Ruby leaves it to the developer's wrapper, where `-E UTF-8` is the one precedent. Fledge is the only one found that makes a C-locale start give UTF-8 in every Ruby of the runtime. None of them documents the failures `2026-11-13-c-locale.md` measured; whether their apps hit them was not run.
2. **The packagers of Python all end at UTF-8, and say so in code.** Briefcase forces it (and exports `LANG` on iOS, whose comment says iOS sets none); PyInstaller keeps CPython's automatic rule and tests it. That is the same answer as Fledge's, from a language whose own rule (PEP 540) already treats the C locale as UTF-8. Python's difference from stock, for a Python app, is nil; for Ruby it is a difference from `ruby`.
3. **The Rubies split.** MRI, Natalie, and TruffleRuby keep US-ASCII, and TruffleRuby warns and documents that RubyGems and ruby/spec need a UTF-8 locale. JRuby gives UTF-8 on a current JDK without its authors choosing it. So "Ruby in a C locale uses US-ASCII" is MRI's rule, not every Ruby's: on one maintained implementation, `Encoding.default_external` is UTF-8 under `LANG=C` today.
4. **Ruby's own direction on Unix is unchanged.** MRI made Windows UTF-8 in 3.0; `NEWS.md` and the locale files at `master` show no change for the C locale. The note of 2026-11-13 found Ruby doing that as the only change that closes the difference at its source.
5. **Where others set a locale for the program, they sometimes export it.** Briefcase on iOS, Docker's Ruby image, and Heroku's buildpack put `LANG` in the environment. Fledge sets the locale inside the process only and exports nothing, which Electron's code makes a point of too ("we should not be changing it"), so a program Fledge's Ruby starts sees the person's own environment.
6. **A third path exists that neither keeps nor reverses the coercion**: TruffleRuby's, which leaves the C locale and logs a warning that names the fix. It does not help a person who double-clicks and never meets Ruby (`AGENTS.md`, design precedence 1), and it is noted here only as the one other choice an implementation has made.
7. **What could not be found**: whether any packager's apps were reported failing in a C locale (no issue trackers were searched), what Chaquopy (Briefcase's Android) does, Flutter's embedders, Artichoke, Bug #18495's discussion, and how JRuby behaves under a JDK before 18.
