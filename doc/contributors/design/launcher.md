<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Launcher and bin/ruby

This document describes the program at the top of every desktop app, the launcher, and the runtime's `bin/ruby` on macOS and Linux: how each starts, what each reads, what it changes in the environment and in what order, what it prints, and how it exits. ADR 001 decides that an app is a launcher that embeds CRuby; and ADR 081 that it adds nothing between Ruby and the program. Each section below says why the part it describes is as it is. Why there are console and windowed launchers, and several programs in one folder, is in `doc/contributors/design/desktop-apps.md`, "Windows" and "Several programs". Line numbers below are at Ruby 4.1.0-preview1, as the launcher's comments cite them, except where a sentence says otherwise.

## Source files

Everything is in `runtime/launcher/`. `launcher.h` declares what the files share, including the exit statuses.

| File | Holds | Linked into |
|---|---|---|
| `unix.c` | the macOS and Linux launcher's `main` and its steps | the launcher |
| `darwin.c`, `linux.c` | `fledge_executable_path`; on Linux also `fledge_find_system_libraries` | the launcher and `bin/ruby` |
| `windows.c` | the whole Windows launcher | `launcher.exe`, `launcherw.exe` |
| `scrub.c` | which variables are hidden from Ruby's boot | every launcher |
| `config.c` | the `fledge.cfg` reader | every launcher, `bin/ruby`, the phone runtime |
| `bundler.c` | the Ruby that loads the app's Bundler, the Ruby that composes `bundle exec`'s environment, and the Ruby that puts the app's Ruby first on `PATH` | every launcher; the phone runtime, for the first |
| `locale.c` | `fledge_coerce_locale` | the Unix launcher, `bin/ruby`, the phone runtime |
| `ruby_main.c` | `bin/ruby`: Ruby's `main.c`, with two calls of Fledge's | `bin/ruby` |
| `relaunch.c` | how `bin/ruby` hands the app's program to its launcher | `bin/ruby` |
| `windows.manifest`, `windows.rc` | the Windows launcher's embedded manifest | every Windows launcher |

`tasks/runtime_builder/unix.rb` and `windows.rb` compile them; `doc/contributors/design/runtimes.md` covers the toolchains. The phone runtime (`runtime/mobile/fledge_ruby.c`) shares `config.c`, `locale.c`, and `bundler.c` and does the launcher's work of its own; `doc/contributors/design/phone-runtimes.md` covers it.

## The boot sequence

On macOS and Linux, `main` in `unix.c` follows Ruby's `main.c` (lines 37 to 63) with the launcher's steps first:

1. `find_root`: find the launcher's own file and folder (see "Finding itself"); refuse a folder named `bin` (in any case) or `lib`.
2. `read_config`: read `ROOT/fledge.cfg` (see "fledge.cfg").
3. On Linux, `find_system_libraries` (see "System libraries on Linux").
4. `find_app_folder`: name `ROOT/app` by its real path (see "The app folder in a macOS bundle").
5. `scrub_environment`: set aside and remove the person's Ruby settings.
6. `fledge_coerce_locale` (see "The locale").
7. `ruby_sysinit`, then `build_ruby_arguments` (see "Ruby's arguments").
8. `ruby_start_main(run_ruby, ...)`. `run_ruby` runs `RUBY_INIT_STACK`, `ruby_init`, and `ruby_options`. When the node is executable, it runs, on macOS, `name_load_path_by_real_paths` (see "The app folder in a macOS bundle"), then `pin_rubygems`; `put_ruby_on_path` (see "The app's Ruby on PATH"); for an app with a Gemfile, `setup_bundler`, `pin_rubygems` again, and `bundle_environment`. Then `restore_environment`, and `ruby_run_node`.

The Windows sequence is in "Windows".

The app's program runs on the process's main thread, where macOS wants windows and events: `ruby_start_main` runs its callback on the thread that called it.

## Finding itself

| System | How | Then |
|---|---|---|
| macOS | `_NSGetExecutablePath` | `realpath` |
| Linux | `/proc/self/exe` | `realpath` |
| Windows | `GetModuleFileNameW`, its buffer doubled until the path fits, up to 65,536 characters | when the file is a reparse point, opens it and names the target with `GetFinalPathNameByHandleW` |

Each follows a symbolic link someone or a package manager put on `PATH` to the file it names, so the launcher finds `fledge.cfg` and Ruby beside the real file. On Windows `GetModuleFileNameW` returns the path the program was started by, so a program winget links into its `Links` folder would otherwise look there. Only the file itself is resolved: a folder reached through a junction, as Scoop's `current` is, or a `subst` or mapped drive keeps the path the person used, and the folder beside the program is the app's either way.

The launcher's file name, less `.exe` on Windows, is NAME in its messages and names its section of `fledge.cfg`.

On macOS and Linux, `--enable-load-relative` makes Ruby derive its prefix from the file that holds libruby, which is the launcher, so Ruby looks for `ROOT/lib/ruby/` (`ruby.c`, lines 593 to 743). When that folder is named `bin` in any case, or `lib`, `ruby.c` takes its parent as the prefix instead (lines 712 to 722), so the launcher refuses to run there rather than use a standard library from somewhere else. `argv[0]` stays the pointer `ruby_sysinit` recorded: on Linux `ruby.c` recognizes the program that holds libruby by comparing `dladdr`'s file name with it (line 649), and only then reads `/proc/self/exe`, so a launcher found on `PATH` by its bare name still finds its root.

On Linux the launcher loads libxcrypt from `ROOT/lib` through a `DT_RPATH` of `$ORIGIN/lib`, which is searched before `LD_LIBRARY_PATH`, so the computer's libraries cannot stand in for it (`doc/contributors/design/runtimes.md`).

## Ruby's arguments

