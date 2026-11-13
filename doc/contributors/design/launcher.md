<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Launcher and bin/ruby

This document describes the program at the top of every desktop app, the launcher, and the runtime's `bin/ruby` on macOS and Linux: how each starts, what each reads, what it changes in the environment and in what order, what it prints, and how it exits. ADR 001 decides that an app is a launcher that embeds CRuby; ADR 002 its messages and statuses; ADR 081 that it adds nothing between Ruby and the program; ADR 037 the console and windowed launchers; ADR 038 the Windows layout; ADR 040 the hiding and restoring of the person's Ruby settings; ADR 087 the locale; ADR 086 Bundler; ADR 024 the sections of `fledge.cfg`; ADR 026 the restart; and ADR 030 the Linux system-library check. Line numbers below are at Ruby 4.1.0-preview1, as the launcher's comments cite them, except where a sentence says otherwise.

## Source files

Everything is in `runtime/launcher/`. `launcher.h` declares what the files share, including the exit statuses.

| File | Holds | Linked into |
|---|---|---|
| `unix.c` | the macOS and Linux launcher's `main` and its steps | the launcher |
| `darwin.c`, `linux.c` | `fledge_executable_path`; on Linux also `fledge_find_system_libraries` | the launcher and `bin/ruby` |
| `windows.c` | the whole Windows launcher | `launcher.exe`, `launcherw.exe` |
| `scrub.c` | which variables are hidden from Ruby's boot | every launcher |
| `config.c` | the `fledge.cfg` reader | every launcher, `bin/ruby`, the phone runtime |
| `bundler.c` | the Ruby that loads the app's Bundler, and the Ruby that composes `bundle exec`'s environment | every launcher; the phone runtime, for the first |
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
8. `ruby_start_main(run_ruby, ...)`. `run_ruby` runs `RUBY_INIT_STACK`, `ruby_init`, and `ruby_options`. When the node is executable, it runs `pin_rubygems`; for an app with a Gemfile, `setup_bundler`, `pin_rubygems` again, and `bundle_environment`. Then `restore_environment`, and `ruby_run_node`.

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

## Signals and the console

Ruby installs handlers for SIGINT and SIGHUP (`signal.c`, `install_sighandler`), and re-raises the signal with its default action after cleanup (`eval.c`, `rb_ec_cleanup`, and `signal.c`, `ruby_default_signal`, at Ruby 4.1.0-preview1). The launcher installs no handler and ignores no signal, so Ctrl-C raises `Interrupt` in the main thread, runs `ensure` clauses and `at_exit` hooks, and ends the app by SIGINT (130 to a shell on macOS and Linux, exit code 3 on Windows); a closed terminal raises `SignalException` for SIGHUP (129). A built app started in the background of a shell script ignores Ctrl-C, as `ruby` does there.

On Windows, the C runtime UCRT turns CTRL_C_EVENT into SIGINT and maps no other console event to a signal, and neither Ruby nor the launcher installs a console control handler. Closing a console window ends the app at once, with STATUS_CONTROL_C_EXIT, as it ends `ruby.exe`.

## Hiding and restoring the person's Ruby settings

`scrub.c` names the prefixes: `RUBY`, `GEM_`, `GEMRC`, `BUNDLE_`, `BUNDLER_`, and `RI_FORCE_PATH_FOR_DLL`, with a comment of which variable each covers and where Ruby, RubyGems, Bundler, and RubyInstaller read it. Variables outside them, such as `SSL_CERT_FILE`, `HOME`, and the `XDG_` folders, describe the computer, not the person's Ruby, and stay.

- **On macOS and Linux**, `scrub_environment` copies each matching `NAME=value` and `unsetenv`s it, scanning `environ` again after each removal. An entry without `=` is no variable to `getenv` or to Ruby's `ENV` (`hash.c`, `env_each_pair`), and `unsetenv` cannot remove it, so it stays, as under `ruby`.
- **On Windows**, names are compared ignoring ASCII case. The launcher collects every match from `GetEnvironmentStringsW` first, skipping the `=C:` entries that hold each drive's current folder, then removes each from both copies of the environment: the C runtime's (`_wputenv_s`), which Ruby's `getenv` reads until Ruby has its own, and the process's (`SetEnvironmentVariableW`), which Ruby reads afterwards and children inherit. It shares UCRT with RubyInstaller's Ruby, so the C runtime's copy is the one Ruby reads.

