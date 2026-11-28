# Differences from `ruby main.rb`

An app's Ruby behaves as it does under `ruby main.rb`, or `bundle exec` for a project with a `Gemfile`: the same requires, globals, `ENV`, standard library, and gems. This page lists every difference your program's code can observe, on each platform, with what it sees, where it holds, and what to do about it. Each comes from what the app needs on the computer of the person who runs it, from the build of Ruby a runtime is made from, or from what a phone forbids. Any difference this page doesn't list is a bug in Fledge: report it on [the Fledge forum](https://forum.setdef.com/c/fledge), with the code that shows it.

"`ruby main.rb`" here means your program run from your project's folder, by the Ruby you build with, in a terminal with a UTF-8 locale. The examples use the app `greet` from [the tutorial](../tutorial.md), built on x86-64 Linux into `dist/greet-x86_64-linux`.

## Summary

| Difference | What your code sees in the app | Where |
| - | - | - |
| [The program's path](#the-programs-path) | `$0`, `__FILE__`, and `$PROGRAM_NAME` are absolute paths | every platform |
| [The person's Ruby settings](#the-persons-ruby-settings) | `RUBYOPT`, `RUBY_YJIT_ENABLE`, and the like are in `ENV` but changed nothing at boot, so `$VERBOSE` is `false` under `RUBYOPT=-W0` | desktops |
| [The gem folders](#the-gem-folders) | `Gem.path` and `Gem.dir` name the runtime's gem folder alone | desktops |
| [Fledge's RubyGems defaults](#fledges-rubygems-defaults) | `$LOADED_FEATURES` lists `rubygems/defaults/operating_system.rb` | macOS, Linux, phones |
| [`ruby` and gems' commands on `PATH`](#ruby-and-gems-commands-on-path) | `ENV["PATH"]` starts with the app's Ruby's `bin` folder | desktops, Android |
| [A Ruby started on the app's program](#a-ruby-started-on-the-apps-program) | `RbConfig.ruby` run on the app's program starts the app again, through its launcher | desktops |
| [The locale](#the-locale) | with no locale, or the C locale, the default encodings are UTF-8, not US-ASCII | macOS, Linux, phones |
| [bootsnap and msgpack](#bootsnap-and-msgpack) | neither gem is installed | macOS, Linux |
| [Bundler's settings](#bundlers-settings) | `Bundler.reset!` brings back the app's frozen settings, and `bundler/feature_flag.rb` never loads | apps with a `Gemfile` |
| [The gemspec](#the-gemspec) | the project's gemspec is the evaluated one, and none of its code runs | apps with a gemspec |
| [`PKG_CONFIG_PATH`](#pkg_config_path) | Ruby's `lib/pkgconfig` is in it once, not twice | macOS, glibc Linux, apps with a `Gemfile` |
| [The ANSI code page](#the-ansi-code-page) | the process's ANSI code page is UTF-8 | Windows |
| [The locale of a windowed program](#the-locale-of-a-windowed-program) | `Encoding.find("locale")` is UTF-8 | Windows, windowed programs |
| [Bundler's variables spelled otherwise](#bundlers-variables-spelled-otherwise) | `ENV` spells `BUNDLE_GEMFILE` as Bundler does | Windows, apps with a `Gemfile` |
| [RubyInstaller's start-up](#rubyinstallers-start-up) | Ruby's DLL search leaves out `RUBY_DLL_PATH` and MSYS2, and RubyGems sets no `GEM_HOME` | Windows |
| [The AppUserModelID](#the-appusermodelid) | the process has the app's identifier as its AppUserModelID | Windows |
| [Documents opened on macOS](#documents-opened-on-macos) | `ARGV` ends with the documents the app was opened with | macOS, windowed apps that open files |
| [On both phones](#on-both-phones) | another `RUBY_PLATFORM`, `$stdout` writing each line as printed, and more | iOS, Android |
| [On iOS](#on-ios) | no program starts, and Ruby has no JIT | iOS |
| [On Android](#on-android) | `HOME` is set, and no file the app writes runs | Android |

## Every platform

### The program's path

`$0`, `__FILE__`, and `$PROGRAM_NAME` hold the absolute path of the program in the app, such as `/tmp/elsewhere/greet-x86_64-linux/app/main.rb`, where `ruby main.rb` gives `"main.rb"`, as you typed it. In an app with a `Gemfile` whose program is `exe/greet`, `bundle exec ruby exe/greet` gives `"exe/greet"`, and the app gives the absolute path. In a windowed macOS app, the path is inside the bundle, under `Contents/Resources/app`. A person may start the app from any folder, so the launcher runs the program by its absolute path, as `ruby /path/to/app/main.rb` would.

`__dir__`, `__FILE__ == $0`, and every path Ruby builds from them hold as under `ruby main.rb`.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# Wrong: true under `ruby main.rb` only.
puts "usage: main.rb NAME" if $0 == "main.rb"

# Right: the program's own name, wherever it runs.
puts "usage: #{File.basename($0)} NAME" if ARGV.empty?
```
<!-- SPDX-SnippetEnd -->

What to do: compare `__FILE__` with `$0` to tell whether a file is the program, take `File.basename($0)` for its name, and find the project's files from `__dir__`.

## Every desktop

### The person's Ruby settings

The launcher sets aside, before Ruby starts, every environment variable whose name starts with `RUBY`, `GEM_`, `BUNDLE_`, or `BUNDLER_`, and `GEMRC` and `RI_FORCE_PATH_FOR_DLL`, on Windows in any case. It gives them back to `ENV` before your program's first line. So these variables are in `ENV`, with the person's values, and every program your app starts receives them, but none of them changed how the app's Ruby, RubyGems, or Bundler started:

- `RUBYOPT` and `RUBYLIB` add no option, library, or folder. With `RUBYOPT=-W0`, `ruby main.rb` sets `$VERBOSE` to `nil`, and the app leaves it `false`.
- What Ruby reads only as it boots, such as `RUBY_YJIT_ENABLE`, `RUBY_GC_HEAP_GROWTH_FACTOR`, and `RUBY_THREAD_VM_STACK_SIZE`, has no effect.
- `GEM_HOME`, `GEM_PATH`, and the person's `BUNDLE_` settings change no gem the app loads (see [The gem folders](#the-gem-folders)).

What RubyGems and Bundler read later, after your program starts, reaches them as under `ruby main.rb`.

What to do: set in your code what you'd have set in the environment, such as `RubyVM::YJIT.enable` or `$VERBOSE = nil`. To honor a person's setting, read it from `ENV` yourself. A program your app starts sees the person's settings; to keep it apart from them, start it with those variables set to `nil`, as in `system({"RUBYOPT" => nil}, "ruby", "worker.rb")`.

### The gem folders

`Gem.dir` is the runtime's gem folder, and `Gem.path` holds it alone: never the person's `GEM_HOME` or `GEM_PATH`, nor `Gem.user_dir` (under `~/.gem`, or under `XDG_DATA_HOME`). So a gem the person installed with another Ruby never shadows one of the app's. `gem install` run from the app installs into the runtime's gem folder.

In an app with a `Gemfile`, the gems' entries in `$LOAD_PATH` and `$LOADED_FEATURES`, and the values Bundler puts in `ENV` (`GEM_HOME`, the bundle's folder at the front of `PATH`, `BUNDLE_BIN_PATH`, `BUNDLER_SETUP`, `RUBYLIB`, and `RUBYOPT`), hold paths in the runtime's gem folder, where under `bundle exec` they hold paths in your `GEM_HOME`. The same gems load, in the same order, from each.

What to do: find a gem's files with `Gem.loaded_specs["rainbow"].full_gem_path` or `Gem::Specification.find_by_name`, never by building a path from `GEM_HOME`.

### Fledge's RubyGems defaults

Each runtime carries `rubygems/defaults/operating_system.rb`, the file RubyGems loads as it starts so that whoever packages Ruby can change its defaults. Fledge's keeps `Gem.default_path` to the runtime's gem folder. On macOS, Linux, iOS, and Android, `$LOADED_FEATURES` lists it, where it doesn't under the Ruby you run, which ships no such file. On Windows it takes the place of RubyInstaller's file of the same name (see [RubyInstaller's start-up](#rubyinstallers-start-up)).

The file also prepends an anonymous module to the singleton class of `Gem::BUNDLED_GEMS`, and, the first time a bundled gem that `Gemfile.lock` doesn't lock activates (as `binding.irb` activates `irb`), one to `Bundler`'s singleton class. They let that gem activate in the app's frozen bundle as it does under `bundle exec`. Each shows in `ancestors` of the singleton class, and defines no constant.

What to do: nothing, unless your code lists `$LOADED_FEATURES` or a singleton class's `ancestors` and expects an exact match.

### `ruby` and gems' commands on `PATH`

Before your program runs, the launcher puts the folder of the app's `ruby` and its gems' commands first on `PATH`, as your shell has the Ruby you run first. So `system("rake")`, backquotes, `Open3`, `ruby -S rake`, and `system("ruby", "worker.rb")` run the app's, never a Ruby the person happens to have. In an app with a `Gemfile`, Bundler puts the bundle's folder before it, as under `bundle exec`, and `Bundler.original_env`, `with_original_env`, and `with_unbundled_env` give the person's `PATH` with the app's Ruby first. The rest of the person's `PATH` stays, in its order.

What to do: run Ruby and your gems' commands by name, as you would under `ruby main.rb`. Android does the same; iOS starts no program (see [On iOS](#on-ios)).

### A Ruby started on the app's program

The runtime's `ruby`, whose path `RbConfig.ruby` returns, hands a script that is one of the app's programs to that program's launcher. So `exec RbConfig.ruby, $0, *ARGV` restarts the app as it first started, with the person's Ruby settings set aside again and the app's gems set up again, where plain `ruby` would boot with the person's `RUBYOPT` and without Bundler. The hand-off happens only when the program's path comes first: with an option before it, as in `system(RbConfig.ruby, "--yjit", $0)`, or with any other script, the runtime's `ruby` runs as plain `ruby` does, with the person's settings.

On Windows, as under `ruby.exe`, the restarted app is a new process with a new `Process.pid`, and a windowed app restarted this way opens a console while it runs, since `ruby.exe` is a console program.

What to do: restart with `exec RbConfig.ruby, $0, *ARGV`. To start Ruby with an option, turn the option on in your code instead, as `RubyVM::YJIT.enable` does for `--yjit`.

### The locale

On macOS and Linux, when neither `LC_ALL` nor `LC_CTYPE` is set and the environment's locale is C or POSIX, `ruby` takes US-ASCII as the encoding it reads text, paths, and arguments in. The launcher, and the runtime's `ruby`, choose the first of `C.UTF-8`, `C.utf8`, `UTF-8`, and `en_US.UTF-8` the computer has, so `Encoding.default_external`, `Encoding.find("locale")`, and `Encoding.find("filesystem")` are UTF-8. A double-click, a service manager, and `env -i` start a program with no locale. Without the change, Bundler, and any code that joins or matches the app's paths, would fail when the app sits in a folder whose name is outside ASCII, such as the home folder of a person named José.

Fledge adds nothing to `ENV`, so a program the app starts that isn't Ruby sees the person's locale. A `LC_ALL` or `LC_CTYPE` the person set, `C` included, is kept as `ruby` keeps it. On a computer with none of those four locales, the app stays in C, as `ruby` does.

The phone runtimes make the same choice, since iOS and Android start an app with no locale; there your program reads UTF-8, as in your terminal.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# main.rb
puts Encoding.default_external
```
<!-- SPDX-SnippetEnd -->

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ env -i "$(command -v ruby)" main.rb
US-ASCII
$ env -i dist/greet-x86_64-linux/greet
UTF-8
$ env -i LC_ALL=C dist/greet-x86_64-linux/greet
US-ASCII
```
<!-- SPDX-SnippetEnd -->

What to do: nothing, for a program that reads and writes UTF-8. A program that needs the C locale's US-ASCII sets `LC_ALL=C` or `LC_CTYPE=C` for itself, or opens its files with an explicit encoding.

### bootsnap and msgpack

The macOS and Linux runtimes are built from Rubies that install two gems a standard Ruby 4.1 doesn't, bootsnap and msgpack, and Fledge removes both. If the Ruby you run is one of those builds (jdx/ruby's, or rv-ruby's), `require "bootsnap"` and `require "msgpack"` succeed under `ruby main.rb` without a `Gemfile` and raise `LoadError` in the app.

What to do: add the gem to the `Gemfile` when your program needs it, as you would for any Ruby.

## Apps with a Gemfile

### Bundler's settings

fledge writes the app's `.bundle/config`, which sets `frozen`, `path.system`, `auto_install` off, and the groups you build with. The launcher has Bundler set up the gems frozen, so Bundler never writes `Gemfile.lock`, even in a folder the person can't write, and then makes Bundler's settings again without `frozen`. So your program finds `Bundler.frozen_bundle?` and `Bundler.settings[:frozen]` as `bundle exec` gives them in a project with no such setting. Two things differ:

- After `Bundler.reset!`, or in a Ruby the app starts that requires `bundler/setup`, Bundler reads the app's `.bundle/config` again, and the bundle is frozen.
- `bundler/feature_flag.rb` never loads, since `path.system` answers the question `bundle exec` asks the feature flags, so `$LOADED_FEATURES` lacks it.

The person's `~/.bundle/config`, and their `BUNDLE_` variables, never change which groups or gems the app sets up.

What to do: don't change the bundle at run time. `Bundler.definition.lock` tries to write `Gemfile.lock`, as under `bundle exec`, and raises `Bundler::PermissionError` in a folder the person can't write.

### The gemspec

A gemspec in your project ships evaluated, as Bundler ships a git gem's, so a gemspec that lists its files with `git ls-files` needs no git where the app runs. Before your program's first line, Bundler loads each file of your project that the gemspec required or loaded when `fledge build` evaluated it, such as `lib/greet/version.rb`, as `bundle exec` does. Nothing else the code in the gemspec does happens in the app:

- a constant it defines in the `.gemspec` file itself;
- a change it makes to `$LOAD_PATH`, `ENV`, or a global variable;
- code it evaluates from a string;
- a file outside your project that it loads.

What to do: put what your program needs in a file the gemspec requires, as the gemspec that `bundle gem` writes requires `version.rb`.

### `PKG_CONFIG_PATH`

On macOS and glibc Linux, the Ruby a runtime is built from puts its `lib/pkgconfig` first in `PKG_CONFIG_PATH` each time it starts. `bundle exec` starts Ruby twice, once for `bundle` and once for your program, so `ENV["PKG_CONFIG_PATH"]` there starts with that folder twice. The app starts Ruby once, so it holds the folder once, then the rest of the value. pkg-config searches the same folders in the same order either way.

What to do: nothing, unless your code compares `PKG_CONFIG_PATH` with an exact value.

## Windows

### The ANSI code page

A Windows function whose name ends in `A` reads a narrow (`char *`) string in the process's ANSI code page. The app's launcher, and the runtime's `ruby.exe` and `rubyw.exe`, declare UTF-8 as that code page in their manifest, where RubyInstaller's `ruby.exe` keeps the system's, such as Windows-1252 on an English or Western European Windows. Your code can see it in three places:

- A gem that hands Ruby's UTF-8 paths to an `A` function finds a file under a folder whose name is outside ASCII, such as `C:\Users\José\`. The ffi gem opens a DLL with `LoadLibraryExA`, so a gem that loads its DLL through ffi loads it there in the app, and fails under `ruby.exe` with "The specified module could not be found".
- With `TZ` set to a zone whose name is outside ASCII, `Time#zone` is a UTF-8 string, not Windows-1252.
- A C extension's `fopen`, and the C runtime's other narrow functions, read UTF-8.

`Encoding.default_external` and `Encoding.find("filesystem")` are UTF-8 under `ruby.exe` already, and don't change. A console program's `Encoding.locale_charmap` is the console's code page, as under `ruby.exe`, and the console's code page stays as it was. A Ruby the app starts through `RbConfig.ruby` has the app's code page.

What to do: nothing; a gem that fails under `ruby.exe` in such a folder works in the app. Draw text with GDI's `W` functions: GDI's `A` functions keep the system's code page.

### The locale of a windowed program

With no console, as a windowed program starts, Ruby takes its locale from the ANSI code page. So in a windowed app, `Encoding.locale_charmap` is `"CP65001"` and `Encoding.find("locale")` is UTF-8, where `rubyw.exe` gives the system's code page, such as `"CP1252"` and Windows-1252. `rubyw.exe` loads that code page's encoding as it starts, such as `enc/windows_1252.so`, and `$LOADED_FEATURES` in the app lacks it, since UTF-8 is built into Ruby.

What to do: name the encoding you mean, such as `Encoding::Windows_1252`, when your program reads text in the system's code page.

### Bundler's variables spelled otherwise

Windows ignores case in a variable's name, so a person may spell Bundler's `BUNDLE_GEMFILE` as `bundle_gemfile`. `bundle exec` keeps their spelling in `ENV` and in `Bundler.original_env`. In an app with a `Gemfile`:

- `ENV` spells it `BUNDLE_GEMFILE`, naming the app's `Gemfile`, and so does the environment of every program the app starts;
- `Bundler.original_env` and `Bundler.unbundled_env` hold no `bundle_gemfile`, before a restart or after it.

Bundler reads its settings by Bundler's spelling, so with the person's, a Ruby your app starts with `bundler/setup` would set up whichever `Gemfile` is set in the person's Bundler settings. Every other variable keeps the person's spelling, as under `bundle exec`.

What to do: read a variable with `ENV["BUNDLE_GEMFILE"]`, which ignores case on Windows, rather than look for its name among `ENV.keys`.

### RubyInstaller's start-up

The Windows runtimes' Ruby is RubyInstaller's, whose `ruby.exe` runs RubyInstaller's start-up as RubyGems loads. The app loads the same library, so `RubyInstaller` and `Win32` are defined and `$LOADED_FEATURES` lists the same files as under `ruby.exe`, but it does only part of what the start-up does:

- Windows looks for a DLL that's loaded by name in System32 and Ruby's folders. RubyInstaller's start-up also adds each folder of `RUBY_DLL_PATH`, and the `bin` folder of an MSYS2 it finds; the app adds neither.
- RubyGems writes nothing into the app's gem folder, sets no `GEM_HOME`, and creates no `%ProgramData%\gemrc`.

What to do: carry in the app every DLL your program loads, and load one with Fiddle or ffi by its absolute path.

### The AppUserModelID

When `fledge.kdl` has an `identifier`, the launcher gives the process that identifier as its explicit AppUserModelID before your program runs, so that the taskbar groups the app's windows with its shortcut. `ruby.exe` sets none.

What to do: nothing.

## macOS

### Documents opened on macOS

A double-click on a document, a drop on the app's icon, and `open -a APP FILE` start a macOS app with the document's path in an Apple event, not on its command line. When Launch Services starts a windowed app that opens files (see [Open files and folders](../how-to/file-associations.md)), the launcher takes that first event before Ruby starts and puts each path at the end of `ARGV`, after the arguments it was given, as `ruby main.rb ARGS FILE` would have them. A folder is a path like a file's. Each path is spelled as the file system stores it, so a name with accents arrives decomposed.

Your GUI library doesn't receive that first event: SDL3 sends no `SDL_EVENT_DROP_FILE` for it. A document opened while the app runs reaches the GUI library's event loop as without Fledge, and not `ARGV`.

The launcher waits up to 15 seconds for the event. When none comes, it prints a line on standard error that says so, and starts your program with the arguments it was given.

What to do: read the documents the app was opened with from `ARGV`, on every desktop, and those opened later from your GUI library's events.

## On both phones

These hold on iOS and Android, beside [The locale](#the-locale). The first four come from Fledge's phone runtimes; the last two are what each phone's system does to every app.

| What differs | What your code sees | What to do |
| - | - | - |
| The platform | `RUBY_PLATFORM` is `arm64-darwin` on iOS, and `aarch64-linux-android` or `x86_64-linux-android` on Android. `RUBY_DESCRIPTION` ends with it, and the folders of Ruby's platform-specific files in `$LOAD_PATH` and `$LOADED_FEATURES` are named for it. | Compare `RUBY_PLATFORM` with these names to tell a phone from a desktop. |
| Standard output | `$stdout`, a pipe to the system's log, writes each line as it's printed, where `ruby main.rb` buffers a pipe until the buffer fills or the program ends. `$stdout.sync` and `$stdout.tty?` stay `false`, as under `ruby main.rb` with its output to a pipe. | Nothing. A Ruby your Android app starts buffers its pipe as on a desktop. |
| Certificates | After `require "openssl"`, `ENV["PORTABLE_RUBY_SSL_CERT_FILE"]` holds the path of the certificates the runtime carries, `libexec/cert.pem`. | Nothing: the runtime's OpenSSL reads them. |
| Gems' extensions linked into the app | An extension fledge links into the app (every gem's extension on iOS, and on Android one that a Rakefile or Rust builds) is recorded in `$LOADED_FEATURES` as its feature, `GEM/GEM.so` for a gem's `GEM/GEM` extension, where a desktop records its file's absolute path. Ruby's extensions, and the bundled gems', are files at a desktop's paths. | Nothing, unless your code reads an extension's path from `$LOADED_FEATURES`. |
| The working folder and standard input | `Dir.pwd` is `/`, and `$stdin` is at its end. | Find files from `__dir__`, `Dir.home`, or `Dir.tmpdir`, and take input through the app's interface. |
| The background | The system may stop the app without running its `at_exit` blocks. | Save what matters as you go. |

## On iOS

Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#2.5.2), 2.5.2, keep an app to its bundle and its container, and forbid it to download, install, or run code that adds to or changes its features. Apple documents compiling code at run time only for a browser's web content extension ([Protecting code compiled just in time](https://developer.apple.com/documentation/browserenginekit/protecting-code-compiled-just-in-time)).

| What differs | What your code sees | What to do |
| - | - | - |
| Starting a program | `Process.spawn`, backquotes, and `IO.popen` raise `Errno::EPERM` on a device and `Errno::ENOENT` in the Simulator, and `system` returns `nil`. | Do the work in the app's process, with a Ruby library or a gem's C extension. |
| `RbConfig.ruby` | It returns where the runtime's `ruby` would be, and no file is there, since iOS's Ruby is a library inside the app. `exec RbConfig.ruby, $0` fails. | Call `load` or `require` in the same process. |
| The JIT | Ruby is built without YJIT and ZJIT: `RubyVM::YJIT` and `RubyVM::ZJIT` aren't defined, and `RbConfig::CONFIG["YJIT_SUPPORT"]` and `["ZJIT_SUPPORT"]` are `"no"`. | Turn one on only where it's defined: `RubyVM::YJIT.enable if defined?(RubyVM::YJIT)`. |
| The stack limit | The main thread, where Ruby runs, has a 64 MB stack, from a linker flag in Fledge's iOS project, and `Process.setrlimit(:STACK, ...)` raises `Errno::EINVAL`. | Leave the stack limit as it is. |
| The bundle | On a device, the app's bundle can't be written to; in the Simulator it can. | Write under `Dir.home` or `Dir.tmpdir`. |
| Users and groups, in the Simulator | The app runs as your Mac's user, whom the Simulator's user database lacks: `Etc.getpwuid(Process.uid)` raises `ArgumentError`, `Process.groups` raises `Errno::EINVAL`, and `File.grpowned?` is true only for a file of the app's primary group. | Don't look the app's user up with `Etc`. |

## On Android

Android 10 took away an app's permission to run files in its home folder: an app that targets Android 10 or later "cannot invoke `execve()` directly on files within the app's home directory", as Android's [behavior changes for Android 10](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission) say.

| What differs | What your code sees | What to do |
| - | - | - |
| `HOME` | Android gives an app no `HOME`, so the runtime sets it to the app's files folder: `Dir.home` is a folder the app may write, and a Ruby the app starts inherits it. | Keep the app's files under `Dir.home`. |
| Files the app writes | Running one, such as a script in `Dir.tmpdir`, raises `Errno::EACCES` from `Process.spawn`, and `system` returns `nil`. The system's programs, and the app's `ruby`, run. | Hand the script to the program that reads it: `system("sh", path)` or `system(RbConfig.ruby, path)`. |
| Gems' commands | Each command in the app's `bin` folder is a link to the runtime's `ruby` program, which runs RubyGems' script for it. `system("rake")`, `ruby -S rake`, and `load` work as on a desktop, but `File.read(File.join(Gem.bindir, "rake"))` reads the program's bytes. | Run a command by its name, and read a gem's script from the gem, with `Gem.loaded_specs["rake"].bin_file("rake")`. |
| `exec` | `exec RbConfig.ruby, $0` replaces the app's process, Java and all, and Android ends the app. `system` and `spawn` start Ruby in a separate process without Java. | Start Ruby with `system` or `spawn`. |
| ZJIT | `RubyVM::ZJIT.enabled?` is `false` and `RbConfig::CONFIG["ZJIT_SUPPORT"]` is `"yes"`, where a desktop Ruby built without ZJIT, such as jdx/ruby's, lacks `RubyVM::ZJIT`. YJIT and ZJIT are each off until your program turns one on. | Test with `defined?(RubyVM::ZJIT)` before you turn it on. |
| `/dev` | `Dir.children("/dev")` raises `Errno::EACCES`. | Don't list `/dev`. |
| Time zones | There are no `right/` zones, so `TZ=right/UTC` is UTC, which counts no leap second. | Don't rely on a `right/` zone. |
| The build's tools | `RbConfig::CONFIG["AR"]` and `["STRIP"]` hold the paths of the Android NDK's tools on the computer that built the runtime, which the phone lacks. | Compile extensions on your computer, as fledge does when it writes the project. |