Ruby sees `argv[0]`, then `--disable=rubyopt`, `--`, the absolute path `APP/ENTRY`, and every argument the person passed, where APP is the app folder by its real path and ENTRY is `fledge.cfg`'s `entry`. On Windows ENTRY's `/` become `\`, and the path is UTF-8. A missing or non-regular ENTRY exits 66.

Nothing else, because each option of Fledge's own would show in the program. There is no `-I ROOT/app`, which would let `require "foo"` find the app's `foo.rb` where `ruby main.rb` does not, and leave a `$LOAD_PATH` entry no Ruby developer expects: an app loads its own files with `require_relative`, as under `ruby`. There is no `--yjit`, which makes `RUBY_DESCRIPTION` read `+YJIT`: an app that wants YJIT enables it, as Rails does, with `RubyVM::YJIT.enable`. There is no `-r` boot file, which would join `$LOADED_FEATURES`. `--disable=rubyopt` changes nothing an app sees, since `RUBYOPT` is hidden from Ruby's boot anyway ("Hiding and restoring the person's Ruby settings"); it guards that boot twice.

## Signals and the console

Ruby installs handlers for SIGINT and SIGHUP (`signal.c`, `install_sighandler`), and re-raises the signal with its default action after cleanup (`eval.c`, `rb_ec_cleanup`, and `signal.c`, `ruby_default_signal`, at Ruby 4.1.0-preview1). The launcher installs no handler and ignores no signal, so Ctrl-C raises `Interrupt` in the main thread, runs `ensure` clauses and `at_exit` hooks, and ends the app by SIGINT (130 to a shell on macOS and Linux, exit code 3 on Windows); a closed terminal raises `SignalException` for SIGHUP (129). A built app started in the background of a shell script ignores Ctrl-C, as `ruby` does there.

On Windows, the C runtime UCRT turns CTRL_C_EVENT into SIGINT and maps no other console event to a signal, and neither Ruby nor the launcher installs a console control handler. Closing a console window ends the app at once, with STATUS_CONTROL_C_EXIT, as it ends `ruby.exe`.

## Hiding and restoring the person's Ruby settings

Two rules pull apart here. Nothing of a Ruby the person happens to have, such as a `RUBYOPT`, a `GEM_HOME`, or a `BUNDLER_SETUP` that `rubygems.rb` requires as it loads, may change how the app starts (AGENTS.md, Design precedence 1), but the app's `ENV`, and every program it starts, should be what `ruby main.rb` gives (Design precedence 2). Removing the variables for good meets the first and breaks the second, so the launcher hides them from Ruby's boot and puts them back before the program runs, as the maintainer agreed (`decisions.md`, 2026-10-26, later, reply 11). Ruby's `gem_prelude.rb` does the same with `BUNDLER_SETUP` while RubyGems loads (lines 11 and 21). Doing it in C, between `ruby_options` and `ruby_run_node`, adds nothing to `$LOADED_FEATURES`, as a `-r` boot file would.

`scrub.c` names the prefixes: `RUBY`, `GEM_`, `GEMRC`, `BUNDLE_`, `BUNDLER_`, and `RI_FORCE_PATH_FOR_DLL`, with a comment of which variable each covers and where Ruby, RubyGems, Bundler, and RubyInstaller read it. Prefixes rather than names hide a variable a later Ruby adds under them too; a variable a new Ruby reads at boot outside them is what that comment is checked against at each Ruby. Variables outside them, such as `SSL_CERT_FILE`, `HOME`, and the `XDG_` folders, describe the computer, not the person's Ruby, and stay. `PATH` is one of these and is never hidden: the person's entries all stay, in their order, and the launcher puts one folder before them once Ruby has booted, the app's Ruby's, as a developer's shell has the Ruby that runs a program before the rest (see "The app's Ruby on PATH"). It changes which program a name finds only for a name that folder holds, `ruby` and the gems' commands, which must be the app's for the person's Ruby not to reach it, and nothing Ruby boots with.

- **On macOS and Linux**, `scrub_environment` copies each matching `NAME=value` and `unsetenv`s it, scanning `environ` again after each removal. An entry without `=` is no variable to `getenv` or to Ruby's `ENV` (`hash.c`, `env_each_pair`), and `unsetenv` cannot remove it, so it stays, as under `ruby`.
- **On Windows**, names are compared ignoring ASCII case. The launcher collects every match from `GetEnvironmentStringsW` first, skipping the `=C:` entries that hold each drive's current folder, then removes each from both copies of the environment: the C runtime's (`_wputenv_s`), which Ruby's `getenv` reads until Ruby has its own, and the process's (`SetEnvironmentVariableW`), which Ruby reads afterwards and children inherit. It shares UCRT with RubyInstaller's Ruby, so the C runtime's copy is the one Ruby reads.

After `ruby_options` returns, Ruby has booted, RubyGems has loaded, and the program is compiled but not run. The order is then fixed:

1. `pin_rubygems` evaluates `Gem.paths if defined?(Gem.paths)`. `Gem.paths` reads `GEM_HOME`, `GEM_PATH`, and `GEM_SPEC_CACHE` once and keeps the answer (`rubygems.rb` and `rubygems/path_support.rb`), so the gem paths are fixed while the person's are hidden. Fledge's `rubygems/defaults/operating_system.rb` makes the default path the runtime's gem folder alone.
2. `put_ruby_on_path` puts the bin folder of the app's Ruby before the person's `PATH` (see "The app's Ruby on PATH").
3. For an app with a Gemfile, Bundler sets up the app's gems, and `pin_rubygems` runs again (see "The Bundler environment").
4. The variables come back. For an app without a Gemfile, `restore_environment` puts each back with its own value (`setenv`; on Windows `_wputenv_s` and `SetEnvironmentVariableW`), skipping any that is set again by then. For an app with one, `bundle_environment` does it beneath Bundler's settings, and `restore_environment` then has nothing left to do.
5. `ruby_run_node` runs the program.

A failure in these steps exits 70: "could not start RubyGems", "could not clear the environment", "could not restore NAME".

Each step that runs Ruby uses `rb_eval_string_protect`, so the launcher adds nothing to `$LOADED_FEATURES` or `$LOAD_PATH` and defines no global or constant.

Two differences from `ruby main.rb` remain, which `Parity::JUSTIFIED` and `doc/differences_from_ruby.md` list: `$VERBOSE`, which a person's `RUBYOPT=-W0` makes `nil` under `ruby` and leaves `false` in the app, and `Gem.path` and `Gem.dir`, which never hold the person's `GEM_HOME` or `Gem.user_dir`. What Ruby reads only at boot, such as `RUBY_YJIT_ENABLE`, a person cannot turn on for an app. What Ruby and RubyGems read later reaches the app as under `ruby main.rb`, such as `GEM_REQUIREMENT_NAME` and `GEMRC`, and so do the person's settings in every Ruby the app starts; an app that wants its children kept apart from them clears them itself.

## The Bundler environment

A gem-shaped program runs as `bundle exec exe/my_cool_app`, with the project's `lib` and every locked gem on the load path, and says `require "my_cool_app"`. Many programs also require `bundler/setup` themselves, call `Bundler.require`, read `Gem.loaded_specs`, or start a person's own tools inside `Bundler.with_unbundled_env`. For that code to stay as it is (decisions 9 and 20), the launcher sets up the real Bundler as `bundle exec` does. Bundler's `--standalone`, which writes a `bundler/setup.rb` of load paths that needs no Bundler at run time, was weighed and not taken: a program that requires `bundler/setup` then loads the real Bundler anyway, which looks for a Gemfile from the person's current folder, and `Gem.loaded_specs` knows none of the gems. An app without a Gemfile runs without Bundler.

For an app whose `fledge.cfg` names a `gemfile`, `setup_bundler` runs while the person's settings are still hidden:

1. It requires Bundler by its path, so that `Bundler.original_env` records the environment Ruby booted with, its `PATH` beginning with the app's Ruby. Required by name, RubyGems would first activate the bundler gem, which `bundle exec` does not. Which Bundler, `fledge_bundler_code` in `bundler.c` writes: the runtime's own, `File.join(RbConfig::CONFIG['rubylibdir'], 'bundler')`, or, when `fledge.cfg` names a `bundler` version, the gem `fledge build` installed for it (`doc/contributors/design/gems.md`, "The lockfile's Bundler"). For that one, the launcher first puts the gem's lib, `File.join(Gem.dir, 'gems', 'bundler-VERSION', 'lib')`, at the front of `$LOAD_PATH`, where `bundle exec`'s `RUBYLIB` puts it for the program it runs (`bundler/shared_helpers.rb`, `set_rubylib`), and requires `bundler` from there. `Gem.dir` is the runtime's gem folder, since RubyGems' paths are fixed before.
2. It sets `BUNDLE_GEMFILE` to `APP/GEMFILE`, reads the `BUNDLE_` lines of `APP/.bundle/config`, the file `fledge build` wrote (beside the Gemfile on a phone), into `ENV`, and points `BUNDLE_APP_CONFIG` and `BUNDLE_USER_CONFIG` at `APP/.bundle/none`, which holds nothing. Bundler reads no settings file, and the person's `~/.bundle/config` is never read. Bundler reads a settings file with RubyGems' YAML serializer, which defines a hollow `Psych` when Psych is not loaded, so reading the file would make `defined?(Psych)` true where it is false under `bundle exec`. Removing that `Psych` after the setup would not do: the serializer would stay loaded, and its error paths name `Psych`.
3. It requires `bundler/setup` by its path, from the same Bundler, as `bundle exec`'s `RUBYOPT=-r.../bundler/setup` does (`bundler/shared_helpers.rb`, `set_rubyopt`). On failure it prints the exception's message and exits 70 ("could not set up this app's gems"); `bundler/setup` prints its own message and exits when standard output is a terminal.
4. It deletes `BUNDLE_FROZEN` from `ENV` and has Bundler make its settings again (`Bundler.reset_settings_and_root!`, then `Bundler.settings`), while `BUNDLE_APP_CONFIG` and `BUNDLE_USER_CONFIG` still name nothing, so the bundle is frozen only while Bundler sets it up: frozen, Bundler takes the lockfile's resolution as it is, refuses a Gemfile that moved past it, and never touches the lockfile. The program then finds `Bundler.frozen_bundle?` and `Bundler.settings[:frozen]` nil, as under `bundle exec` in a developer's project, with the app's other settings kept. `Bundler.setup` and `Bundler.require` return the setup already done (`bundler.rb`, line 157, at Bundler 4.0.20), and whatever makes the settings again, as `Bundler.reset!` and `Gem::BUNDLED_GEMS.force_activate` do, reads the app's `.bundle/config`, frozen. Keeping the bundle frozen once the setup ends would be a difference from `bundle exec` with nothing to gain. `Bundler.settings.temporary(frozen: true)` around the setup would not do: the setup makes the settings again itself whenever `BUNDLE_GEMFILE` is set (`configure_custom_gemfile`, lines 590 to 597).
5. It deletes every variable step 2 put in `ENV`, so the program's `ENV` is what it was. The file stays in the app for a Ruby the app starts with `bundler/setup`, which reads it as before.

`bundle_environment` then evaluates the Ruby that `bundler.c` writes, with the set-aside variables inside it as hexadecimal, so the launcher needs no Ruby function but `rb_eval_string_protect`. The code, run once:

1. decodes the set-aside variables, in the locale's encoding (UTF-8 on Windows, where Ruby's `ENV` is UTF-8);
2. keeps `bundled`, the `ENV` the protected setup left, and `booted`, a copy of `Bundler::ORIGINAL_ENV`;
3. makes a `Bundler::EnvironmentPreserver` over `booted` merged with the set-aside variables, and replaces `Bundler::ORIGINAL_ENV` with its `restore`, so that a person who started the app from inside a bundle gets their environment from before it, as a Bundler started under `bundle exec` does;
4. replaces `ENV` with the preserver's `backup`, whose `BUNDLER_ORIG_*` record the person's values;
5. puts back `BUNDLE_GEMFILE` and `BUNDLE_LOCKFILE` from `bundled`;
6. calls `Bundler::SharedHelpers.set_bundle_environment`, which composes `PATH`, `RUBYOPT`, and `RUBYLIB` over the person's values as `bundle exec` does, with the bundle's bin folder first on `PATH` and `-r.../bundler/setup` before the person's `RUBYOPT`;
7. puts back `GEM_HOME` and `GEM_PATH` from `bundled`, which name the runtime's gem folder;
8. sets up `MANPATH` as Bundler does, when Bundler had changed it;
9. on Windows, gives each set-aside variable but `BUNDLE_GEMFILE` and `BUNDLE_LOCKFILE` the spelling the person gave its name, and makes `Bundler::ORIGINAL_ENV` from the composed `ENV`, as the program's Bundler under `bundle exec` does (see "Bundler's variables spelled otherwise").

So `ENV` is `bundle exec`'s, and `Bundler.original_env`, `with_original_env`, `unbundled_env`, and `with_unbundled_env` give the person's own environment. Nothing here changes which gems load: `Gem.paths` is fixed, Bundler's `Settings` read `ENV` once when created, and Bundler's memoized `bundle_path` names the runtime's gems. A failure exits 70, "could not set up this app's environment". Reimplementing Bundler's composition in C would mean guessing at Bundler's rules, and restoring the person's environment before Bundler loads would expose its setup to their values.

What this costs: the app carries Bundler's environment, so a Ruby it starts runs in the app's bundle, with `GEM_HOME` naming the runtime's gem folder, as under `bundle exec`; and the setup leans on Bundler's internals, `EnvironmentPreserver` and `SharedHelpers.set_bundle_environment`, which a new Bundler may change, and which the parity check's gem-shaped run would notice (`doc/contributors/design/parity.md`, "The gem-shaped run"). A program that calls `Bundler.reset!` finds the bundle frozen again, and an explicit `Bundler.definition.lock` tries to write the lockfile, as under `bundle exec`, and raises `Bundler::PermissionError` in a folder the person cannot write.

The app's `.bundle/config`, the evaluated gemspecs, and Fledge's `force_activate` wrap are `fledge build`'s and the RubyGems defaults' work: `doc/contributors/design/gems.md`.

## The app's Ruby on PATH

A program runs a gem's command by its name, `system("rake")`, backquotes, `Open3`, `ruby -S rake`, or a child Ruby that does the same, and runs Ruby itself by its name, `system("ruby", "worker.rb")`. A developer runs `ruby main.rb`, or `bundle exec`, from a shell whose `PATH` found that `ruby`, in its bin folder, where `gem install` writes the commands of its gems; a version manager or RubyInstaller's installer puts it there. `bundle exec` then puts the bundle's bin folder before it (`Bundler::SharedHelpers#set_path`, `bundler/shared_helpers.rb`, lines 355 to 360, at Bundler 4.0.20), and `bundle install` writes the bundle's commands into `Bundler.system_bindir`, which is `Gem.bindir` (`bundler/source/rubygems.rb`, line 594; `bundler.rb`, lines 456 to 463), with `env_shebang`. A command that finds no `ruby` beside itself runs the `ruby` `PATH` finds (`Gem::Installer#bash_prolog_script` and `#windows_stub_script`, `rubygems/installer.rb`, lines 802 to 830 and 1039 to 1054, at Ruby 4.1.0-preview1). So under either, `system("rake")` runs the Ruby's rake, or the bundle's, under the program's own Ruby.