After `ruby_options` returns, Ruby has booted, RubyGems has loaded, and the program is compiled but not run. The order is then fixed:

1. `pin_rubygems` evaluates `Gem.paths if defined?(Gem.paths)`. `Gem.paths` reads `GEM_HOME`, `GEM_PATH`, and `GEM_SPEC_CACHE` once and keeps the answer (`rubygems.rb` and `rubygems/path_support.rb`), so the gem paths are fixed while the person's are hidden. Fledge's `rubygems/defaults/operating_system.rb` makes the default path the runtime's gem folder alone.
2. For an app with a Gemfile, Bundler sets up the app's gems, and `pin_rubygems` runs again (see "The Bundler environment").
3. The variables come back. For an app without a Gemfile, `restore_environment` puts each back with its own value (`setenv`; on Windows `_wputenv_s` and `SetEnvironmentVariableW`), skipping any that is set again by then. For an app with one, `bundle_environment` does it beneath Bundler's settings, and `restore_environment` then has nothing left to do.
4. `ruby_run_node` runs the program.

A failure in these steps exits 70: "could not start RubyGems", "could not clear the environment", "could not restore NAME".

Each step that runs Ruby uses `rb_eval_string_protect`, so the launcher adds nothing to `$LOADED_FEATURES` or `$LOAD_PATH` and defines no global or constant.

## The Bundler environment

For an app whose `fledge.cfg` names a `gemfile`, `setup_bundler` runs while the person's settings are still hidden:

1. It requires Bundler by its path, so that `Bundler.original_env` records the environment Ruby booted with. Required by name, RubyGems would first activate the bundler gem, which `bundle exec` does not. Which Bundler, `fledge_bundler_code` in `bundler.c` writes: the runtime's own, `File.join(RbConfig::CONFIG['rubylibdir'], 'bundler')`, or, when `fledge.cfg` names a `bundler` version, the gem `fledge build` installed for it (`doc/contributors/design/gems.md`, "The lockfile's Bundler"). For that one, the launcher first puts the gem's lib, `File.join(Gem.dir, 'gems', 'bundler-VERSION', 'lib')`, at the front of `$LOAD_PATH`, where `bundle exec`'s `RUBYLIB` puts it for the program it runs (`bundler/shared_helpers.rb`, `set_rubylib`), and requires `bundler` from there. `Gem.dir` is the runtime's gem folder, since RubyGems' paths are fixed before.
2. It sets `BUNDLE_GEMFILE` to `APP/GEMFILE`, reads the `BUNDLE_` lines of `APP/.bundle/config`, the file `fledge build` wrote (beside the Gemfile on a phone), into `ENV`, and points `BUNDLE_APP_CONFIG` and `BUNDLE_USER_CONFIG` at `APP/.bundle/none`, which holds nothing. Bundler reads no settings file, and the person's `~/.bundle/config` is never read. Bundler reads a settings file with RubyGems' YAML serializer, which defines a hollow `Psych` when Psych is not loaded, so reading the file would make `defined?(Psych)` true where it is false under `bundle exec`.
3. It requires `bundler/setup` by its path, from the same Bundler, as `bundle exec`'s `RUBYOPT=-r.../bundler/setup` does (`bundler/shared_helpers.rb`, `set_rubyopt`). On failure it prints the exception's message and exits 70 ("could not set up this app's gems"); `bundler/setup` prints its own message and exits when standard output is a terminal.
4. It deletes every variable step 2 put in `ENV`, so the program's `ENV` is what it was. The file stays in the app for a Ruby the app starts with `bundler/setup`, which reads it as before.

