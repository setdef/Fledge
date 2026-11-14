<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Requested: written by an agent and not reviewed line by line. An adversarial audit, made on 2026-11-12 at commit 173ddc1a, of every difference Fledge accepts between a built desktop app and `ruby main.rb` or `bundle exec`. It changes no code, no justification, and no ADR; the orchestrator decides what to land.

# An Adversarial Audit of Desktop Parity

The maintainer, 2026-11-12: "Every difference, every lack of parity, is a knife in Fledge's back that could kill the project before it launches." Two accepted justifications had just collapsed: Android's `$0 =`, called impossible and then fixed in about 25 lines, and `fiddle` left out of iOS "for App Review" on a sentence nobody checked. This audit assumes every other justification may be the same, and tries to break each one.

## Scope and method

The audit covers the 28 desktop entries of `test/parity_justified.yml` (every entry of `Parity::JUSTIFIED` in `tasks/parity.rb` whose platforms include a desktop, numbered J1 to J28 below in the file's order) and every section of `doc/differences_from_ruby.md`. The phone entries (`Parity::MOBILE_JUSTIFIED`) are out of scope.

Each entry is put in one class:

- **(A) Inherent:** the difference is the shipped location or configuration itself, and `ruby main.rb` or `bundle exec` run from that same place, with that same configuration, would differ the same way.
- **(B) Forbidden:** an operating system, or Design precedence 1 (a person never meets Ruby), truly requires it.
- **(C) Closable:** Fledge could remove it.

"Developer" marks a difference an app developer's code can meet in a real app; "probe" marks one only the parity probe sees.

Evidence is Ruby 4.1.0-preview1's own library as mise installs it on this Mac (`~/.local/share/mise/installs/ruby/4.1.0-preview1/lib/ruby/4.1.0+5`, cited below as `LIBDIR/`), the gems installed beside other Rubies there, RubyInstaller's source at the pinned commit 92a692c (`runtime/sources.yml`, line 24), and a few narrow measurements, each given with its command. No runtime was built for this audit.

## The entries

| # | Fact, check | What differs | Class | Who meets it |
|---|---|---|---|---|
| J1–J3 | `$0`, `__FILE__`, `$PROGRAM_NAME`; script | `"main.rb"` against `"<app>/main.rb"` | A | developer |
| J4–J6 | the same; bundle | `"exe/my_cool_app"` against `"<app>/my_cool_app"` | A | developer |
| J7 | `$LOAD_PATH`; bundle | gems under the person's `GEM_HOME` against the runtime's gem folder | A | probe |
| J8 | `$LOADED_FEATURES`; bundle | Bundler's files from the same two places | A | probe |
| J9–J10 | `ENV`, child `ENV`; bundle | `BUNDLE_BIN_PATH`, `BUNDLER_SETUP`, `RUBYLIB`, `RUBYOPT` naming those places | A | probe |
| J11–J13 | `$LOAD_PATH`, `gems`, `requireable`; bundle | rake, a development gem, missing from the app | closed: `feat(lib)!: ship the development and test groups, as bundle exec loads them` | developer |
| J14–J15 | `ENV`, child `ENV`; bundle | `GEM_HOME` and `PATH` naming those places | A | probe |
| J16 | `$VERBOSE` | `nil` (person's `RUBYOPT=-W0`) against `false` | B | developer |
| J17 | `$LOADED_FEATURES`; bundle | `rubygems/yaml_serializer.rb` in the app, and a hollow `Psych` in `Object.constants` | closed: `fix: set Bundler up from the environment, so nothing defines a hollow Psych` | probe |
| J18 | `$LOADED_FEATURES`; bundle | `bundler/feature_flag.rb` under `bundle exec` | A | probe |
| J19 | `$LOADED_FEATURES`; bundle | the project's `lib/my_cool_app/version.rb`, loaded by the gemspec under `bundle exec` | closed: `fix(lib): load what a gemspec requires before the program, as Bundler does` | developer |
| J20 | `Gem.path` | the person's `GEM_HOME` and `Gem.user_dir` missing from the app | B | developer |
| J21 | `Gem.dir` | the person's `GEM_HOME` against the runtime's gem folder | B | developer |
| J22–J23 | `gems`, `requireable` | rv-ruby's bootsnap and msgpack missing from the app | A | developer, rarely |
| J24 | `$LOADED_FEATURES`; Unix | Fledge's `rubygems/defaults/operating_system.rb` | B | probe |
| J25 | `$LOADED_FEATURES`; Windows | RubyInstaller's `ruby_installer/*`, `win32/dll_directory.so`, and `enc/*` missing from the app | narrowed: `fix: define RubyInstaller in a Windows app, as ruby.exe does`; `ruby_installer/runtime/*`, `win32/dll_directory.so`, and `enc/*` remain, and `RubyInstaller` is defined | developer |
| J26–J28 | the three encodings; no locale | `US-ASCII` against `UTF-8` | B | developer |

Counts: 15 entries A, 7 B, 1 C in part (J25), 5 closed (J11, J12, J13, J17, J19). The static libruby that `mkmf` links against is kept in every desktop runtime (`fix: keep the library mkmf links against in every desktop runtime`).

### J1–J6: the program's path (A)

The launcher hands Ruby the absolute path `APP/ENTRY` (`doc/contributors/design/launcher.md`, "Ruby's arguments"). Ruby names the script as it was given, so `ruby /abs/main.rb` gives the absolute path in all three. Measured, on this Mac:

```
$ ruby p0.rb                         # p [$0, __FILE__, $PROGRAM_NAME, __dir__]
["p0.rb", "p0.rb", "p0.rb", "/…/devgrp"]
$ ruby /…/devgrp/p0.rb
["/…/devgrp/p0.rb", "/…/devgrp/p0.rb", "/…/devgrp/p0.rb", "/…/devgrp"]
```

The app is the second line, run from wherever the person is. A relative path would need the person's current folder to be the app's, and changing it would be a worse difference (`Dir.pwd`). Nothing to close. One thing the probe cannot see: the launcher names the app folder by its real path (`launcher.md`, "The app folder in a macOS bundle"), so where a person reached the app through a link, `$0` is the real path where a typed `ruby /link/main.rb` keeps the link. No one types it, so it is still the location itself.

### J7–J10, J14–J15: where the bundle's gems are (A)

The reference installs the bundle into the person's `GEM_HOME`; the app installs it into Ruby's own gem folder, with `path.system` (`gems.md`, "Installing into the runtime's gem folder"). A developer who runs `bundle install` with no `GEM_HOME` installs into Ruby's own gem folder too, and then `bundle exec` gives the app's paths exactly: Bundler sets `GEM_HOME` to the bundle path and puts its bin folder on `PATH` either way. The difference is the reference's choice of install location, not Fledge's.

### J11–J13: the development and test groups (closed)

Closed by `feat(lib)!: ship the development and test groups, as bundle exec loads them`: the app sets up the groups `bundle exec` sets up under the developer's own settings (`gems.md`, "Groups"). What follows is the finding that led to it.

`gems.md`, "Groups": "with `development` and `test` always left out: a built app has no development gems, as Warbler's `bundle_without` has it." The reason is prior art (Warbler, Heroku's default `BUNDLE_WITHOUT`), and size. Neither is a rule of an operating system, and decision 20 says "Tiny filesize is not a priority; "my ruby code just works" _is_ a (high) priority."

What a developer meets: a program that requires a gem of its development group at run time, such as `debug`, `pry`, `dotenv`, or `rake` used as a library, works under `bundle exec` and fails in the app with a `LoadError` that names the gem, to the person. Measured, with a Gemfile whose only gem is rake in `group :development` and a `main.rb` of `require "rake"`:

```
$ bundle exec ruby main.rb
13.4.2
$ BUNDLE_WITHOUT=development bundle exec ruby main.rb
…/bundled_gems.rb:60:in 'Kernel.require': cannot load such file -- rake (LoadError)
```

(The second run's `ruby` resolved to mise's 4.0.9 through `PATH`; the behaviour is Bundler's and the same.) That is a Design precedence 1 harm caused by Fledge's choice, not prevented by it.

The fix: stop forcing `development` and `test` into `without` in `Fledge::Bundle#read_groups`, so the app sets up exactly what `bundle exec` sets up, still honouring the developer's own `BUNDLE_WITHOUT` and `.bundle/config`, as Bundler does. About 5 lines in `lib/`, plus the tests that pin today's behaviour, `gems.md` "Groups", ADR 005's and the former ADR 045, now the former ADR 086, now ADR 095's lines on groups, `examples/my_cool_app/Gemfile`'s comment, the README and `doc/differences_from_ruby.md` "Your gems", and J11–J13 removed. The cost is real and should be weighed: bigger apps, and a `fledge build` that now refuses a development gem with no build for the target (a test-only gem that compiles, say), which would never have run. A developer who wants today's behaviour sets `BUNDLE_WITHOUT` as for any deployment, which is exactly the configuration under which `bundle exec` gives the same `LoadError`. That turns J11–J13 from a difference into the developer's own configuration (A).

### J16: `$VERBOSE` under a person's `RUBYOPT` (B)

Design precedence 1 names it: "no influence from a Ruby the person happens to have (`RUBYLIB`, `RUBYOPT`, `GEM_HOME`, and the rest are hidden from Ruby's boot". A person's `RUBYOPT=-rsomething` would load code into the app; `-W0` is the harmless stand-in the probe uses. `ruby main.rb` with no `RUBYOPT` gives `false`, as the app does. The maintainer agreed to restore the variables into `ENV` afterwards (decision 11, "I think yes?"), which ADR 040 does, so only the boot is shielded. Nothing to close without breaking precedence 1.

### J17–J18: Bundler reads the app's `.bundle/config` (J17 closed, J18 A)

J17 is closed by `fix: set Bundler up from the environment, so nothing defines a hollow Psych`: the launcher hands Bundler the app's settings as `BUNDLE_` variables read from `.bundle/config` and deletes them after `bundler/setup`, and points `BUNDLE_APP_CONFIG` and `BUNDLE_USER_CONFIG` at a folder that holds nothing, so Bundler reads no settings file, loads no `rubygems/yaml_serializer`, and defines no hollow `Psych` (`launcher.md`, "The Bundler environment"). The text below says why the file stays in the app, and why J18 stands.

`LIBDIR/bundler/settings.rb`, line 831, requires `rubygems/yaml_serializer` when Bundler reads a configuration file; line 338 to 341, `use_system_gems?`, asks `Bundler.feature_flag` only when no setting says where the gems are. The app has a `.bundle/config`, the reference has none. `bundle exec` in the built app's folder, or in any project where the developer ran `bundle config set --local`, loads the same files. The `.bundle/config` itself is forced: without `BUNDLE_FROZEN`, `Definition#write_lock` touches `Gemfile.lock` on every setup even when nothing changed (`LIBDIR/bundler/definition.rb`, lines 425 to 428, `FileUtils.touch` when not frozen; `runtime.rb` line 37 calls `lock`), which fails in a folder the person cannot write, such as `/Applications` for a standard user or `C:\Program Files`, where the NSIS installer puts the app. Moving the settings into `BUNDLE_*` variables would show in `ENV`, a worse difference.

### J19: the gemspec's own requires (closed)

Closed by `fix(lib): load what a gemspec requires before the program, as Bundler does`: the shipped gemspec starts with a `require_relative` for each project file its evaluation loads (`gems.md`, "The app's .bundle/config and gemspecs"). What follows is the finding that led to it.

Under `bundle exec`, Bundler evaluates the project's gemspec at every start, in `TOPLEVEL_BINDING` (`LIBDIR/bundler.rb`, lines 642 to 660). `bundle gem`'s template, and `examples/my_cool_app/my_cool_app.gemspec` line 8, begin with `require_relative "lib/my_cool_app/version"`, so `MyCoolApp::VERSION` is defined, and `version.rb` loaded, before the program's first line. The app ships the gemspec evaluated at build time (`gems.md`, "The app's .bundle/config and gemspecs"), so neither is true there.

Not evaluating the developer's gemspec on the person's computer is right: the same gemspec runs `git ls-files` at line 25, and on a Mac without Xcode's command line tools `/usr/bin/git` is a shim that offers to install them, a precedence 1 harm (Apple's shim behaviour, not measured here). But the observable consequence is closable. A developer meets it with an `exe/` that handles `--version` with `MyCoolApp::VERSION` before `require "my_cool_app"`, to start fast: it works under `bundle exec` and raises `NameError` in the app.

The fix: when `fledge build` evaluates each of the project's gemspecs, record the files under the project's root that the evaluation added to `$LOADED_FEATURES` (it already evaluates them), and write them as `require_relative` lines, in order, at the top of the evaluated gemspec it ships. Bundler then evaluates that gemspec at boot as it does under `bundle exec`, and loads the same files in the same order from the same relative paths, with no git. About 15 to 25 lines in `Fledge::Bundle#app_files` (or wherever `spec.to_ruby` is written), a test, a sentence in `gems.md`, and J19 removed. A gemspec that requires a file which itself runs git would bring git back; the recording can be limited to files that define no more than constants, or simply documented.

### J20–J21: `Gem.path` and `Gem.dir` (B)

`runtime/rubygems/operating_system.rb` explains it: "Left alone, `Gem.default_path` puts `Gem.user_dir` … first whenever the person's home folder exists …, so a gem they installed with their own Ruby 4.1 would shadow a gem the app ships, json included." In an app with no Gemfile, RubyGems activates the newest version it finds on `Gem.path`, so a person's `gem install json` would replace the app's json: a person's Ruby changing how the app runs, which precedence 1 forbids by name ("the app's gems are the runtime's"). `Gem.dir` with no `GEM_HOME` is `Gem.default_dir` under `ruby main.rb` too, so the app's value is what a developer with no `GEM_HOME` sees.

### J22–J23: bootsnap and msgpack (A)

rv-ruby installs both; no standard Ruby 4.1 does (`gems/bundled_gems` at the v4_1_0_preview1 tag lists neither; `runtime/sources.yml`, lines 41 to 55). The musl reference, which is Ruby built from source, and RubyInstaller's both lack them, and the app matches those. So the difference is rv-ruby's from Ruby, not the app's. A developer on rv's Ruby who writes `require "msgpack"` with no Gemfile would meet it. Keeping them would cost nothing in code and match only rv-ruby, at the price of differing from every other Ruby, so A stands. Decision 20 ("prune only what no running Ruby code can observe") is about Ruby's own contents, which the app keeps.

### J24: Fledge's RubyGems defaults on macOS and Linux (B)

The file is the means of J20, through the hook RubyGems documents for whoever packages Ruby (`rubygems.rb`, lines 1464 to 1476, cited in the file's header), which Debian's Ruby and RubyInstaller use too. A Debian `ruby main.rb` loads such a file. Patching `rubygems/defaults.rb` instead would hide the trace but change a file of Ruby's own. Only the probe sees it.

### J25: RubyInstaller's start-up files on Windows (C, in part; narrowed)

Narrowed by `fix: define RubyInstaller in a Windows app, as ruby.exe does`: Fledge's `operating_system.rb` requires `ruby_installer/runtime` and calls nothing, so `RubyInstaller` is defined and mysql2 takes its `ruby.exe` branch. The files RubyInstaller's start-up loads beyond that stay missing. What follows is the finding that led to it.

Replacing RubyInstaller's `operating_system.rb` is forced. At 92a692c (`resources/files/operating_system.rb`) it writes and deletes `Gem.default_dir/writable_p` on every start; when that fails, as in `C:\Program Files`, it sets `ENV['GEM_HOME'] ||= Gem.user_dir`, an `ENV` change of its own; it creates `%ProgramData%\gemrc` when missing; and it calls `RubyInstaller::Runtime.enable_dll_search_paths`, which adds every folder of `RUBY_DLL_PATH` and then calls `msys2_installation.enable_dll_search_paths` (`lib/ruby_installer/build/singleton.rb`), so a person's MSYS2 DLLs can load into the app. All of it is precedence 1 harm in an app. That part is B.

What is closable is the side effect the entry also allows: in the app, `RubyInstaller` is not defined. Gems test for it. mysql2 0.5.6, `lib/mysql2.rb`, lines 7 to 30:

```ruby
  elsif defined?(RubyInstaller)
    # RubyInstaller-2.4+ native build doesn't need DLL preloading
  else
    # This will use default / system library paths
    'libmysql.dll'
  end

  if dll_path
    require 'fiddle'
    …
      abort "Failed to load libmysql.dll from #{dll_path}"
```

Under `ruby.exe` it skips the preload. In the app it takes the `else`: it requires fiddle, which a bundle that does not lock it leaves out (`gems.md`, "binding.irb and force_activate"), and otherwise loads `libmysql.dll` by bare name in a process whose launcher called `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` (`launcher.md`, "Windows"), and aborts with a message that names a DLL. pg 1.6.2, `lib/pg.rb`, lines 29 to 37, requires `ruby_installer/runtime` itself and is unaffected.

The fix: on Windows, Fledge's `operating_system.rb` requires `ruby_installer/runtime`, which the runtime keeps in `site_ruby` (`runtimes.md`, "What a runtime keeps"), and calls nothing. At 92a692c, `lib/ruby_installer/runtime.rb` only sets up autoloads and requires its singleton, whose methods are only defined (`build/singleton.rb`; check the runtime's own copy of `runtime/singleton.rb` before landing). Then `defined?(RubyInstaller)` and `RubyInstaller::Runtime.add_dll_directory` behave as under `ruby.exe`, the `ruby_installer/` part of J25 goes, and only `win32/dll_directory.so` and the encodings that RubyInstaller's start-up loads remain, which load on first use either way. About 3 lines, a parity fact (`defined?(RubyInstaller)`), and J25's first pattern removed. `runtimes.md`, "Fledge's RubyGems defaults", says "A runtime needs none of it", which is true of what the file does and not of the constant it defines.

### J26–J28: the locale with none set (B)

Measured, with mise's Ruby 4.1.0-preview1, in a folder named `Ünïcödé`, a `main.rb` of `puts File.join(__dir__, "café")`, run as a desktop starts an app, with no locale:

```
$ env -i ruby /…/Ünïcödé/main.rb
…/main.rb:3:in 'File.join': incompatible character encodings: US-ASCII and UTF-8 (Encoding::CompatibilityError)
```

That is an ordinary line of app code failing for a person whose folder name is not ASCII, before anything of Bundler's; the former ADR 041, now ADR 087 adds that Ruby's boot and Bundler's setup fail too under a prefix outside ASCII, which this audit did not measure, having no runtime built. A double-clicked macOS app gets no `LANG`. Python's PEP 538 is the prior art. The maintainer accepted it conditionally (2026-11-03): "I can buy that for now, but will easily be swayed by the first app dev who gets upset by the deviation." B, with that condition.

## The sections of `doc/differences_from_ruby.md`

| Section | Class | Note |
|---|---|---|
| Your program's path | A | J1–J6. |
| Your users' Ruby settings | B | J16, and ADR 040's unprobed consequence: a person cannot turn on `RUBY_YJIT_ENABLE`, `RUBY_MN_THREADS`, or `RUBY_GC_*` for an app. Precedence 1 covers that too (a person's `RUBY_THREAD_VM_STACK_SIZE` could break the app); a developer can still call `RubyVM::YJIT.enable` from code. No parity fact measures any `RUBY_*` tunable. |
| Your gems | B | `Gem.dir`, `Gem.path`, the frozen bundle, and the defaults file are B (J17–J18, J20–J21, J24). J11–J13 and J17 are closed. `Bundler.frozen_bundle?`, `Bundler.settings[:frozen]`, and `Bundler.settings[:without]` differ too, and no parity fact reads them. |
| The locale | B | J26–J28. |
| Windows' ANSI code page | B | ffi 1.17.4's `ext/ffi_c/DynamicLibrary.c`, lines 215 to 225, calls `LoadLibraryExA`, confirmed; an app that cannot start in `C:\Users\José\` is precedence 1 harm, and precedence 1 wins over 2. But no entry in `Parity::JUSTIFIED` covers it, because the parity check runs only console programs, where nothing differs: the windowed difference (`Encoding.locale_charmap` `"CP65001"`) is documented and never checked. |
| Restarts | **C** on Windows, A in part | Below. |
| C headers | closed | Below. |
| On a phone | out of scope | The phone audit's. |
| What a standard Ruby installs and the app does not | A and **C** | bootsnap and msgpack are A (J22–J23); RubyInstaller's start-up is C in part, narrowed (J25). |

### Restarts on Windows (C, developer)

ADR 026: "On Windows this is a limit, not a choice. Fledge keeps RubyInstaller's tree whole and builds no `ruby.exe` of its own (ADR 038), and Windows has no `exec` that keeps the process". Only the second half is a limit. Ruby's own `exec` on Windows starts the program, waits, and exits with its status (`launcher.md`, "bin/ruby and restarts", citing `process.c` line 1639 and `win32/win32.c` lines 1184 to 1200), so under `ruby.exe` too a restart gets a new PID, and under `rubyw.exe` `RbConfig.ruby` is `ruby.exe` and opens a console. Those parts are A. The rest is ADR 038's choice: a restart through `RbConfig.ruby` boots with the person's `RUBYOPT`, `RUBYLIB`, and `GEM_HOME`, with no Bundler setup, and under the system's ANSI code page, so the ffi failure the launcher's manifest prevents comes back in the restarted app.

A developer meets it with any self-restarting app (after an update, after a settings change) on Windows, and the only fix today is a branch per operating system, which decision 23 ("Would this require app devs to have a bunch of `if`s …") hoped to spare them.

The fix: build a `ruby.exe` (and `rubyw.exe`) of Fledge's with llvm-mingw, which already builds the launchers, and put it in place of RubyInstaller's inside the same tree, so the tree's shape stays ADR 038's. It is Ruby's `main.c` against the DLL, as `bin/ruby` is on Unix, plus a Windows `relaunch`: when `argv[1]` names the app's entry by file identity (`GetFileInformationByHandle`, the volume serial and file index, as `relaunch.c` compares device and inode), `CreateProcessW` the app's launcher with the rest of the command line, wait, and exit with its status, which is what Ruby's own `exec` does there. It reads `fledge.cfg` with `config.c` and carries the `activeCodePage` manifest. About 150 to 250 lines of C, the build steps in `RuntimeBuilder::Windows`, the license audit's record of the replaced programs, a Windows restart check in Delivery, and ADR 026's and ADR 038's lines on Windows. It would also give every child Ruby the app starts the launcher's code page, closing the last paragraph of "Windows' ANSI code page".

### C headers without libraries (closed)

Closed by `fix: keep the library mkmf links against in every desktop runtime`: every desktop runtime keeps the static libruby, or the import library of Ruby's DLL (`runtimes.md`, "What a runtime keeps"). What follows is the finding that led to it.

the former ADR 039, now ADR 085 prunes "static and import libraries" as what "no running code reads". `runtimes.md`, "The build-only companion", says otherwise in its own words: "mkmf links the test programs of `have_func` and the rest against `LIBRUBYARG_STATIC`, so an `extconf.rb` that checks for a function (nokogiri's) fails without it" (`LIBDIR/mkmf.rb`, line 552, `link_config`'s `$(LIBRUBYARG)`, and lines 2790 to 2806). An app's own running code that calls `have_func` or `try_link`, on a computer with a compiler, reads them. It needs a compiler a person rarely has, so it is the least likely entry here to be met. The fix ships the companion's files in the runtime: no new code, the license audit's and SBOM's entries (Ruby's license, and Rust's beside a static libruby), and some megabytes on macOS and Linux; Windows' import library is small. Decision 20 says size does not count against "my ruby code just works". the former ADR 039, now ADR 085's "Decision Outcome" line on pruning would change with it.

## The closable entries, ranked

Ranked by how soon an app developer would meet each in a real app:

1. **Development and test groups left out (J11–J13).** Closed. Any program that requires a development gem at run time (`debug`, `pry`, `dotenv`, rake as a library) fails in the app with a `LoadError` naming the gem, and works under `bundle exec`. About 5 lines in `Fledge::Bundle#read_groups`, plus tests and docs; the cost is bigger apps and builds refused for development gems with no build for the target.
2. **`RubyInstaller` undefined on Windows (J25, in part).** Closed. A gem that tests `defined?(RubyInstaller)`, such as mysql2 0.5.6, takes its other branch and aborts. About 3 lines in `runtime/rubygems/operating_system.rb`, a new parity fact, and one pattern of J25 removed.
3. **Restart through `RbConfig.ruby` on Windows.** A self-restarting app boots with the person's settings, without Bundler, and in the system's code page. About 150 to 250 lines of C for a Fledge `ruby.exe` and `rubyw.exe`, the build, a Delivery check, and ADR 026's and 038's Windows lines.
4. **The gemspec's own requires (J19).** Closed. `MyCoolApp::VERSION` is defined before the program runs under `bundle exec`, and not in the app. About 15 to 25 lines in `fledge build`'s gemspec writer, and J19 removed.
5. **Static and import libraries (C headers).** Closed. `have_func` and `try_link` fail in the app's own running code. No new code; more megabytes, and the license audit's entries.

## Gaps the probe does not see

None of these is in `Parity::JUSTIFIED`, so none fails the check today:

- `defined?(RubyInstaller)` on Windows (closable, rank 2 above).
- `Bundler.frozen_bundle?` and `Bundler.settings` values, which the app's `.bundle/config` sets.
- `Encoding.locale_charmap` in a windowed Windows app, since the parity check runs no windowed program.
- Every `RUBY_*` tunable Ruby reads at boot.
- `Dir.pwd`, which the check sets to the app's folder for the app and the probe's copy for the reference, so a launcher that changed the current folder would not show.

## Lines this audit finds untrue

For the orchestrator, who writes every ADR correction:

- ADR 026, "Decision Outcome": "On Windows this is a limit, not a choice." Only the new PID, and `ruby.exe`'s console under a windowed app, are limits; the person's settings, the missing Bundler, and the code page follow from ADR 038's choice.
- the former ADR 039, now ADR 085, "Decision Outcome": static and import libraries are listed under "what no running code reads"; `runtimes.md`, "The build-only companion", shows that mkmf's checks read them.
- `doc/contributors/design/runtimes.md`, "Fledge's RubyGems defaults": "A runtime needs none of it" holds for what RubyInstaller's file does, not for the `RubyInstaller` constant it defines, which gems read.
- `doc/contributors/design/parity.md` and `doc/differences_from_ruby.md`, "Windows' ANSI code page": the difference is documented but no parity run measures it.
