# The launcher

The launcher is the C program a person runs: every desktop app's program is a copy of it, renamed. It finds its app, reads `fledge.cfg`, checks what the app needs from the system, hides the person's Ruby settings, and starts the runtime's CRuby on the app's program, in its process, as Ruby's `main.c` does (ADR 001). Its source is `runtime/launcher`; it is compiled when a runtime is built, never by `fledge build`.

## The files

| File | Role |
| - | - |
| `unix.c` | the launcher for macOS and Linux: `main`, the start sequence, and Ruby's embedding |
| `windows.c` | the launcher for Windows: the same sequence in wide characters, with Ruby's DLL loaded at run time |
| `config.c` | parses `fledge.cfg`, shared by every launcher and by the runtime's `ruby` |
| `bundler.c` | the Ruby snippets the launcher evaluates: requiring Bundler, `bundler/setup`, putting the runtime's `bin` on `PATH`, and restoring the environment |
| `scrub.c` | which environment variables are set aside: names that start with `RUBY`, `GEM_`, `GEMRC`, `BUNDLE_`, `BUNDLER_`, or `RI_FORCE_PATH_FOR_DLL`, in any case on Windows |
| `locale.c` | chooses a UTF-8 locale when neither `LC_ALL` nor `LC_CTYPE` is set and the environment's locale is C or POSIX |
| `darwin.c`, `linux.c` | the launcher's path; on Linux, checking system libraries and typelibs in a child process |
| `documents.c` | on macOS, the paths of the documents Launch Services opens the app with |
| `relaunch.c`, `windows_relaunch.c` | the runtime's `ruby`: running an app's program through its launcher |
| `ruby_main.c` | the runtime's `ruby`: Ruby's `main.c`, with Fledge's relaunch called first |
| `launcher.h` | what these share, and the exit statuses |
| `windows.manifest`, `windows.rc` | the Windows launchers' manifest: run as invoker, long paths, and UTF-8 as the active code page |

Code adapted from Ruby's `main.c` sits between SPDX snippet comments under Ruby's license; the rest is Fledge's.

## The start sequence

Each step either succeeds or ends the process with a message naming the program and an exit status from `launcher.h`:

1. **Find the app.** The launcher's path, links resolved, is the app's root; its file name (without `.exe`) is the program's name. On macOS and Linux, a root folder named `bin` or `lib` is refused.
2. **Read `fledge.cfg`.** `fledge_parse_config` takes the top-level keys and the section named for the program, ignoring ASCII case. It refuses an unknown key, a key given twice, a path that could leave the app folder, and a value that isn't the shape its key takes.
3. **Check the system,** before Ruby starts, so a missing piece is named in a sentence rather than a load error: on Linux, each `system_libraries` library by `dlopen` and each `system_typelibs` typelib through GObject introspection, both in a child process; on Windows, each `visual_c_runtime` DLL in System32. A missing one exits 72 (`EX_OSFILE`).
4. **On Windows,** limit DLL search to the defaults and the runtime's `ruby_builtin_dlls`, set the process's AppUserModelID to the program's identifier, and load Ruby's DLL from `ruby\bin`.
5. **On macOS,** for a bundle that declares document types, wait up to 15 seconds for Launch Services' first Apple event, and collect the paths it lists.
6. **Set aside the environment** that would change Ruby, RubyGems, or Bundler (`scrub.c`), and, on macOS and Linux, choose a UTF-8 locale in place of C (`locale.c`). Windows' launchers declare UTF-8 as their active code page in their manifest instead.
7. **Start Ruby** on `app/ENTRY`, with `--disable=rubyopt` and `--` before it, the person's arguments after it, and then the Apple event's paths.
8. **Before the program runs,** with Ruby initialized: on macOS, name the load path's folders by their real paths; pin RubyGems' paths, put the runtime's `bin` first on `PATH`, and, when `fledge.cfg` has a `gemfile`, require the app's Bundler and run `bundler/setup` with the app's Gemfile and `.bundle/config`, frozen. Then hand the set-aside variables back, as described next.
9. **Run the program,** and return its status.

## The program runs as ruby runs it

