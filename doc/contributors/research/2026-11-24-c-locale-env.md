<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-24 on a way to close the C locale difference that `2026-11-13-c-locale.md` and `2026-11-24-c-locale-elsewhere.md` did not weigh: set a UTF-8 locale in the environment before Ruby boots, in place of coercing it inside the process. Requested: written by an agent and not reviewed line by line. They add measurements for question #115; they decide nothing.

# The C locale: setting the environment instead of coercing

Today the launcher makes Ruby choose UTF-8 where `ruby main.rb` would choose US-ASCII, by calling `setlocale` itself and exporting nothing (`doc/contributors/design/launcher.md`, "The locale"). The alternative measured here is the one Briefcase's iOS template and the official Docker Ruby image take: when the app starts with no locale, or with `C` or `POSIX`, the launcher puts a UTF-8 locale in the environment, and Ruby's own `setlocale(LC_CTYPE, "")` (`main.c`, line 58) then chooses UTF-8 by its ordinary rule. The difference moves from Ruby's encodings to a variable in `ENV`. These findings measure what each candidate value does to stock Ruby; no Fledge code ran.

## How it was measured

Stock Ruby 4.1.0-preview1 (the pin of `runtime/sources.yml`), started with `env -i`, so only `PATH`, `HOME`, and the candidate variable were set. Scripts of 2026-11-24 (not kept in the repository; `probe.rb` ran inside the folder, `run.rb` drove 16 cases and printed the tables below). Each case ran in a folder `My Apps/Ünïcödé 日本/app`, as `2026-11-13-c-locale.md` did.

| System | Ruby | Placement |
|---|---|---|
| macOS 27.2.1, arm64 | jdx/ruby's `4.1.0-preview1-1` archive, SHA-256 checked | Ruby unpacked inside the folder, as in a Fledge app. Run on a Mac with Homebrew present (the build node's run never started); the child Ruby's failure under a C locale was seen by one separate run of the probe |
| glibc Linux, Ubuntu 26.04, with `en_US.UTF-8` generated | jdx/ruby's archive for x86_64 | inside the folder |
| glibc Linux, Ubuntu 24.04 (WSL2), glibc 2.39, `C.utf8` the only UTF-8 locale | the same | inside the folder |
| musl Linux, the Alpine 3.24 image `ruby:4.1.0-preview1-alpine3.24` of `runtime/sources.yml`, unpacked from Docker Hub and entered with `unshare -Ur chroot` on the WSL2 node | the image's own Ruby, at `/usr/local` | the app inside the folder, Ruby at an ASCII prefix: the image's Ruby is not relocatable, so Bundler's failures that need Ruby inside the folder could not be reproduced there |