`bundle_environment` then evaluates the Ruby that `bundler.c` writes, with the set-aside variables inside it as hexadecimal, so the launcher needs no Ruby function but `rb_eval_string_protect`. The code, run once:

1. decodes the set-aside variables, in the locale's encoding (UTF-8 on Windows, where Ruby's `ENV` is UTF-8);
2. keeps `bundled`, the `ENV` the protected setup left, and `booted`, a copy of `Bundler::ORIGINAL_ENV`;
3. makes a `Bundler::EnvironmentPreserver` over `booted` merged with the set-aside variables, and replaces `Bundler::ORIGINAL_ENV` with its `restore`, so that a person who started the app from inside a bundle gets their environment from before it, as a Bundler started under `bundle exec` does;
4. replaces `ENV` with the preserver's `backup`, whose `BUNDLER_ORIG_*` record the person's values;
5. puts back `BUNDLE_GEMFILE` and `BUNDLE_LOCKFILE` from `bundled`;
6. calls `Bundler::SharedHelpers.set_bundle_environment`, which composes `PATH`, `RUBYOPT`, and `RUBYLIB` over the person's values as `bundle exec` does, with `-r.../bundler/setup` before the person's `RUBYOPT`;
7. puts back `GEM_HOME` and `GEM_PATH` from `bundled`, which name the runtime's gem folder;
8. sets up `MANPATH` as Bundler does, when Bundler had changed it.

So `ENV` is `bundle exec`'s, and `Bundler.original_env`, `with_original_env`, `unbundled_env`, and `with_unbundled_env` give the person's own environment. Nothing here changes which gems load: `Gem.paths` is fixed, Bundler's `Settings` read `ENV` once when created, and Bundler's memoized `bundle_path` names the runtime's gems. A failure exits 70, "could not set up this app's environment". Reimplementing Bundler's composition in C would mean guessing at Bundler's rules, and restoring the person's environment before Bundler loads would expose its setup to their values.

The app's `.bundle/config`, the evaluated gemspecs, and Fledge's `force_activate` wrap are `fledge build`'s and the RubyGems defaults' work: `doc/contributors/design/gems.md`.

## fledge.cfg

`fledge build` writes `fledge.cfg` beside the launcher (`Fledge::Assembly.launch_config`). The launcher is the same program for every app, and on macOS a signed one, so nothing about one app is written into it; instead it reads a small text file beside itself, as Python's interpreter reads the `pyvenv.cfg` beside it (PEP 405). In a macOS bundle `Contents/MacOS/fledge.cfg` is a link to `Contents/Resources/fledge.cfg`.

**Format.** UTF-8 text, shorter than 65,536 bytes, with no NUL. Each line is `key = value`; spaces and tabs around key and value, and a trailing carriage return, are trimmed. Blank lines and lines beginning with `#` say nothing. A line `[NAME]` heads a section. The first line is a comment:

```
# Written by fledge build VERSION for PLATFORM: what this app's program runs (ADR 005).
```

ending `what this app's programs run (ADR 024).` for an app of several programs. A phone project's `fledge.cfg` (`Fledge::MobileProject`) names no version or platform: `# Written by fledge build: ...`. `fledge build --from` reads VERSION and PLATFORM from it (`Fledge::BuiltApp::HEADER`). Every app carries these words, so the ADR numbers in them do not change.

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

Once the program runs, the status is the program's own. `bin/ruby`, which is Ruby's program, says `ruby: could not run LAUNCHER: REASON` and exits 70 when it finds the app's launcher and cannot start it.

## The locale

`fledge_coerce_locale` in `locale.c`, for the Unix launcher, `bin/ruby`, and the phone runtime:

1. `setlocale(LC_CTYPE, "")`, as `main.c` does.
2. When `LC_ALL` or `LC_CTYPE` has a non-empty value, stop: the person chose.
3. When the locale chosen is neither `C` nor `POSIX`, stop.
4. Try `C.UTF-8`, `C.utf8`, `UTF-8`, and `en_US.UTF-8`, and keep the first that `setlocale` accepts and whose `nl_langinfo(CODESET)` is `UTF-8` or `utf8`, in any case.
5. With none, go back to `C`.

