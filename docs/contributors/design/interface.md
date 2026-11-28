# Interface: the command, fledge.yml, and the app model

This part is everything a developer touches: the `fledge` command, the project's configuration file, and the model the rest of Fledge builds from, a project with its programs and their identities.

## Where the interface is described

The command line is described twice. The code runs it, and `fledge --help` prints it; the Usage spec, [`docs/reference/fledge.usage.kdl`](../../reference/fledge.usage.kdl), specifies the same command line for people and for `usage`:

| To | Run |
| - | - |
| build a desktop app | `fledge build [PATH]` |
| write a phone's project | `fledge build ios [PATH]`, `fledge build android [PATH]` |
| run a program on a Simulator or device | `fledge test ios PROGRAM`, `fledge test android PROGRAM` |

A build takes `-o`/`--out`, `--sign`, `--sign-command`, `--notarize`, and `--from`, and a test `-o`/`--out` and `-d`/`--device`.

The configuration file is described the same way. `Config` reads `fledge.yml` (`Config::FILE`), which `lib/fledge/config.schema.json` describes, and [`docs/reference/fledge-yml.md`](../../reference/fledge-yml.md) documents for developers. In this document, the file and its entries go by that reference's names: `fledge.yml`, and its keys.

Each description is written in one place:

| What | Where | Read when fledge runs? |
| - | - | - |
| what the command accepts, and what it does | each command class's `Options.parse` in `lib/fledge/cli`, and `CLI` for the commands themselves | yes: this is the interface |
| what `fledge --help` prints | the header comment of `exe/fledge`, between the `####` and `###` lines | yes, as text: `CLI#help` prints it, and `CLI#usage` its `SYNOPSIS` section |
| the command line, as a Usage spec | `fledge.usage.kdl` | no: people read it, and `usage` renders it, lints it, and makes completions from it |
| what the configuration file accepts | `Config` and its value classes | yes |
| the schema of that file | `lib/fledge/config.schema.json` | no; `test/config_schema_test.rb` fails when it and `Config` disagree |
| the configuration file, for developers | `fledge-yml.md` | no |

`fledge --help` prints the help header as it is written, so a change to the command line the code runs changes the header in the same commit; `test/cli_test.rb` checks that the header lists every platform, its archive, and each exit status. Nothing checks the two references against the code, so a change to the interface changes them by hand. To add a flag to `fledge build`:

1. Parse it in `CLI::Build::Options`, with a test, and use it in `CLI::Build`.
2. Describe it in the help header of `exe/fledge`, so that `fledge --help` shows it.
3. Declare it in `fledge.usage.kdl`, under `cmd "build"`, and check the file with `usage lint`, which no gate runs.

A new configuration entry goes the same way: its value class under `Config` and its property in `config.schema.json`, with a test, then its entry in `fledge-yml.md`.

## The pieces