The person who runs an app has no Ruby on `PATH`, or a Ruby of their own, which would then run in the app's place: the person's Ruby reaching the app (AGENTS.md, Design precedence 1). Bundler's own entry in the app names `lib/ruby/gems/API/bin`, which holds nothing: the gems' commands are in the runtime's `bin/` (`doc/contributors/design/gems.md`, "Gem executables"), since `Gem.bindir` of RubyGems' default folder is Ruby's own bin folder (`rubygems.rb`, lines 334 to 338). So the launcher puts `RbConfig::CONFIG["bindir"]`, the folder that holds the app's `ruby` and its gems' commands, first on `PATH`, unless it is first already, as in a Ruby the app restarts (`fledge_ruby_on_path_code` in `bundler.c`). `put_ruby_on_path` evaluates it for every app once RubyGems' paths are fixed, before Bundler loads:

- **An app without a Gemfile:** `ENV["PATH"]` is the person's, with that folder before it, as a developer's shell has it for `ruby main.rb`.
- **An app with a Gemfile:** Bundler records that `PATH` as the one it started from, `BUNDLER_ORIG_PATH` and `Bundler.original_env`, and composes over it, so `ENV["PATH"]` is the bundle's bin folder, the app's Ruby's, then the person's, and Bundler's `uniq` keeps a restart's the same. `Bundler.original_env`, `unbundled_env`, and every program the app starts inside `with_original_env` or `with_unbundled_env` find the app's Ruby first, as under `bundle exec` they find the developer's, the Ruby that runs the program: `Bundler.with_unbundled_env { system("ruby", "x.rb") }` and `with_original_env { system("gem", "list") }` work in the app as there, and find no Ruby the person happens to have.