Nothing is exported: `ENV`, and programs that are not Ruby, see the person's own locale. Every Ruby the app starts through `RbConfig.ruby` coerces for itself.

On Windows the launcher calls `setlocale(LC_CTYPE, "")` as `main.c` does, and its manifest declares UTF-8 as the process's ANSI code page (`activeCodePage`), which `ruby.exe` does not. Ruby's `Encoding.default_external` is UTF-8 there whatever the code page (since Ruby 3.0, Feature #16604), and so is `Encoding.find("filesystem")` (`localeinit.c`, `Init_enc_set_filesystem_encoding`, lines 117 to 137 at Ruby 0e25874222). `Encoding.locale_charmap` is the console's input code page, or, in a process with no console, such as a windowed app, the ANSI code page (`localeinit.c`, lines 48 to 54: `GetConsoleCP`, then `GetACP`). Ruby writes to a console with `WriteConsoleW` (`win32/win32.c`, `rb_w32_write_console`), so text outside the code page still shows as written.

The ANSI code page is what every Windows function whose name ends in `A` reads a narrow string in. Ruby's own file, environment, and process functions convert UTF-8 to UTF-16 themselves and call the `W` functions, and `ruby/win32.h` points a C extension's `open`, `stat`, `access`, `mkdir`, `unlink`, and `getenv` at them too (lines 125 to 183 and 664). What reaches an `A` function with Ruby's UTF-8 bytes is a gem's own: ffi opens a DLL with `LoadLibraryExA` (`ext/ffi_c/DynamicLibrary.c`, lines 215 to 225, at ffi 1.17.4), and an extension may call `fopen` or a Windows function directly. Under code page 1252 those name no file whose path holds a character outside ASCII, such as a DLL in `C:\Users\José\`; under UTF-8 they do. What `activeCodePage` UTF-8 changes in the launcher's process, from Windows 10 version 1903 ("Use UTF-8 code pages in Windows apps", Microsoft Learn), and nothing else:

- `GetACP` is 65001, and so is `GetOEMCP`, so every `A` function, and `MultiByteToWideChar` with `CP_ACP`, reads UTF-8.
- `setlocale(LC_CTYPE, "")` takes its code page from `GetACP` (UCRT's `setlocale` reference, "Remarks"), so the C runtime's locale is UTF-8 (`English_United States.utf8` where `ruby.exe` gets `.1252`), and UCRT's narrow functions, `fopen` and `_mkdir` among them, read UTF-8 (the same page, "UTF-8 support").
- `Encoding.locale_charmap` with no console is `CP65001`, so `Encoding.find("locale")` is UTF-8 in a windowed app, where `rubyw.exe` gives the system's, such as Windows-1252. With a console it is the console's code page, as under `ruby.exe`: the manifest changes neither of the console's code pages.
- `Time#zone`, when `TZ` is set, takes the C runtime's zone name in the encoding `GetACP` names (`time.c`, lines 769 to 774), UTF-8 rather than Windows-1252; a name in ASCII, such as `CET`, is US-ASCII either way.
- GDI's `A` functions keep the system's code page, as Microsoft's page says, so a gem that draws text with them gains nothing.

CI run 43278468138, on the `experiment/windows-acp` branch, printed each of these from both launchers and from the runtime's `ruby.exe` and `rubyw.exe` on x64 and ARM64 runners, under code pages 65001 and 437.

A child process has its own code page, from its own program's manifest. RubyInstaller's `ruby.exe` declares none and keeps the system's, and a `ruby.exe.manifest` file beside it changes nothing, since `ruby.exe` embeds a manifest (for `longPathAware`) and Windows reads the embedded one (the same run). So the runtime's `ruby.exe` and `rubyw.exe`, which `RbConfig.ruby` names, are Fledge's, and embed the launcher's manifest (see "bin/ruby and restarts"): a Ruby the app starts has the app's code page. The parity check's `Windows` fact compares a child's with its parent's.

## Windows

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

**The two builds.** `windows.c` built with `-DFLEDGE_WINDOWED` and linked with `-mwindows` is `launcherw.exe`, which shows failures in a message box (ADR 037). The console launcher may import only KERNEL32 and the universal C runtime's `api-ms-win-crt-*` DLLs; the windowed one adds USER32.

## The app folder in a macOS bundle

In a windowed macOS app the launcher is `NAME.app/Contents/MacOS/NAME`, beside links to `../Resources/app`, `bin`, `fledge.cfg`, `lib`, and `libexec` (`Fledge::MacBundle::LINKED`), and Ruby's prefix is `Contents/Resources`. Ruby resolves links in the main script's path for `__dir__` and keeps the path it was given for `$0` and `__FILE__` (`ruby.c`, lines 2688 to 2698). Run through the link, `$0` would name `Contents/MacOS/app/main.rb` and `__dir__` `Contents/Resources/app`, and `File.dirname(__FILE__) == __dir__` would be false.

So `find_app_folder` names `ROOT/app` by `realpath` once, and the launcher runs ENTRY there and sets up Bundler with the Gemfile and `.bundle/config` there. In a bundle, `$0`, `__FILE__`, `__dir__`, `RbConfig::CONFIG["prefix"]`, `RbConfig.ruby`, and `BUNDLE_GEMFILE` all name `Contents/Resources`. Everywhere else ROOT is already real and `app` a real folder, so nothing changes. When `app` is missing the path stays `ROOT/app`, for the message.

Two ways were not taken. Resolving the whole entry path would also resolve a link inside the project, such as `bin/tool` pointing at `../exe/tool`, and make `$0` the link's target where `ruby bin/tool` keeps `bin/tool`. Moving the app into `Contents/MacOS` would put files that are not code where Apple's tools expect only code.

A console program of a project with a windowed one lives in `Contents/MacOS` too, linked from the app's folder; `darwin.c`'s `realpath` resolves that link to the bundle.

## bin/ruby and restarts

On macOS and Linux the runtime's `bin/ruby` is `ruby_main.c`: Ruby's `main.c` built against the launcher's static libruby with the launcher's link line, so both carry the same Ruby. It differs from `main.c` in two calls: `fledge_relaunch` first, and `fledge_coerce_locale` in place of `setlocale`. It hides nothing and reads no `fledge.cfg` unless `fledge_relaunch` finds the app's program.

`fledge_relaunch` (`relaunch.c`) hands the app's own program to the app's launcher (ADR 026) when all of these hold:

1. `argv[1]` is not empty, does not begin with `-`, and names a regular file.
2. `bin/ruby` finds its own real path (`fledge_executable_path`), and PREFIX, two folders up, holds a readable `fledge.cfg`.
3. A launcher is a regular, executable file, not a link, whose name does not begin with `.`, in PREFIX or, in a `.app`, in `PREFIX/../MacOS` by its real path, where `fledge.cfg` is the same file as PREFIX's by device and inode.
4. That launcher's part of `fledge.cfg` (its section, by its file name, or the whole file without sections) names an `entry` that, under `PREFIX/app`, is the same file as `argv[1]` by device and inode. A relative path, a link, or the path through `Contents/MacOS/app` all match.

Then it `execv`s the launcher with `argv[0]` the launcher's path and the arguments after the program. What it cannot cover stays plain Ruby, as `main.c` would run it:

- an option before the program, as in `exec RbConfig.ruby, "--yjit", $0` or a gem's executable run with `-x`;
- any other script, such as `system(RbConfig.ruby, "worker.rb")`, which runs with the person's settings, as `ruby worker.rb` would, and in Bundler's environment in an app with a Gemfile;
- a runtime whose `fledge.cfg` is missing or unreadable, and a launcher renamed by hand in an app of several programs, which has no section.

In an app of one program, whose `fledge.cfg` has no sections, the first executable file `bin/ruby` finds in the folder is taken as the launcher; `fledge build` puts no other there. A launcher found and not started exits 70 (see "Messages and exit statuses").

On Windows the runtime's `ruby\bin\ruby.exe` and `rubyw.exe` are `ruby_main.c` too, in place of RubyInstaller's, compiled by `RuntimeBuilder::Windows#compile_ruby` with llvm-mingw, linked against Ruby's DLL through the tree's import library (`lib\libx64-ucrt-ruby410.dll.a`) as RubyInstaller links its own, `rubyw.exe` with `-mwindows`, and with the launcher's resources, so its manifest is `windows.manifest`. RubyInstaller's tree keeps its shape: `RbConfig.ruby`, `Gem.ruby`, the gems' `.bat` wrappers, and mkmf name `ruby.exe` by its place, and nothing else of the tree changes. `wmain`:

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

### A restart of an app with a Gemfile, with Bundler's variables spelled otherwise

A known defect, on Windows only. Windows' variable names ignore case, and a person may spell Bundler's, `bundle_gemfile` or Windows' own `Path`, in another case than Bundler's `BUNDLE_GEMFILE` and `PATH`. Bundler's `EnvironmentPreserver` looks its keys up in a Ruby Hash, case-sensitively (`bundler/environment_preserver.rb`, `backup` and `restore`, lines 40 to 67, in RubyInstaller's head build of 2026-11-10). Stock `bundle exec` there, measured on Windows with the probe in a project of its own (machines run 20261113-030018-fb5b70, Bundler 4.1.0.beta3), keeps the person's spelling in `ENV`, since Bundler's writes keep a variable's existing name, records `BUNDLER_ORIG_BUNDLE_GEMFILE` and `BUNDLER_ORIG_PATH` as `BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL`, and gives `Bundler.original_env` the person's `bundle_gemfile` and the `Path` Bundler has already changed; a restart through `exec RbConfig.ruby, $0` keeps `bundle_gemfile` in `Bundler.original_env`, with the value `ENV` holds then. A Fledge app's first start gives `Bundler.original_env` the person's `bundle_gemfile`; its restart loses the entry (Delivery, CI run 43351719058), most likely because the launcher sets `BUNDLE_GEMFILE` in Bundler's spelling (`windows.c`, `setup_bundler`), so the restarted app inherits that name and Bundler's `restore` deletes it; the inherited spelling is not yet measured. Delivery's hostile restart (`.github/scripts/deliver.ps1`) expects exactly that loss until it is fixed.

