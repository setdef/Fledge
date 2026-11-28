# Ship several programs in one app

A project can ship more than one program in one app folder, such as a game and its server, or a desktop app and its command line. They share one runtime, one copy of the project, and one set of gems, so the app is barely larger than one program's.

## List the programs

Name each program in `fledge.yml` under `programs`, by its file in the project:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Rocket Run
version: "0.4.0"
publisher: Example, Inc.

programs:
  - path: game/main.rb
    kind: windowed
    identifier: com.example.RocketRun
    icon: art/icon
  - path: bin/rocket-run-server
```
<!-- SPDX-SnippetEnd -->

Then build the project:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
```
<!-- SPDX-SnippetEnd -->

The app folder now holds a program for each: `Rocket Run`, named for the project because it is windowed, and `rocket-run-server`, named for its file. Each is Fledge's launcher, so each starts its own Ruby, with the gems set up from the one `Gemfile`.

Give a program another name with `name`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
programs:
  - path: bin/rocket-run-server
    name: rr-server
```
<!-- SPDX-SnippetEnd -->

## The rules

- **One windowed program.** A project has at most one windowed program, and it is the app's main program: its installers install the whole folder and start that program, and on macOS its bundle holds the others. Build a second windowed app as a project of its own.
- **Identity per program.** `kind`, `identifier`, and `icon` are set on each program, and fledge refuses them at the top level of `fledge.yml` once it has `programs`. The rest, `name`, `version`, `publisher`, `installers` and so on, stay the project's.
- **Names and identifiers are unique.** No two programs may share a name or an identifier, ignoring case, since some systems ignore case in file names.
- **Files must exist.** fledge refuses a program whose file is not in the project.

## On macOS

The windowed program is the app's bundle, `Rocket Run.app`. The console programs live inside it, in `Contents/MacOS`, so that one signature covers them all, and the app folder has a link to each beside the bundle, so that `./rocket-run-server` works from a terminal. With no windowed program, each program is a file in the app folder, as on Linux.

## Build one program alone

To build one of the listed programs as an app of its own, name its file:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build bin/rocket-run-server
```
<!-- SPDX-SnippetEnd -->

That program alone goes in the app, with its own `kind`, `identifier`, and `icon`, and a file that `fledge.yml` does not list is refused. A folder means every program.