Keeping the folder out of what Bundler records, so that a person's own tool started there, such as a project's `bin/rails`, would find the person's Ruby, was tried and not taken: it made six facts of the parity check's gem-shaped run differ from `bundle exec`, a difference that could be closed, and let those calls find nothing, or the person's Ruby (AGENTS.md, Design precedence 1). A developer's own tools run under the Ruby on their `PATH`, the one running the program, without Fledge too.

On Windows the folder is `ROOT/ruby/bin`, with `/` between folders as `RbConfig` and Bundler's own entry write it, and Ruby's `ENV` write keeps the name the variable has, so a `PATH` Windows spells `Path` stays `Path`. Its `.bat` commands run the `ruby.exe` beside them, Fledge's, which runs a script as plain Ruby (see "bin/ruby and restarts"). Loading DLLs does not change: the launcher and the runtime's `ruby.exe` search System32 and Ruby's own folders, never `PATH`.

The phone runtimes do none of this. iOS lets no app run a program. The Android runtime has a `ruby` program, but no gems' commands, and a command written as a script in the app's files is one Android 10 forbids an app to run (`doc/contributors/design/phone-runtimes.md`, "The ruby program on Android").

What this costs: `ENV["PATH"]`, and the `PATH` Bundler records, name a folder of the app's, as a developer's names their Ruby's, and a program the app starts that runs `ruby` or a gem's command by name, a shell script among them, finds the app's. The parity check shows each: its references run with the reference Ruby's bin folder first on `PATH`, as a developer has it, and its probe runs a gem's command each way above (`parity.md`, "The environments" and "The probe"). Reversal: drop `fledge_ruby_on_path_code` and `put_ruby_on_path`, the probe's `gem commands`, and `Parity#developer`, and say in `doc/differences_from_ruby.md` that a gem's command is not found by name.

## fledge.cfg

`fledge build` writes `fledge.cfg` beside the launcher (`Fledge::Assembly.launch_config`). The launcher is the same program for every app, and on macOS a signed one, so nothing about one app is written into it; instead it reads a small text file beside itself, as Python's interpreter reads the `pyvenv.cfg` beside it (PEP 405). In a macOS bundle `Contents/MacOS/fledge.cfg` is a link to `Contents/Resources/fledge.cfg`.

**Format.** UTF-8 text, shorter than 65,536 bytes, with no NUL. Each line is `key = value`; spaces and tabs around key and value, and a trailing carriage return, are trimmed. Blank lines and lines beginning with `#` say nothing. A line `[NAME]` heads a section. The first line is a comment:

```
# Written by fledge build VERSION for PLATFORM: what this app's program runs.
```

ending `what this app's programs run.` for an app of several programs. A phone project's `fledge.cfg` (`Fledge::MobileProject`) names no version or platform: `# Written by fledge build: ...`. `fledge build --from` reads VERSION and PLATFORM from it (`Fledge::BuiltApp::HEADER`); nothing reads the words after the colon.

**Keys.**

| Key | Value | Where |
|---|---|---|
| `entry` | the program to run, relative to the app folder, `/` between folders, with no empty, `.`, or `..` part, no `\`, no `:` | required: at the top, or in each section |
| `gemfile` | the project's Gemfile, as a path like `entry` | at the top only |
| `bundler` | the version of the Bundler that sets up the Gemfile, when it is not the runtime's own: 1 to 32 letters, digits, and dots | at the top only, after `gemfile` |
| `identifier` | 1 to 128 letters, digits, hyphens, and dots | at the top, or in a section |
| `system_libraries` | file names of letters, digits, and `. _ + -`, between single spaces | at the top only; the Linux launcher reads it |

**Sections.** An app of one program has no section. An app of several gives each program a section headed by its name, holding only `entry` and `identifier`, after the shared keys. Each launcher copy reads the section whose name is its own file name, less `.exe` on Windows, ignoring case: ASCII case on macOS and Linux, `CompareStringOrdinal` on Windows, as their file systems compare names. Keys of other sections are checked but not kept.

**Refusals.** `fledge build` and the runtime come from the same Fledge, so anything else means the app is damaged: an unknown key, a line that is not `key = value`, a heading that is not `[NAME]`, a path that leaves the app folder, an identifier or library list with another character, a Bundler version with another character, a key twice, `gemfile`, `bundler`, or `system_libraries` inside a section, `entry` or `identifier` above the first section, no `entry`, text that is not UTF-8 on Windows. Each exits 70 with "this app is damaged: PATH PROBLEM". A missing file, and a file with sections and none for this launcher, exit 66.

## Messages and exit statuses

The launcher prints `NAME: message` to standard error and exits. On Windows `show` writes UTF-16 with `WriteConsoleW` to a console, and UTF-8 to a file or pipe; the windowed launcher, when it has no standard error, shows the message in a `MessageBoxW` titled with the program's name, with an error icon.

| Status | When |
|---|---|
| 66 (`EX_NOINPUT`) | `fledge.cfg` is missing |
| 66 | the program `entry` names is missing or not a file |
| 66 | `fledge.cfg` has sections and none for this launcher |
| 72 (`EX_OSFILE`) | Linux: a library `system_libraries` lists will not load |
| 70 (`EX_SOFTWARE`) | the launcher is in a folder named `bin` or `lib` |
| 70 | `fledge.cfg` is damaged or unreadable |
| 70 | Windows: Ruby's DLL, or a DLL it needs, is missing |
| 70 | Windows: Ruby's DLL will not load, or lacks a function |
| 70 | Bundler cannot start or set up the app's gems |
| 70 | anything else before the program runs |

The messages follow Ruby's `ruby: message` form and name the app, never Ruby: for example `NAME: this app is incomplete: PATH is missing` for a missing program, and `NAME: this app needs LIB, which this computer does not have (REASON). Install it from your Linux distribution's packages, then run the app again` for status 72. Their exact wording is the launcher's C source (`runtime/launcher/`), which `test/integration/built_app_test.rb` and Delivery read back; this table lists the statuses.