The fix, not yet made:

1. When the launcher sets `BUNDLE_GEMFILE`, and when the composition writes Bundler's other variables, keep the name as the person spelled it, as Ruby's `ENV[]=` does on Windows.
2. In the composition (`bundler.c`), on Windows, give `EnvironmentPreserver` the names as the person spelled them, so it records what stock `bundle exec` records, at the first start and the restart alike.
3. Compare against `bundle exec` where Ruby is: a Windows variant of the parity check's gem-shaped run with the person's `bundle_gemfile` and `Path` so spelled, comparing `ENV`, `Bundler.original_env`, and the restart's report with `bundle exec`'s. Delivery, which has no Ruby, then expects what that variant establishes.

## System libraries on Linux

When `fledge.cfg` has `system_libraries`, written from `fledge.yml`'s `linux: system_libraries` (ADR 030; `doc/contributors/design/gems.md` covers the list and its refusals), the Linux launcher checks them after reading `fledge.cfg` and before hiding anything or starting Ruby:

1. It makes a pipe and forks. The child `dlopen`s each name in order with `RTLD_LAZY | RTLD_LOCAL`; at the first that fails it writes the name, a newline, and `dlerror`'s reason to the pipe, and exits 1; otherwise it exits 0.
2. The parent reads the pipe and waits. At a failure with a name it exits 72 with the message above.

The check runs in a child so that the app's own process loads nothing early and a library's constructors run when the gem loads it, as under `ruby`. A computer that cannot make a pipe or fork, and a child that ends without naming a library, skip the check, and the gem's own loading decides. The message names a library, which a person installs from a software center, and never Ruby or a gem.