The launcher's job is that the program can't tell it from `ruby main.rb` under `bundle exec`. Three choices carry that:

- **Ruby runs in the launcher's process,** started with `ruby_options` and `ruby_run_node` on the same kind of argument vector the `ruby` program builds, on the process's main thread. Signals, exit statuses, `$0`, and `Process.pid` are the program's, and Ctrl-C ends it as it ends `ruby`.
- **Bundler is set up as `bundle exec` sets it up,** with Bundler's `bundler/setup`, the app's settings file, and the lockfile frozen, so the load path, `ENV`, and `Bundler.settings` are Bundler's answers. A lockfile that lists another Bundler gets that Bundler from the app's gems.
- **The person's environment reaches the program as `bundle exec` leaves it.** The variables set aside before Ruby started go back into `ENV` and into Bundler's `ORIGINAL_ENV` after setup, through Bundler's `EnvironmentPreserver`. So `Bundler.with_original_env` and child processes see the person's settings, while the app's gems were set up without them.

Some differences stay, on purpose, and Parity records each one with its reason and the platforms it holds on, so that its check fails on any other ([Parity](parity.md), "Justifications"). The locale is the difference the launcher chooses. Where neither `LC_ALL` nor `LC_CTYPE` is set and the environment's locale is C or POSIX, `ruby` would take US-ASCII as its default external encoding; the launcher sets the first of `C.UTF-8`, `C.utf8`, `UTF-8`, and `en_US.UTF-8` the computer has, so the program reads and writes UTF-8, and stays in C on a computer with none of them. The runtime's `ruby` does the same, so a child `ruby` agrees with its parent. Parity justifies others besides, such as a path spelled as Windows spells it, Bundler's spelling of the Gemfile's path, the person's gem folder, and a windowed Windows app's UTF-8 locale; `test/parity_test.rb` has a test for each.

## The runtime's `ruby`

A program that starts `RbConfig.ruby` on its program file, to restart itself or run a sibling program, would get a bare Ruby without the app's gems. `ruby_main.c` calls `fledge_relaunch` first: when the first argument is a file that one of the app's programs runs, according to the `fledge.cfg` two folders up, it executes that program's launcher instead, with the rest of the arguments. Any other script, or an option before the script, runs as plain `ruby`. On Windows, `windows_relaunch.c` finds the launcher by a mark compiled into it, so that it runs no other program in the folder in the launcher's place.

## Exit statuses

| Status | Name | When |
| - | - | - |
| 66 | `FLEDGE_EXIT_NO_APP` | `fledge.cfg` or the program's file is missing, or `fledge.cfg` has no section for the program |
| 70 | `FLEDGE_EXIT_SOFTWARE` | anything else that stops the start: a damaged `fledge.cfg`, a missing file of Ruby's, Bundler failing to set up |
| 72 | `FLEDGE_EXIT_OSFILE` | a system library, typelib, or Visual C++ DLL the app needs is missing |

The phone runtimes use 66 and 70 with the same meanings.

## Traps

- **`fledge.cfg` has two readers.** `Assembly.launch_config` writes it, and `config.c` (and the phone runtimes) read it; `BuiltApp` reads it back for `--from`. A new key changes all of them, and an old launcher refuses an unknown key by design.
- **The launcher can't rely on Ruby until step 8.** Everything before runs as plain C, writes its messages to standard error (on Windows, through the console's wide-character API when there is one), and must not allocate Ruby objects.
- **Restoring the environment is Bundler's business.** The snippet in `bundler.c` uses Bundler's `EnvironmentPreserver` and its key list, and on Windows re-spells variables whose case Windows folded, so that a Bundler change to either is a launcher change.
- **The relaunch looks two folders up.** It assumes the runtime's layout, `PREFIX/bin/ruby` beside `PREFIX/fledge.cfg`, or a Mac bundle's `Contents/MacOS` beside `Contents/Resources`.

## What the launcher doesn't do

- Unpack anything, or mount a file system: it runs from the folder as it is.
- Choose a Ruby: it runs the runtime beside it, never one on `PATH`.
- Read `fledge.yml`, or anything of the project but the entry in `fledge.cfg`.