The statuses are sysexits(3)'s, from FreeBSD, which macOS and glibc ship, and `launcher.h` defines them once for every platform: `EX_NOINPUT` (66), "An input file (not a system file) did not exist or was not readable"; `EX_OSFILE` (72), "Some system file ... does not exist, cannot be opened, or has some sort of error"; and `EX_SOFTWARE` (70), "An internal software error has been detected". A launcher cannot reuse Ruby's own statuses, since the app's failures already exit with whatever the app chooses, so a script tells a broken app from the app's own failure by status. An app that exits 66, 70, or 72 for reasons of its own looks broken by status alone, and only the message tells them apart. The maintainer left such conventions to the agents, to follow the standards (`decisions.md`, 2026-10-26, decision 16).

Once the program runs, the status is the program's own. `bin/ruby`, which is Ruby's program, says `ruby: could not run LAUNCHER: REASON` and exits 70 when it finds the app's launcher and cannot start it.

## The locale

Ruby's `main.c` sets `LC_CTYPE` from the environment (`setlocale(LC_CTYPE, "")`, line 58), and that locale decides `Encoding.default_external`, `Encoding.find("locale")`, and `Encoding.find("filesystem")`. A desktop, a service manager, `env -i`, and a phone start an app with no locale: Launch Services gives a macOS app no `LANG` or `LC_*`, and a phone gives none. In that C locale Ruby gives a folder named outside ASCII three encodings, BINARY, US-ASCII with invalid bytes, and UTF-8 (`ruby.c`, lines 2546 to 2589; `file.c`, `copy_path_class`), so the app's code that joins or matches its paths raises, and Bundler cannot set up its gems: on Linux its vendored Thor fails as it loads, and on macOS `clean_load_path` raises (`doc/contributors/research/2026-11-13-c-locale.md`). So every Ruby of a runtime coerces the C locale, as Python does (PEP 538): a coercion in the launcher alone would miss each Ruby that `bin/ruby` starts.

`fledge_coerce_locale` in `locale.c`, for the Unix launcher, `bin/ruby`, and the phone runtime:

1. `setlocale(LC_CTYPE, "")`, as `main.c` does.
2. When `LC_ALL` or `LC_CTYPE` has a non-empty value, stop: the person chose.
3. When the locale chosen is neither `C` nor `POSIX`, stop.
4. Try `C.UTF-8`, `C.utf8`, `UTF-8`, and `en_US.UTF-8`, and keep the first that `setlocale` accepts and whose `nl_langinfo(CODESET)` is `UTF-8` or `utf8`, in any case.
5. With none, go back to `C`.

Nothing is exported: `ENV`, and programs that are not Ruby, see the person's own locale. Every Ruby the app starts through `RbConfig.ruby` coerces for itself, and so does `bin/ruby` run by hand.

With no locale, or `LANG=C`, the three encodings are then UTF-8 where `ruby` gives US-ASCII. The maintainer accepted that "for now", until the first app developer it upsets, and asked that it not be hidden (`decisions.md`, 2026-11-03); it meets the bar of 2026-11-12 as inherent to where the app ships. `doc/differences_from_ruby.md`, "The locale", tells developers. Not coercing breaks the app in such a folder. PEP 538 as written also coerces an explicit `LC_CTYPE=C` and exports `LC_CTYPE`, overriding a person's choice and adding to `ENV`; PEP 538 itself leaves `LC_ALL` alone (CPython v3.13.0, `Python/pylifecycle.c`, lines 189 to 194). Fixing each failure in Ruby, Bundler, and Thor, as the drafts beside the research propose, moves the difference rather than closing it: the app would see paths that are not UTF-8, and raise on joining them. Only Ruby treating the C locale as UTF-8, as CPython does under PEP 540, closes it (`doc/contributors/drafts/ruby-c-locale-utf8.md`).

**Reversal,** when an app developer reports the coercion as a surprise: `fledge_coerce_locale` does only `setlocale(LC_CTYPE, "")` for its callers (`ruby_main.c`, `unix.c`, and `runtime/mobile/fledge_ruby.c`); the `LOCALE_FACTS` entries of `Parity::JUSTIFIED`, their lines in `test/parity_justified.yml`, and the locale entry of `RubySpec::JUSTIFIED` go; and the tests that expect UTF-8 in a bare C locale, `doc/differences_from_ruby.md`'s "The locale", and the CHANGELOG change. A phone, which starts every app with no locale, then reads all text as US-ASCII.