jdx/ruby's archive is relocatable, which mise's installed copy of it is not (a copy of mise's Ruby kept its original prefix), so the archive itself was used. Windows is out of scope. iOS and Android were not measured, only read (below).

## Which value each system honours

"UTF-8" below means `Encoding.locale_charmap` is `"UTF-8"` and `default_external`, `Encoding.find("locale")`, and `Encoding.find("filesystem")` are UTF-8. Each value was set alone, as `LANG`, as `LC_CTYPE`, and (for `C.UTF-8` and `en_US.UTF-8`) as `LC_ALL`. Where `LANG` and `LC_CTYPE` differ for a value, the table says so.

| Value | macOS 27 | glibc, Ubuntu 26.04 | glibc, Ubuntu 24.04 with `C.utf8` only | musl (Alpine 3.24) |
|---|---|---|---|---|
| no variable | US-ASCII | US-ASCII | US-ASCII | **UTF-8** |
| `C`, `POSIX` | US-ASCII | US-ASCII | US-ASCII | US-ASCII |
| `C.UTF-8` | UTF-8 | UTF-8 | UTF-8 | UTF-8 |
| `C.utf8` | **US-ASCII** | UTF-8 | UTF-8 | UTF-8 |
| `UTF-8` | UTF-8 | **US-ASCII** | **US-ASCII** | UTF-8 |
| `en_US.UTF-8` | UTF-8 | UTF-8 | **US-ASCII** | UTF-8 |

The table reads the same for `LANG` and `LC_CTYPE`, on every system, and for `LC_ALL` with the values tried as `LC_ALL` (`C.UTF-8` and `en_US.UTF-8`). `C` and `POSIX` were tried as `LANG` only. `LANG=C` with `LC_CTYPE=C.UTF-8` gives UTF-8 on all four, so `LC_CTYPE` wins over a `LANG=C` the person set; `LC_ALL=C` with `LC_CTYPE=C.UTF-8` gives US-ASCII on all four, so a person's `LC_ALL` wins over the launcher's `LC_CTYPE`, as it would over a person's own.

So no one value works everywhere: `C.UTF-8` is the only one that worked on all four, and the report of Bug #18495, as `2026-11-13-c-locale.md` states it, that macOS gave US-ASCII under `LC_ALL=C.UTF-8`, did not reproduce on macOS 27, where `LC_ALL=C.UTF-8` gave UTF-8 (older macOS versions were not tried). A system that has only `en_US.UTF-8` generated, such as a glibc without `C.UTF-8` (glibc before 2.35 does not build it in; RHEL and CentOS 7, glibc 2.17, the floor of jdx/ruby's Linux archives, were not available to try), would need that name. The launcher's current list (`C.UTF-8`, `C.utf8`, `UTF-8`, `en_US.UTF-8`, each kept only when `setlocale` accepts it and `nl_langinfo(CODESET)` says UTF-8) already copes with all of the above; an environment approach would run the same search and then export the winner.

**musl differs.** With no locale variable at all, the Alpine image's Ruby already gives UTF-8, and only an explicit `LANG=C`, `LANG=POSIX`, or `LC_ALL=C` gives US-ASCII. Every value that names UTF-8 works there, even `UTF-8` and `en_US.UTF-8` with no locale files installed. So on musl the coercion matters only for an app started with `C` or `POSIX` set; the common double-click case already behaves as the developer's terminal does. Why musl does this was not looked into.

## What the failures of 2026-11-13 do under each value

With Ruby inside the non-ASCII folder (macOS and glibc), in every case that gives UTF-8 above:

- `require "bundler/setup"`, `ruby -rbundler/setup`, and `bundle -v` run. Where the encodings are US-ASCII they fail as the note of 2026-11-13 recorded: in Bundler's vendored Thor, `command.rb` line 3, on Linux, and in `Bundler::SharedHelpers#clean_load_path` (`shared_helpers.rb`, line 391) on macOS; and `bundle -v` raises in `FriendlyErrors` (`friendly_errors.rb`, line 98).
- With Ruby inside the folder, `bundle exec ruby -e ...` fails with "incompatible character encodings: BINARY and UTF-8" under every UTF-8 value too. That is the fourth failure of the earlier note (`CLI::Exec#ruby_shebang?`), not the locale's; Fledge's launcher does not reach it. With Ruby at an ASCII prefix (musl here) it runs in every case.
- App code: `__dir__ =~ /app/`, `__dir__.split("/")`, `File.join(__dir__, "café")`, `File.expand_path("café")` raise (`ArgumentError`, `Encoding::CompatibilityError`) under no locale, `C`, and `POSIX`, and run under every UTF-8 value. `File.read` returns UTF-8 text, not US-ASCII with invalid bytes. `$LOAD_PATH` is UTF-8, not BINARY. `Dir.glob` names are UTF-8 either way.
- A Ruby the app starts (`RbConfig.ruby`, by `system`, backticks, or `IO.popen`) inherits the variable and so is UTF-8 too. Without it, the same child Ruby inside that folder fails at boot under a C locale with a stack of "already initialized constant RbConfig" warnings and then "incompatible character encodings: UTF-8 and ..." (seen on macOS and glibc Linux).

On musl, with Ruby at an ASCII prefix, Bundler ran in every case, including the C locale: only the app's own code raised, in the C cases, as above.

## What else a value changes

- **`ENV`.** The app sees the variable. `ENV["LC_CTYPE"]` (or `LANG`) is present where the person set none, `ENV.to_h` and `ENV.keys` differ from `ruby main.rb`'s, and `env` in a child shows it. Measured: a child `env` lists exactly the variable set. With `LANG=C` the person set, and `LC_CTYPE=C.UTF-8` added, the app sees both, a combination no person's shell gives.
- **Programs that are not Ruby.** They inherit it. Their character handling follows UTF-8 (this was not measured beyond `sort`).
- **`LANG` against `LC_CTYPE`.** `LANG` is read for every category by any program that calls `setlocale(LC_ALL, "")`, which Ruby itself does not (it sets `LC_CTYPE` only); `LC_CTYPE` alone leaves the other categories at `C`. Measured with `sort` of `b A a B é e z` in a child: `LANG=en_US.UTF-8` and `LC_ALL=en_US.UTF-8` give `a A b B e é z` on macOS and glibc where a locale file exists (collation changed), while `LC_CTYPE=en_US.UTF-8` and every `C.UTF-8` give `A B a b e z é`, the C order. Messages (`LC_MESSAGES`) were not measured, because every system here had English only; `LC_CTYPE` leaves them alone by POSIX's rules, and `LANG=C.UTF-8` gives English too. So the narrowest variable that works is `LC_CTYPE`, and `C.UTF-8` the narrowest value where it exists.
- **`LC_ALL` and `LC_CTYPE` set by the person** stop the launcher, as today (launcher.md, step 2): a person's `LC_ALL=C` still gives US-ASCII.

## Phones, by reading

- **iOS.** Not measured. Briefcase's iOS template exports `LANG` with a UTF-8 locale identifier because "iOS doesn't export an LANG environment variable; that variable is needed to set the locale correctly on startup" (`2026-11-24-c-locale-elsewhere.md`). That says the variable works on iOS for CPython. iOS and macOS share Darwin's libc, and macOS honoured `C.UTF-8`, `UTF-8`, and `en_US.UTF-8` here, but `C.utf8` not, so an iOS app would use one of those three; this is an inference, not a run.
- **Android.** Not measured. `2026-11-13-c-locale.md` quotes PEP 538: on Android `setlocale(LC_CTYPE, "")` gives `"C"` whatever the environment, which is why CPython calls `setlocale(LC_CTYPE, "C.UTF-8")` itself there. If that holds for Ruby, an environment variable would not reach Ruby's `main.c` on Android, and the in-process call that Fledge makes today would still be needed there. The design document of the phone runtimes (`phone-runtimes.md`) says only that Android 8's bionic has the `nl_langinfo` that Ruby's `localeinit.c` calls.

## What this option would close, and what remains

It would close, on macOS and glibc Linux wherever a value of the list works, what the coercion closes today: the three encodings are UTF-8, `$LOAD_PATH` and `__dir__` are valid UTF-8, Bundler and Thor set up the app, and app code that joins or matches its paths runs. It would also reach a Ruby that is not Fledge's and that the app starts, and every Ruby the app starts through any path, with no copy of the search in `bin/ruby`. On musl it would add nothing for a launch with no variable, which is UTF-8 already.

What remains is a difference in `ENV` the app can see: `LC_CTYPE` (or `LANG`) present where the person set none, inherited by every child process, and added beside a `LANG=C` the person did set. `Encoding.locale_charmap` is `"UTF-8"` in both designs. It does not reach Android, if PEP 538 describes bionic. It does not remove the need for a value that works on the system, so the launcher keeps its search.

The launcher already puts the person's variables aside while it boots Ruby and restores them before the program runs (`launcher.md`, "The Bundler environment"). A variant of this option would set `LC_CTYPE` for Ruby's boot and delete it from `ENV` after, so that the app's `ENV` is the person's own; Ruby's `main.c` reads it once, at boot. That variant was not run. It would leave the app's child Ruby with no variable, so `bin/ruby` would still coerce for itself.

## Lines these findings make untrue

None in the documents of the repository. `launcher.md`'s statement that exporting nothing keeps `ENV` the person's remains true of today's code; this note describes an alternative.
