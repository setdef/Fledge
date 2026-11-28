# What a built app holds, and how it starts

This page describes the app `fledge build` writes: its files, the `fledge.cfg` its launcher reads, what the launcher does before your program runs, and the exit statuses a person can meet. It's for checking a build, supporting the people who run your app, and knowing what they receive.

## Files

`fledge build` writes, in `dist` (or the folder you give `--out`):

| File | What it is |
| - | - |
| `NAME-PLATFORM/` | the app folder |
| `NAME-PLATFORM.tar.gz`, or `.zip` on Windows | the app folder, packed |
| `NAME-PLATFORM.dmg`, `-setup.exe`, `.AppImage`, `.deb`, `.msix` | each installer a windowed app gets |
| each of those `.sha256` | the file's SHA-256 and name, as `sha256sum -c` reads them |
| `CACHEDIR.TAG` | marks the folder as build output, so that backups and later builds skip it |

A `.tar.gz` records no owner of yours: each entry belongs to user and group 0.

## The app folder

On Linux, for an app named `greet`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```
greet-x86_64-linux/
├── greet          the launcher, the program a person runs
├── fledge.cfg     what the launcher runs
├── app/           a copy of the project, with its Gemfile and .bundle/config
├── bin/           Ruby, and the gems' executables
├── include/       Ruby's headers
├── lib/           Ruby's library, its standard library, and the gems
├── libexec/
└── notices/       the license and notice of everything in the runtime
```
<!-- SPDX-SnippetEnd -->

- **Windows** has `greet.exe` as the launcher, and Ruby in a `ruby` folder. A windowed program's launcher is a Windows GUI program, so it opens no console window.
- **macOS**, for a windowed app, holds `NAME.app`, a bundle whose `Contents/MacOS/NAME` is the launcher, and whose `Contents/Resources` holds `fledge.cfg`, `app`, and the runtime. A console app's folder is laid out as on Linux.
- **Linux**, for a windowed app, adds `IDENTIFIER.desktop`, its icons under `share/icons/hicolor`, and the definitions of the file types it defines under `share/mime/packages`.
- **Several programs** put one launcher in the folder for each program, beside the same `app` and runtime.
- **`build-tools`** adds a `tools` folder.

The app holds Ruby's headers so that a program can compile with `mkmf` where the computer has a compiler, as it can under `ruby`. fledge leaves out the rest of what the runtime holds for compiling gems.

## fledge.cfg

The launcher reads `fledge.cfg` beside it to learn what to run. fledge writes it; you never need to edit it, and a launcher refuses one that is damaged.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```
# Written by fledge build 0.17.0 for x86_64-linux: what this app's program runs.
# Needs glibc 2.28 or newer, the newest any of its compiled files needs.
entry = main.rb
gemfile = Gemfile
```
<!-- SPDX-SnippetEnd -->

The comment lines say which Fledge wrote it, for which platform, and, on Linux, the oldest glibc the app runs on. Each other line is `key = value`:

| Key | Value |
| - | - |
| `entry` | the program's file, in `app` |
| `gemfile` | the project's `Gemfile`, in `app`, when it has one |
| `bundler` | the Bundler version the app runs with, when the lockfile lists one other than the runtime's |
| `identifier` | the program's `identifier` |
| `system_libraries` | the Linux libraries the app checks for at start, separated by spaces |
| `system_typelibs` | the GObject introspection typelibs the app checks for at start |
| `visual_c_runtime` | the Visual C++ runtime DLLs a `central` app checks for at start |

An app of several programs gives each program a section, `[NAME]`, with its `entry` and `identifier`; the launcher reads the section named for its own file name, ignoring case.

## What the launcher does

When a person runs the app, the launcher:

1. finds the folder it is in, through any links, and refuses to run from a folder named `bin` or `lib`;
2. reads `fledge.cfg`;
3. on Linux, checks that the computer has each `system_libraries` library and `system_typelibs` typelib, by loading it;
4. on Windows, checks for each `visual_c_runtime` DLL in System32, gives the process the app's identifier as its AppUserModelID, so that the taskbar groups it with its shortcut, and limits where Windows looks for DLLs to the app's Ruby and the system;
5. on macOS, for an app that opens files, collects the paths of the files Finder opened it with;
6. sets aside every environment variable that would change Ruby, RubyGems, or Bundler: those whose names start with `RUBY`, `GEM_`, `BUNDLE_`, or `BUNDLER_`, `GEMRC`, and `RI_FORCE_PATH_FOR_DLL`;
7. outside Windows, chooses a UTF-8 locale when no locale is set, or the C locale is, so that Ruby's default encoding is UTF-8;
8. starts Ruby on `app/ENTRY`, with the person's arguments after it, and with `RUBYOPT` off;
9. puts the runtime's `bin` first on `PATH`, so a program that runs `ruby` or a gem's executable gets the app's;
10. when the app has a `Gemfile`, sets up its gems as `bundle exec` does, from the app's `Gemfile`, lockfile, and `.bundle/config`, frozen;
11. gives the variables it set aside back to the program's `ENV`, as `bundle exec` leaves a program's environment, so that the program's child processes see the person's Ruby settings, and the app's gems never did.

Then your program runs, as `ruby main.rb` would run it. Ctrl-C and a hangup end the app as they end `ruby`, and the app's exit status is your program's.

### Ruby run from inside the app

A program that starts `ruby` (`RbConfig.ruby`) on one of the app's programs, such as to restart itself, gets that program's launcher, with its gems set up again. `ruby` run on any other script, or with an option before the script, runs as plain Ruby.

## Exit statuses

Beside your program's statuses, a person can meet these, each with a message on standard error that starts with the program's name:

| Status | Meaning | What to tell them |
| - | - | - |
| 66 | The app is incomplete: `fledge.cfg` or the program's file is missing, or `fledge.cfg` has no section for a program of the launcher's name. | Unpack the archive again, whole. |
| 70 | The app could not start: `fledge.cfg` is damaged, a file of Ruby's is missing, the app's folder is named `bin` or `lib`, or Ruby, RubyGems, or Bundler failed to start. | Read the message; unpack the archive again into a new folder. |
| 72 | The computer lacks something the app needs from its system: a Linux library or typelib, or Microsoft's Visual C++ Redistributable. | Install what the message says, from the distribution's packages or Microsoft's link in the message. |

## Notices

The `notices` folder holds the licenses and notices of everything in the runtime: Ruby, its libraries, Fledge's launcher, and the tools it carries. Its notices list the runtime alone; your app's code and gems are yours to license, and to give notices for.

For each component under the LGPL, the notices say how to replace it, and where Fledge's release publishes its source. That release also publishes each runtime's software bill of materials, as SPDX.