On Windows the launcher calls `setlocale(LC_CTYPE, "")` as `main.c` does, and its manifest declares UTF-8 as the process's ANSI code page (`activeCodePage`), which `ruby.exe` does not. Ruby's `Encoding.default_external` is UTF-8 there whatever the code page (since Ruby 3.0, Feature #16604), and so is `Encoding.find("filesystem")` (`localeinit.c`, `Init_enc_set_filesystem_encoding`, lines 117 to 137 at Ruby 0e25874222). `Encoding.locale_charmap` is the console's input code page, or, in a process with no console, such as a windowed app, the ANSI code page (`localeinit.c`, lines 48 to 54: `GetConsoleCP`, then `GetACP`). Ruby writes to a console with `WriteConsoleW` (`win32/win32.c`, `rb_w32_write_console`), so text outside the code page still shows as written.

The ANSI code page is what every Windows function whose name ends in `A` reads a narrow string in. Ruby's own file, environment, and process functions convert UTF-8 to UTF-16 themselves and call the `W` functions, and `ruby/win32.h` points a C extension's `open`, `stat`, `access`, `mkdir`, `unlink`, and `getenv` at them too (lines 125 to 183 and 664). What reaches an `A` function with Ruby's UTF-8 bytes is a gem's own: ffi opens a DLL with `LoadLibraryExA` (`ext/ffi_c/DynamicLibrary.c`, lines 215 to 225, at ffi 1.17.4), and an extension may call `fopen` or a Windows function directly. Under code page 1252 those name no file whose path holds a character outside ASCII, such as a DLL in `C:\Users\José\`; under UTF-8 they do. What `activeCodePage` UTF-8 changes in the launcher's process, from Windows 10 version 1903 ("Use UTF-8 code pages in Windows apps", Microsoft Learn), and nothing else:

- `GetACP` is 65001, and so is `GetOEMCP`, so every `A` function, and `MultiByteToWideChar` with `CP_ACP`, reads UTF-8.
- `setlocale(LC_CTYPE, "")` takes its code page from `GetACP` (UCRT's `setlocale` reference, "Remarks"), so the C runtime's locale is UTF-8 (`English_United States.utf8` where `ruby.exe` gets `.1252`), and UCRT's narrow functions, `fopen` and `_mkdir` among them, read UTF-8 (the same page, "UTF-8 support").
- `Encoding.locale_charmap` with no console is `CP65001`, so `Encoding.find("locale")` is UTF-8 in a windowed app, where `rubyw.exe` gives the system's, such as Windows-1252. With a console it is the console's code page, as under `ruby.exe`: the manifest changes neither of the console's code pages.
- `Time#zone`, when `TZ` is set, takes the C runtime's zone name in the encoding `GetACP` names (`time.c`, lines 769 to 774), UTF-8 rather than Windows-1252; a name in ASCII, such as `CET`, is US-ASCII either way.
- GDI's `A` functions keep the system's code page, as Microsoft's page says, so a gem that draws text with them gains nothing.

Only the manifest sets a process's ANSI code page, which Windows reads before the program runs and no call changes, and it mends every narrow call at once: ffi's `LoadLibraryExA`, Fiddle's `dlopen` (`LoadLibrary`, `ext/fiddle/fiddle.h`, line 34, at fiddle 1.1.8), and an extension's `fopen`. `setlocale(LC_CTYPE, ".UTF8")` mends `fopen` alone. Patching a developer's gems is ruled out (`doc/contributors/design/gems.md`, "Checks that are not about licenses"); 8.3 short names would change `$0` and `__dir__`, and can be turned off for a volume; Windows' system-wide UTF-8 setting needs an administrator and changes every program. A fix in ffi (`doc/contributors/drafts/ffi-windows-utf8-path.md`) would cover ffi alone. Windows 10 before version 1903 ignores `activeCodePage`, so an app there behaves as under `ruby.exe`. `doc/differences_from_ruby.md`, "Windows' ANSI code page", lists what an app's code can see.

CI run 43278468138, on the `experiment/windows-acp` branch, printed each of these from both launchers and from the runtime's `ruby.exe` and `rubyw.exe` on x64 and ARM64 runners, under code pages 65001 and 437.

A child process has its own code page, from its own program's manifest. RubyInstaller's `ruby.exe` declares none and keeps the system's, and a `ruby.exe.manifest` file beside it changes nothing, since `ruby.exe` embeds a manifest (for `longPathAware`) and Windows reads the embedded one (the same run). So the runtime's `ruby.exe` and `rubyw.exe`, which `RbConfig.ruby` names, are Fledge's, and embed the launcher's manifest (see "bin/ruby and restarts"): a Ruby the app starts has the app's code page. The parity check's `Windows` fact compares a child's with its parent's.

## Windows

The launcher loads Ruby's DLL when it runs, rather than importing it. Windows resolves a program's imports before any of its code runs, searching the program's folder, System32, and `PATH`, never a folder below it, so a launcher at the top of the app that imported `ruby\bin`'s DLL failed to start, with `0xC0000135` (`doc/contributors/research/2026-11-10-findings-from-the-adrs.md`, "The Windows launcher spike: importing Ruby's DLL, and the layouts tried"). Loaded by its absolute path, with the search for DLLs loaded by name kept to System32 and the folders a DLL names for itself, no other Ruby's DLL, from `PATH` or the current folder, loads in its place. Why Ruby's tree sits below the launcher, whole, is `doc/contributors/design/runtimes.md`, "Layout on Windows". The cost is that the launcher calls Ruby through function pointers typed by Ruby's headers and is built against the DLL's name, so a missing or damaged DLL is a damaged app, which exits 70.

`wmain` in `windows.c`, linked with `-municode` as `ruby.exe` is:

1. `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)`, so no DLL loads by name from the current folder or `PATH`.
2. Find its own path (see "Finding itself"), split it into ROOT and the program's name.
3. `read_config`; then `set_app_user_model_id`.
4. `scrub_environment`.
5. `load_ruby`: `LoadLibraryExW(ROOT\ruby\bin\DLL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)`, so the DLL finds its own dependencies in its folder and System32. Past `MAX_PATH`, `LoadLibraryExW` fails with `ERROR_FILENAME_EXCED_RANGE` even in a process aware of long paths, so it tries again with the `\\?\` form (`\\?\UNC\` for a network path). DLL is `FLEDGE_RUBY_DLL`, the name of the tree's Ruby DLL, such as `x64-ucrt-ruby410.dll`, compiled in. It looks up `ruby_sysinit`, `ruby_init_stack`, `ruby_init`, `ruby_options`, `ruby_executable_node`, `rb_eval_string_protect`, and `ruby_run_node` with `GetProcAddress`, typed by Ruby's headers, built with `RUBY_DONT_SUBST` since nothing of Ruby is linked.
6. `setlocale(LC_CTYPE, "")`, then `ruby_sysinit` with no arguments: on Windows it rebuilds `argv` from `GetCommandLineW` as UTF-8 (`win32/win32.c`, `rb_w32_sysinit`). `wmain` keeps the C runtime from converting the command line to the ANSI code page on the way.
7. `run_ruby`, a real stack frame below `wmain` whose local variable's address `ruby_init_stack` takes, then the steps of "Hiding and restoring the person's Ruby settings".

Files of the app are opened with `\\?\` paths where they may pass `MAX_PATH`.

**The manifest.** `windows.manifest`, embedded by `windows.rc` as resource 1 of type 24 (`RT_MANIFEST`), so it stays with the program when `fledge build` renames it:

- `longPathAware`, as RubyInstaller's `ruby.exe` declares, so RubyGems loads from an app unpacked deep in a folder tree;
- `supportedOS` for Windows 10 and 11, so Windows runs it without compatibility shims;
- `requestedExecutionLevel` `asInvoker`, which also turns off Windows' installer detection, which would ask for an administrator's password for an app whose name holds "setup", "install", or "update";
- `activeCodePage` UTF-8, so a gem's `A` calls read Ruby's UTF-8 paths as UTF-8 (see "The locale").

**The AppUserModelID.** When `fledge.cfg` names an `identifier`, console or windowed, the launcher loads `shell32.dll` from System32 and calls `SetCurrentProcessExplicitAppUserModelID` with it before any window opens, so the taskbar groups the app's windows under it and Windows attributes its notifications to it. Failing changes how Windows groups and names the app, never whether it runs, so failure is ignored. Windows shows the app's toasts only when a Start menu shortcut carries the same `System.AppUserModel.ID`, which the NSIS installer writes (`doc/contributors/design/desktop-apps.md`).

**The two builds.** `windows.c` built with `-DFLEDGE_WINDOWED` and linked with `-mwindows` is `launcherw.exe`, which shows failures in a message box (`doc/contributors/design/desktop-apps.md`, "Windows"). The console launcher may import only KERNEL32 and the universal C runtime's `api-ms-win-crt-*` DLLs; the windowed one adds USER32.

## The app folder in a macOS bundle

In a windowed macOS app the launcher is `NAME.app/Contents/MacOS/NAME`, beside links to `../Resources/app`, `bin`, `fledge.cfg`, `lib`, and `libexec` (`Fledge::MacBundle::LINKED`), and Ruby's prefix is `Contents/Resources`. Ruby resolves links in the main script's path for `__dir__` and keeps the path it was given for `$0` and `__FILE__` (`ruby.c`, lines 2688 to 2698). Run through the link, `$0` would name `Contents/MacOS/app/main.rb` and `__dir__` `Contents/Resources/app`, and `File.dirname(__FILE__) == __dir__` would be false.

So `find_app_folder` names `ROOT/app` by `realpath` once, and the launcher runs ENTRY there and sets up Bundler with the Gemfile and `.bundle/config` there. When `app` is missing the path stays `ROOT/app`, for the message.

`$LOAD_PATH` has the same trouble. Ruby takes its prefix from the launcher's real path, `Contents/MacOS` (`ruby.c`, lines 640 to 767), so its own entries would name `Contents/MacOS/lib/ruby/...` through the link, while `require` loads each file by the real path of its folder (`load.c`, line 99), so `__FILE__`, `$LOADED_FEATURES`, and `rbconfig.rb`'s `TOPDIR` name `Contents/Resources`, and `$LOAD_PATH.include?(RbConfig::CONFIG["rubylibdir"])`, true under `ruby`, would be false. So on macOS, once `ruby_options` returns, `name_load_path_by_real_paths` replaces each entry that holds Ruby's mark, `@gem_prelude_index`, with its real path, the real path of the nearest existing folder above it for an entry that does not exist, such as `site_ruby`, and gives the new entry the mark, which RubyGems reads to put a gem's paths before Ruby's own (`rubygems.rb`, `load_path_insert_index`), as `ruby.c` does when it replaces an entry itself (lines 2553 to 2568). Ruby has loaded only its own files by then, by their real paths, so nothing loads twice.

In a bundle, then, `$0`, `__FILE__`, `__dir__`, `$LOAD_PATH`, `$LOADED_FEATURES`, `RbConfig::CONFIG["prefix"]`, `RbConfig.ruby`, and `BUNDLE_GEMFILE` all name `Contents/Resources`. Everywhere else ROOT is already real and `app` and `lib` real folders, so nothing changes; the windowed parity check, which starts a bundle through Launch Services, compares `$LOAD_PATH` with `ruby main.rb`'s.

Three ways were not taken. Resolving the whole entry path would also resolve a link inside the project, such as `bin/tool` pointing at `../exe/tool`, and make `$0` the link's target where `ruby bin/tool` keeps `bin/tool`. Moving the app into `Contents/MacOS` would put files that are not code where Apple's tools expect only code, and moving Ruby's `lib` there, to make `Contents/MacOS` the prefix, would do the same with the standard library's Ruby files. A bundle's executable cannot be a link to a launcher in `Contents/Resources`, since `codesign` seals the main executable as a file.

A console program of a project with a windowed one lives in `Contents/MacOS` too, linked from the app's folder; `darwin.c`'s `realpath` resolves that link to the bundle.

## bin/ruby and restarts

A Ruby program restarts itself by asking Ruby where it is, as Puma's hot restart does: `exec RbConfig.ruby, $0, *ARGV`. Its developer expects the app to start again as it first started. Plain Ruby there would boot with the person's `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and `BUNDLER_SETUP`, which the launcher has put back, without the Bundler setup of the first start, and on macOS outside the bundle's program: the surprise the maintainer's words rule out (`decisions.md`, 2026-11-02, later again). So `bin/ruby` hands the app's own program back to the app's launcher, which does all its work again, and Fledge adds nothing an app reads to find itself: `$0`, `__FILE__`, `__dir__`, `RbConfig.ruby`, `RbConfig::CONFIG["prefix"]`, `Gem.dir`, and `Gem.path` are true inside a built app. The other answers weighed each cost more:

- **A constant or a variable naming the launcher,** such as `FLEDGE_LAUNCHER`: the app would need code of Fledge's to restart, and its `ENV` would differ from `ruby main.rb`'s.
- **`bin/ruby` doing the launcher's work itself:** a macOS restart would run as `Contents/Resources/bin/ruby`, outside the bundle's program, and the launcher's work would live in two programs.
- **`RbConfig.ruby` naming the launcher:** `RbConfig.ruby` must run any script and take Ruby's options, as RubyGems' tools and the parity check use it, and the launcher runs only the app.
- **A shell script in place of `bin/ruby`:** it costs a process and a shell for every Ruby the app starts.

The cost of the hand-off is that `bin/ruby` is no longer only `main.c`: for every Ruby the app starts with a script it reads `fledge.cfg` and the folder beside it, a few system calls, and it carries Fledge's code (`relaunch.c`, `config.c`, `locale.c`), which `runtime/licenses.yml` records.

On macOS and Linux the runtime's `bin/ruby` is `ruby_main.c`: Ruby's `main.c` built against the launcher's static libruby with the launcher's link line, so both carry the same Ruby. It differs from `main.c` in two calls: `fledge_relaunch` first, and `fledge_coerce_locale` in place of `setlocale`. It hides nothing and reads no `fledge.cfg` unless `fledge_relaunch` finds the app's program.

`fledge_relaunch` (`relaunch.c`) hands the app's own program to the app's launcher when all of these hold:

1. `argv[1]` is not empty, does not begin with `-`, and names a regular file.
2. `bin/ruby` finds its own real path (`fledge_executable_path`), and PREFIX, two folders up, holds a readable `fledge.cfg`.
3. A launcher is a regular, executable file, not a link, whose name does not begin with `.`, in PREFIX or, in a `.app`, in `PREFIX/../MacOS` by its real path, where `fledge.cfg` is the same file as PREFIX's by device and inode.
4. That launcher's part of `fledge.cfg` (its section, by its file name, or the whole file without sections) names an `entry` that, under `PREFIX/app`, is the same file as `argv[1]` by device and inode. A relative path, a link, or the path through `Contents/MacOS/app` all match.

Then it `execv`s the launcher with `argv[0]` the launcher's path and the arguments after the program. What it cannot cover stays plain Ruby, as `main.c` would run it:

- an option before the program, as in `exec RbConfig.ruby, "--yjit", $0` or a gem's executable run with `-x`, since finding the script behind Ruby's options would mean parsing Ruby's command line as `ruby.c` does and merging those options with the launcher's; such a program enables the option in Ruby instead, or clears the person's settings itself;
- any other script, such as `system(RbConfig.ruby, "worker.rb")`, which runs with the person's settings, as `ruby worker.rb` would, and in Bundler's environment in an app with a Gemfile;
- a runtime whose `fledge.cfg` is missing or unreadable, and a launcher renamed by hand in an app of several programs, which has no section.

In an app of one program, whose `fledge.cfg` has no sections, the first executable file `bin/ruby` finds in the folder is taken as the launcher; `fledge build` puts no other there. A launcher found and not started exits 70 (see "Messages and exit statuses").

On Windows the runtime's `ruby\bin\ruby.exe` and `rubyw.exe` are `ruby_main.c` too, in place of RubyInstaller's, compiled by `RuntimeBuilder::Windows#compile_ruby` with llvm-mingw, linked against Ruby's DLL through the tree's import library (`lib\libx64-ucrt-ruby410.dll.a`) as RubyInstaller links its own, `rubyw.exe` with `-mwindows`, and with the launcher's resources, so its manifest is `windows.manifest`. Replacing them in place, rather than adding programs beside them, keeps RubyInstaller's tree in its shape: `RbConfig.ruby`, `Gem.ruby`, the gems' `.bat` wrappers, and mkmf name `ruby.exe` by its place, and nothing else of the tree changes. `wmain`:

1. `fledge_limit_dll_search` (`windows_relaunch.c`): `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` and `AddDllDirectory` of `ruby_builtin_dlls` beside it, as the launcher does, so a Ruby the app starts loads DLLs from where the app's Ruby does. RubyInstaller's own `operating_system.rb`, which a runtime replaces, called `SetDefaultDllDirectories` for its `ruby.exe` (`ruby_installer/runtime/msys2_installation.rb`, `enable_dll_search_paths`).
2. `setlocale(LC_CTYPE, "")` and `ruby_sysinit`, as `main.c`.
3. `fledge_relaunch` (`windows_relaunch.c`), with the arguments `ruby_sysinit` read as Ruby reads them, then `ruby_start_main`.

`fledge_relaunch` on Windows runs the app's launcher when all of these hold:

1. `argv[1]` is not empty, does not begin with `-`, and names a regular file that is no link.
2. The command line's first two arguments are written as Ruby's own `exec` writes them (`win32/win32.c`, `join_argv`): plain, with no quote, or in double quotes with no quote inside, and the script with none of `* ? [ {`, which Ruby would expand. Ruby splits a command line by its own rules (`w32_cmdvector`), with single quotes and file name patterns beyond Microsoft's; anything else stays plain Ruby, rather than be split differently.
3. ROOT, three folders above `ruby.exe`, holds a readable `fledge.cfg`.
4. A launcher is a file in ROOT whose name ends in `.exe`, that is no link, whose section of `fledge.cfg` (or the whole file without sections) names an `entry` that, under `ROOT\app`, is the same file as `argv[1]` by volume serial number and file index (`GetFileInformationByHandle`), and that holds `FLEDGE_LAUNCHER_MARK`, bytes `windows.c` keeps. The mark keeps an installer's `uninstall.exe`, which sits beside the launcher, from passing for it in an app of one program.

Then it runs the launcher with `CreateProcessW`, its path quoted and the rest of its own command line after the script exactly as given, inheriting its handles and standard streams as Ruby's own `CreateChild` does, waits for it, and exits with its status. Windows has no `exec` that keeps the process: Ruby's `exec` there does the same, starting the program and waiting for it (`process.c`, line 1639, calls `rb_w32_uaspawn` with `P_OVERLAY`, and `win32/win32.c`'s `child_result`, lines 1188 to 1203, waits and exits with the child's status, at Ruby 0e25874222). While it waits it handles Ctrl-C and Ctrl-Break by doing nothing, as CPython's `py` launcher does (`PC/launcher.c`, `ctrl_c_handler`), so the launcher, which shares its console, decides what they do; a handler, unlike ignoring them, is not inherited. A launcher found and not started exits 70.

So a restart through `RbConfig.ruby` boots as the app first booted, with its AppUserModelID and code page. What stays as under `ruby.exe` is the new PID, and, in a windowed app, the console `ruby.exe`, a console program, opens while the restarted app runs.

### Bundler's variables spelled otherwise

Windows' variable names ignore case, and a person may spell Bundler's otherwise, as `bundle_gemfile`, or as Windows itself spells `PATH`, `Path`. Ruby's `ENV` writes there keep a variable's existing name (`hash.c`, `ruby_setenv`, through `_wputenv_s`, at Ruby 0e25874222), and Bundler's `EnvironmentPreserver` looks its keys up in a Ruby Hash, by Bundler's spelling (`bundler/environment_preserver.rb`, `backup` and `restore`, lines 40 to 67, at Bundler 4.0.20). So stock `bundle exec` there, measured on Windows with the probe in a project of its own (Bundler 4.1.0.beta3), keeps the person's spelling in `ENV`, records `BUNDLER_ORIG_BUNDLE_GEMFILE` and `BUNDLER_ORIG_PATH` as `BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL`, and gives the program's `Bundler.original_env` the values its `ENV` holds under the person's names: the Gemfile Bundler set, and the `Path` Bundler composed. A restart through `exec RbConfig.ruby, $0` finds the same.

The launcher removes the person's variables before Ruby boots and writes `BUNDLE_GEMFILE` in Bundler's spelling (`setup_bundler`), so the composition's writes would keep Bundler's spelling, and a restart, inheriting `BUNDLE_GEMFILE` with `BUNDLER_ORIG_BUNDLE_GEMFILE` intentionally nil, would lose it from `Bundler.original_env`. On Windows the composition therefore ends by giving each variable it set aside its person's spelling back, and by making `Bundler::ORIGINAL_ENV` the `restore` of the `ENV` it composed, as the program's Bundler under `bundle exec` makes it from the `ENV` it starts with (`bundler.rb`, `ORIGINAL_ENV`). Elsewhere names are exact, `restore` of that `ENV` is what step 3 already gave, and the code does neither.

`BUNDLE_GEMFILE` and `BUNDLE_LOCKFILE`, which name the app's own Gemfile and lockfile, keep Bundler's spelling, where `bundle exec` keeps the person's. Bundler's settings read `ENV` by Bundler's spelling alone (`bundler/settings.rb`, `Settings#initialize`, at Bundler 4.0.20), and `Bundler.setup` takes the Gemfile from them (`bundler.rb`, `configure_custom_gemfile`), so with the person's spelling a Ruby the app starts with `bundler/setup` in `RUBYOPT` finds no `BUNDLE_GEMFILE` among them and sets up the Gemfile the person's own `.bundle/config` names, as Delivery's hostile environment showed (AGENTS.md, Design precedence 1). A restart inherits only `ENV`, so the app's `Bundler.original_env` then holds no `bundle_gemfile`, where `bundle exec`'s holds the Gemfile `ENV` names under that spelling; `Parity::JUSTIFIED` says why. The parity check's `:spelled` run compares this, and its restart, with `bundle exec` (`parity.md`, "The gem-shaped run").

## System libraries on Linux

When `fledge.cfg` has `system_libraries`, written from `fledge.yml`'s `linux: system_libraries` (`doc/contributors/design/gems.md`, "Libraries from the Linux distribution", covers the list, its refusals, and why it names sonames), the Linux launcher checks them after reading `fledge.cfg` and before hiding anything or starting Ruby:

1. It makes a pipe and forks. The child `dlopen`s each name in order with `RTLD_LAZY | RTLD_LOCAL`; at the first that fails it writes the name, a newline, and `dlerror`'s reason to the pipe, and exits 1; otherwise it exits 0.
2. The parent reads the pipe and waits. At a failure with a name it exits 72 with the message above.

The check runs in a child so that the app's own process loads nothing early and a library's constructors run when the gem loads it, as under `ruby`. A computer that cannot make a pipe or fork, and a child that ends without naming a library, skip the check, and the gem's own loading decides. The message names a library, which a person installs from a software center, and never Ruby or a gem.