| Piece | Role |
| - | - |
| `exe/fledge` | the executable: it runs `Fledge::CLI` on `ARGV`, and its header comment, between the `####` and `###` lines, is the help text `--help` prints |
| `CLI` | dispatches the first word to a command class (`build` or `test`), prints help and the version, and turns a `UsageError` into status 2 with the usage |
| `CLI::Build` | the desktop build, and, given `ios` or `android` before the path, the phone's project: parses its options into an `Options` value, then drives the build ([architecture.md](architecture.md), "How a desktop build flows") |
| `CLI::Test` | runs a program on a phone: writes the project through `CLI::Build`, into `dist/test` or the folder given with `--out`, then hands it to `PhoneRun` ([phone-projects.md](phone-projects.md)) |
| `Config` | `fledge.yml`, read and validated into values: `Config` itself, and `Config::Program`, `FileAssociation`, `Linux`, `Macos`, `Windows`, and `Phone` for its nested mappings |
| `App` | a project: its root, its name, its Gemfile, its `Config`, and its programs, each an `App::Program` with an entry and an `Identity` |
| `Identity` | how one program presents itself: name, kind, identifier, version, publisher, copyright, icon, descriptions, homepage, and file associations, with the gemspec's values as defaults |
| `Icon` | an icon's base path, which answers each system's file, and refuses a missing one with the sizes that system takes |
| `Platform`, `MobilePlatform` | where an app runs; see [Platforms](#platforms) |

## Exit statuses and messages

Every command returns its status rather than exiting, so the CLI can be tested in-process with its streams passed in. The statuses are the ones both the help header and the Usage spec list: 0 for success; 1 for a `Fledge::Error`, whose message is printed one line at a time, each prefixed with the command (`fledge build: `, `fledge test: `); and 2 for a `UsageError`, printed with the usage. `fledge test` returns the program's status when it is between 0 and 255, and 1 otherwise.

A message is the developer's only guide when a build fails, so each says what is wrong in the developer's terms and what to do: which file, which value, the command to run, or the line to write. Parts below the CLI raise `Fledge::Error` with such a message, never a Ruby exception for a condition a developer can cause.

## Reading fledge.yml

`Config.load(root)` reads the project's configuration file, or returns `Config.none` when there is none. Reading is strict: an unknown key, a value of the wrong type, or a list where a single value belongs is an error that says which key is wrong and how to fix it, so that a typo fails the build instead of changing nothing. Each value class validates its mapping, and `Config` checks the rules between keys: that installers and file associations need a windowed program, that an `msix` installer needs a publisher, and that `kind`, `identifier`, and `icon` move into `programs` once there are any.

A `Config` holds what the file says, not defaults. Defaults that depend on more than the file, such as a name from the gemspec or the folder, are `App`'s and `Identity`'s to supply. Two kinds of accessor shape how other parts read it:

- **Per-system lists** (`system_libraries(os)`, `system_typelibs(os)`, `deb_depends(os)`, `carried_libraries(os)`) answer the platform's list, and an empty one on every other, so callers never test the platform themselves.
- **`for_program`** narrows a project's `Config` to one listed program, with that program's identity in the top-level places, for a build of that program alone.

## Resolving a project

`App.at(path)` does what a developer means by "build this":

- **The root** is the nearest folder at or above the path that holds a `Gemfile`, `gems.rb`, `fledge.yml`, or a gemspec, searching no higher than a folder with `.git`. A root at the home folder is refused, since the app would ship it whole.
- **The gemspec,** when the root has exactly one, is loaded as Bundler loads it, after evaluating the Gemfile, for the defaults it gives: the name, version, authors, and executables. A gemspec with no Gemfile is refused, since Fledge ships only what Bundler locks.
- **The programs** are the file given, or for a folder its `main.rb` or the gemspec's one executable, or every program `programs` lists when `fledge.yml` has them. A file `programs` lists builds that program alone.
- **Names** come from `fledge.yml`, the gemspec, or the folder, camelized as Bundler names a gem's module, and are refused when some system's file names can't hold them.
- **The main program** is the windowed one, or else the first. It gives the app its installers and, on macOS, its bundle.

`App#entries` walks the project for Assembly, leaving out `NEVER_SHIPPED` (`.git`, `.bundle`, `vendor/bundle`, `vendor/cache`) and any folder a `CACHEDIR.TAG` marks, which is how earlier builds in `dist` stay out.

## Platforms

`Platform` (the desktops) and `MobilePlatform` (`ios`, `android`) are different classes that answer one role, so `Bundle`, `AppGems`, and the linkage checks take either: `windows?`, `lockfile_names`, `force_ruby_platform?`, and `to_s`. Beyond that role they differ. A `Platform` answers for its OS, processor, archive format, executable names, and oldest macOS or glibc; `Platform.local` maps the running Ruby's `Gem::Platform` to one, and refuses a computer Fledge has no runtime for. A `MobilePlatform` answers which desktops can write its project, and which gem platforms its extensions compile for.

The CLI never takes a desktop platform from the developer: a build is always `Platform.local`. The `--target` option of earlier versions is refused with that reason.

## Traps

- **A help header missing its markers or its `SYNOPSIS` is an error,** not an empty page: `CLI#help` and `CLI#usage` raise when they can't find them.
- **`ios` and `android` are words, not paths, to `fledge build`.** `CLI::Build::Options` reads the first of them before any path as the phone, so a project folder named `ios` has to be given as `./ios`.
- **The Ruby a build runs on must be the runtime's minor version.** `CLI::Build` compares `RUBY_VERSION` with the runtime's before it resolves a gem: a lockfile resolved on another Ruby, or a gem compiled for one, would not match the app's.
- **`--out` may not be the project.** The app copies the project, so an output inside it would copy earlier builds; `--out .` is refused, and `dist` is marked with a `CACHEDIR.TAG` so that it skips itself.
- **Arguments are values.** Command classes copy `argv` before parsing, and never change the caller's.

## What this part doesn't do

- Read any configuration file but the project's. Every other setting comes from an environment variable, and the Usage spec's `config` block lists the ones a developer sets: where runtimes come from and whether they are checked, the cache folder, Windows' signing command, and the Android SDK and NDK.
- Prompt. Every input has a flag or a `fledge.yml` key, so a build runs the same in a terminal and in CI.
