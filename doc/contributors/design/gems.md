<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# How fledge build Reads and Ships an App's Gems

This document says how `fledge build` turns a project's Gemfile and lockfile into the gems a desktop app ships: what it checks, which build of each gem it takes, where it fetches it, how it installs, compiles, and checks it, and what it writes so that the app's Bundler sets up the same gems. The developer's view, with the commands to run, is [Gems in a Fledge app](../../gems.md). The decisions behind it are ADR 005 (the program and its project), ADR 006 (compiling), ADR 007 (no opinion on licenses), ADR 030 (libraries from the Linux distribution), ADR 045 (the real Bundler at run time), and ADR 046 (the linkage check). Phones differ where noted; their extensions are in `doc/contributors/design/phones.md`.

The reference for every rule here is Bundler itself, at the version `Gemfile.lock` pins (Bundler 4.0.20; paths are in its `lib/bundler/`), and the RubyGems of the pinned Ruby (`lib/rubygems/`). Where Fledge does what Bundler does, it calls Bundler's own classes rather than restating them. Code adapted from Bundler sits in SPDX snippets in `lib/fledge/bundle.rb`, `lib/fledge/bundle/selection.rb`, `lib/fledge/git_gem.rb`, and `lib/fledge/git_checkout.rb`.

## Reading the Gemfile and lockfile

`Fledge::Bundle` reads the project's `Gemfile` (or `gems.rb`) and its lockfile (`Gemfile.lock`, or `gems.locked`) with `Bundler::Dsl` and `Bundler::Definition`, with `BUNDLE_GEMFILE` set to the project's Gemfile and Bundler's root reset to it for the read, then put back. Bundler reads a path gem's folder relative to its root, and Bundler's settings (a mirror, a login, the groups, build options) from the project's `.bundle/config`, so the root must be the project, not wherever `fledge build` runs.

The definition is read frozen, whatever the environment says (`Bundler.settings.temporary(frozen: true)`), and `ensure_equivalent_gemfile_and_lockfile` refuses a lockfile the Gemfile has moved past, in Bundler's own words. A definition Bundler may rewrite adds the computer's own platform, which is no more locked for the app than the lockfile says. A project with a Gemfile and no lockfile fails and says to run `bundle lock`. Bundler's message for an empty `CHECKSUMS` entry gets Fledge's advice appended: `bundle lock --add-checksums` fills an entry only for a build installed on this computer or one its server lists, so a gem that only `vendor/cache` holds needs its SHA-256 written by hand, as [Gems in a Fledge app](../../gems.md) shows.

## The lockfile's checks

For each target, before anything is fetched:

- **The lockfile locks the target.** A lockfile platform counts when it is `ruby`, when it is the generic form of the runtime's platform, or when the runtime's platform `===` it, as `Bundler::Definition#validate_platforms!` and `#current_platform_locked?` decide with the running Ruby's platform (`definition.rb`, lines 524 to 530 and 832 to 836). The runtime's platform is `Gem::Platform.new` of the `arch` in the runtime's `rbconfig.rb` (`Fledge::RuntimeContents#arch`), which is what the app's RubyGems and Bundler see on any computer: `arm64-darwin23` for rv-ruby's macOS build. So `arm64-darwin` and `arm64-darwin-23` fit it, and `arm64-darwin-24` does not; a Linux platform fits by its own name or its `-gnu` name. Otherwise the build fails with `Run bundle lock --add-platform PLATFORM`.
- **The Gemfile's `ruby`**, when it has one, must admit the runtime's Ruby (`Bundler::RubyVersion#diff`).
- **Every gem from a gem server has a checksum** in the lockfile's `CHECKSUMS` section, by the name the section gives it (`sqlite3 (2.10.2-arm64-darwin)`). A gem without one fails with `Run bundle lock --add-checksums`. Fledge pins every external input by SHA-256 (AGENTS.md), and an app's gems are Fledge's input here; the lockfile is where the developer pinned them.
- **The lockfile's Bundler has a checksum**, when the app ships it ("The lockfile's Bundler", below): `bundler (VERSION)` in `CHECKSUMS`, which Bundler 2.6 and newer write for the Bundler that wrote the lockfile. Without one the build fails, saying to run `bundle install`, which installs that Bundler, and then `bundle lock --add-checksums`.
- **Every git gem is locked to a whole commit**, 40 or 64 hexadecimal digits. Nothing else pins it.
- **Every gem comes from a gem server, git, or a folder.** Any other source fails, naming it.

## Groups

The app sets up the groups `bundle exec` would, with `development` and `test` always left out: a built app has no development gems, as Warbler's `bundle_without` has it. `Fledge::Bundle#read_groups` asks Bundler's `Definition#requested_groups` (the Gemfile's groups, less `without` and the optional groups, plus `with`; `definition.rb`, lines 1239 to 1243) under a temporary `with` and `without`. The `with` and `without` come from every level Bundler reads: the project's `.bundle/config`, `BUNDLE_WITH` and `BUNDLE_WITHOUT`, and the developer's own. `development` and `test` are added to `without` and removed from `with`, and also removed from Bundler's answer, because Bundler stores an empty list as no value at all (`Settings#array_to_s` and `#set_key`), so an empty temporary `with` lets a lower level's `BUNDLE_WITH=development` show through.

An optional group (`group :extras, optional: true`) ships when, and only when, `with` names it. The app's `.bundle/config` carries the same `BUNDLE_WITHOUT`, and `BUNDLE_WITH` when the project asks for a group, so the app's Bundler sets up exactly what was shipped ("The app's .bundle/config", below).

## Choosing each gem's build

`Fledge::Bundle::Selection` walks the dependencies from the Gemfile's own, in the groups the app sets up, and their runtime dependencies (never `development` ones), leaving out Bundler itself. A Gemfile dependency is left out when its `platforms:` names no platform the target's CRuby is, as `Bundler::CurrentRuby` would answer on the runtime: `windows` (and its old names `mswin`, `mswin64`, `mingw`, `x64_mingw`) on Windows, `ruby` and `mri` elsewhere, never `jruby` or `truffleruby`, each with an optional version suffix such as `mri_40`.

For each gem it takes the build Bundler would set up on the runtime, with `Bundler::MatchPlatform.select_best_platform_match` for the runtime's platform and then for `ruby`, honoring the dependency's `force_ruby_platform`. When the gem locks only one candidate, that is it. When it locks more, the first whose `required_ruby_version` admits the runtime's Ruby wins, which falls back to the gem's source build when its precompiled build excludes the runtime's Ruby, as sqlite3 2.10.2's precompiled builds (`>= 3.2, < 4.1.dev`) exclude Ruby 4.1. That is what a frozen Bundler does: `LazySpecification#choose_compatible` skips a locked build whose metadata does not match the running Ruby (`MatchMetadata#matches_current_ruby?`), tries the local platform and then `ruby` ("Ruby platform is last since it requires compilation, but works when precompiled gems are incompatible"), and with none compatible keeps the locked platform's build (`lazy_specification.rb`, lines 137 to 152 and 192 to 216). Fledge keeps it too, and the build then fails naming it ("Checks that are not about licenses"). The chosen build's own locked dependencies are followed.

The lockfile does not record `required_ruby_version`, so Fledge reads it from the build's checksummed `.gem`, fetched only when a gem locks a build to fall back to (`Fledge::AppGems#required_ruby`). A compact index query would be a second, unpinned input.

A gem the lockfile does not lock, or locks no build of for the target, fails, saying to run `bundle lock` or `bundle lock --add-platform`.

On a phone (`Fledge::MobilePlatform`), the target is `ruby`: the lockfile must lock `ruby`, and every gem is its `ruby` build, as the app's Bundler runs with `force_ruby_platform` (ADR 057).

## The lockfile's Bundler

`bundle install` installs the Bundler a lockfile names under `BUNDLED WITH`, and `bundle exec`, `bundler/setup`, and every `bundle` command then switch to it from Ruby's own (`Bundler.auto_switch` and `Bundler::SelfManager#restart_with_locked_bundler_if_needed`, `bundler.rb` lines 172 to 174 and `bundler/self_manager.rb` lines 9 to 14, at Bundler 4.0.20). So the app ships that Bundler, and its launcher loads it (ADR 063; `doc/contributors/design/launcher.md`, "The Bundler environment").

`Fledge::Bundle#bundler_for` chooses it as `SelfManager#find_restart_version` does (lines 190 to 200), with the runtime's Bundler (`RuntimeContents#gems`, the one `bundler-VERSION`) as the running one:

- Bundler's `version` setting, read from every level with Bundler's root at the project, is `system`: the runtime's Bundler.
- The setting is `lockfile`, its default: the `BUNDLED WITH` version, read as `LockfileParser.bundled_with` reads it. Any other value names the version itself. A lockfile without `BUNDLED WITH`, or a version that does not parse, keeps the runtime's.
- A development build's version (ending `.dev`), or the runtime's own version, keeps the runtime's (`#released?` and `#running?`).

The chosen Bundler is a `Fledge::LockedGem` of `bundler`, platform `ruby`, from `https://rubygems.org/`, where Bundler fetches it (`#remote_specs`), through the mirror and login Bundler's settings give that server, checked against `bundler (VERSION)` in `CHECKSUMS`. When its `required_ruby_version`, read from the checksummed `.gem`, excludes the runtime's Ruby, the app keeps the runtime's Bundler, as `bundle install` goes on with the Bundler that runs it when RubyGems.org has no build of the locked one for the running Ruby (`#install_and_restart_with`, lines 48 to 63). Otherwise `Fledge::AppGems#for` installs it with the app's gems ("Installing into the runtime's gem folder"), beside the runtime's own Bundler, whose `bundle` and `bundler` programs stay the runtime's ("Gem executables"), and `fledge.cfg` names its version as `bundler` (`Fledge::Assembly.launch_config`). `fledge build --from` keeps the key, as it keeps the lockfile (`Fledge::BuiltApp#bundler`).

The app's `.bundle/config` keeps `BUNDLE_VERSION: "system"`, so neither the app's Bundler nor one in a Ruby the app starts tries to switch again: the launcher has already chosen.

## Fetching a gem's file

`Fledge::GemFetcher` finds each gem's `.gem`, for any platform, in this order, and takes the first whose SHA-256 is the lockfile's:

1. the project's `vendor/cache` (`bundle cache --all-platforms` keeps every platform's there);
2. the `cache` folder of each folder on RubyGems' path;
3. Fledge's own cache, `gems/` beside its runtimes (`$XDG_CACHE_HOME/fledge/gems`, or `~/.cache/fledge/gems`).

Otherwise it downloads `REMOTE/gems/FILE` into its own cache through `Fledge::Download`, which streams to a `.part` file, checks the SHA-256, and only then moves it into place.

**Sources, mirrors, and logins.** `Fledge::Bundle::Sources` builds each gem's remote with `Bundler::Source::Rubygems::Remote`, which applies `Bundler.settings.mirror_for` (`bundle config mirror.URL`) and `credentials_for` (`bundle config HOST USER:PASSWORD`, `BUNDLE_HOST`, or a login in the Gemfile's source URL), the same two calls Bundler's fetcher makes, with Bundler's root at the project. `Fledge::LockedGem` keeps the address (with the mirror, without the login) and the login apart, so no message shows a password. The login goes by HTTP Basic authentication to that host and port only, never to another host a redirect leads to. A redirect from HTTPS to plain HTTP is refused. Fledge adds no `fallback_timeout` probe of its own: `mirror_for` runs Bundler's.

**What an answer means.** The advice differs, so the statuses are told apart:

- **404 or 410:** the server has no such file, whatever server it is. This happens when the lockfile was made from a `.gem` in `vendor/cache` or a gem folder since gone, or names a platform the gem's author never published. The build fails naming the gem, the server, the file, and the status, and says to put the file in the project's `vendor/cache` or lock the gem to the source that has it.
- **401:** a login, always: HTTP requires a server to ask for one with `WWW-Authenticate` (RFC 9110, section 15.5.2).
- **403:** read as Bundler reads it, a login the server will not accept (`Bundler::Fetcher::Downloader#fetch`, `fetcher/downloader.rb`, lines 62 to 66, `AuthenticationForbiddenError`), with one exception: a 403 to a request that carried no login, from a host in `GemFetcher::PUBLIC_SERVERS` (`rubygems.org`), means the file is missing. RubyGems.org needs no login for any file it has, and its storage answers 403 `AccessDenied` for a name it does not hold. Bundler never meets that answer, because it fetches only files its index lists; Fledge fetches a locked gem's file for each platform it builds for. A private server's 403 without a login keeps the login advice, as Bundler gives it. A mirror of RubyGems.org is a server of its own, with its own host, so its 403 gets the login advice.
- **401 and 403 advice:** with no login, set one as Bundler reads it (`bundle config set --local HOST USER:PASSWORD`, or `BUNDLE_HOST` with Bundler's escaping); with one, Bundler's login for the host was refused, and `bundle config get HOST` shows it.
- **408, 429, a 5xx, or a connection that fails or breaks off:** asked again after 2, 4, and 8 seconds, four tries in all, as Bundler's default `BUNDLE_RETRY` of 3 makes (`Download::WAITS`), then the build fails. A missing file, a refusal, and a checksum mismatch fail at once. The retry rules are shared with runtime downloads: `doc/contributors/design/releases.md`.

## Installing into the runtime's gem folder

A gem the runtime already has at the same full name is the runtime's, already audited, and is not added again (`RuntimeContents#gems`). Every other gem from a gem server is installed into the runtime's own gem folder, `lib/ruby/gems/API` (`ruby/lib/ruby/gems/API` on Windows), where API is the Ruby's ABI version (`4.0.0` for Ruby 4.0). Bundler's `path.system` setting makes that folder the bundle's, beside Ruby's default and bundled gems.

`Fledge::GemPackage` verifies the file as `Gem::Package#verify` does, then lays it out as `Gem::Installer#install` would (`rubygems/installer.rb`, lines 268 to 305, at Ruby 4.0.9), as entries in the app rather than by running the installer:

- the gem's files in `gems/FULL_NAME/` (`Gem::Package#extract_files`);
- its specification in `specifications/` (`#write_spec`);
- the `.gem` itself in `cache/` (`#write_cache_file`);
- a loader in `plugins/` for each `rubygems_plugin` file in its require paths (`#generate_plugins`).

Executables are written apart, by the runtime's own RubyGems ("Gem executables"). Each gem ships with all of its own files, its license files among them (ADR 007).

## RubyGems plugin loaders

A gem with a RubyGems plugin gets a loader named for the gem in the gem folder's `plugins/`. When the runtime already has a loader of that name for another version of the gem, the runtime's stays, and the app's gem is installed beside it with no loader of its own (`Fledge::AppGems#for` drops any entry at a path in `RuntimeContents#plugins`). The case is common: irb asks for rdoc, many Gemfiles (Rails's among them) lock an rdoc newer than the runtime's, and the runtime has `rdoc_plugin.rb`.

Do not "fix" this by replacing the runtime's file. RubyGems' own rule is that installing a gem writes its loader over any other version's (`Gem::Installer#generate_plugins`, `installer_uninstaller_utils.rb`, `regenerate_plugins_for`, at Ruby 4.0.9), but a loader matters only to a command that installs gems (`gem install`, and the hooks a `rubygems_plugin` registers), an app never installs, and a build never overwrites a file of the runtime's.

## Gem executables

Under `bundle exec` the bundle's `bin` folder is first on `PATH`, with every gem's wrapper in it. A built app has no Ruby on the person's computer (ADR 003), so a wrapper that says `#!/usr/bin/env ruby` would help no one. The runtime's own wrappers do: RubyGems, built relocatable, writes `bindir="${0%/*}"` and `exec "$bindir/ruby" -x "$0"` (`Gem::Installer#bash_prolog_script`, `installer.rb`, line 979) on macOS and Linux, and on Windows a `.bat` that runs the `ruby.exe` beside it (`#windows_stub_script`, line 783).

So the runtime's own Ruby writes the wrappers of every gem the app ships that has executables (`NativeBuild#binstubs`, its `STUBS` script), as `gem install` would: for each, a copy with its extensions taken out (they are compiled elsewhere), packed as `gem build` packs it, under `Gem::SilentUI`, and installed into a gem folder of its own with the unpacked runtime's bin folder as its bin folder (`Gem.default_bindir`). `Gem.ruby` is set to `/usr/bin/env ruby` for that run, so the interpreter line after the prolog, which `ruby -x` skips, is the one the runtime's own wrappers have, with no path of the build's computer. The wrappers ship in the runtime's `bin/` (`ruby/bin` on Windows), except a name the runtime already has there (`RuntimeContents#binaries`), whose wrapper finds whichever version of its gem the app's Bundler activates. Gems from a server, from git, and from a folder are all written this way, except the project's own gem, whose executable is the program the app runs.

A program finds a wrapper at `File.join(Gem.bindir, NAME)` (`NAME.bat` on Windows), or the executable by `Gem.bin_path`, which never needed the wrapper. The app's `PATH` does not include the runtime's `bin/`, so `system("name")` finds a gem's program only when the app or the person puts it there: Bundler's `PATH` entry in the app names `lib/ruby/gems/API/bin`, which does not exist, because a relocatable wrapper finds its Ruby beside itself and one there would not. Adding `Gem.bindir` to `PATH` would be a change to `ENV` that decision 9 asks to avoid; it waits until an app needs it, and would cost a line in `runtime/launcher/bundler.c` and a justified difference in `Parity::JUSTIFIED`.

Writing executables unpacks the runtime and its build-only companion and runs the runtime's Ruby once, even when nothing is compiled.

## Git gems

A git gem (`Fledge::GitGem`) is its repository, the locked commit, the glob its gemspecs are found by, what the Gemfile asked for (a tag, branch, or ref), and whether it asked for submodules.

`Fledge::GitCheckout` keeps a bare clone of each repository in Fledge's cache, `git/` beside its runtimes, named for the repository and a hash of its URI. It fetches only when the locked commit is missing (every branch and tag, then the commit itself, which a server may serve though no branch holds it), and refuses a commit the repository does not hold. It clones the cache into the build's work folder, checks out the commit detached, runs `git submodule update --init --recursive` when the Gemfile says `submodules: true` (as `Bundler::Source::Git::GitProxy#copy_to` does after its `git reset --hard`; without the option submodules stay out, as Bundler leaves them), and then evaluates every gemspec the glob finds and writes it back as `spec.to_ruby`, as `Bundler::Source::Git#serialize_gemspecs_in` does, so a gemspec that runs `git ls-files` loads with no git. Git runs with `GIT_DIR`, `GIT_WORK_TREE`, and `GIT_INDEX_FILE` cleared and `GIT_TERMINAL_PROMPT=0`. Credentials for a git gem or a submodule are git's own (its credential helper), as they are for Bundler. One checkout serves every gem the lockfile takes from that repository at that commit.

`Fledge::GitPackage` ships each locked gem's own folder of the checkout, the one its gemspec is in, less git's files (`.git`, and each submodule's `.git` file), where Bundler keeps it: `GEM_DIR/bundler/gems/BASE-SHORTREF/FOLDER` (`Bundler::Source::Git#install_path` and `#base_name`, with the first 12 digits of the commit). It refuses a gemspec whose version is not the lockfile's. A gem whose gemspec is at the repository's top ships the whole checkout. The app's frozen Bundler finds each gem there by its gemspec, without git; `GitProxy#installed_to?` counts a checkout installed whatever its `.git` holds. The rest of the repository stays behind, though `bundle exec` would find it in its own checkout: a repository holds more than its gems (Ferro's holds its own tooling, and symbolic links a Windows `.zip` cannot hold), and Bundler finds a gem by its gemspec, in its folder, alone.

## Path gems

A gem from a folder (`path:`, or the Gemfile's `gemspec` line) is one of:

- **Inside the project, with no extension and no executable**, or the project's own gem with no extension: it ships as part of the project, in `app/`, with nothing more.
- **Inside the project, with an executable or an extension:** a `Fledge::PathGem` at its folder in `app/`. Its executables are written ("Gem executables"); its extension is compiled, and what the build wrote into its require paths replaces the project's own files there (`Fledge::AppGems#app_files`, which must therefore be asked after `#for`).
- **Outside the project:** shipped in Bundler's own place for a copy of it. `bundle cache --all` copies such a gem to `vendor/cache/NAME` (`Source::Path#cache`), and a Bundler that finds that folder uses it in place of the original path, even when the original is gone (`#specs` and `#has_app_cache?`). Fledge ships the gem's whole folder, less git's files, with its gemspecs evaluated as a git gem's are, at `app/vendor/cache/NAME`, where NAME is the last part of the path (`#app_cache_dirname`). It ships from the developer's `vendor/cache/NAME` when they have made that copy, since that is what `bundle exec` loads, and from the original path otherwise. A path whose last part is `.` or `..` names no such folder and is refused; so is a folder that is not there. The project's own `vendor/cache` still stays out of the app (ADR 005), so only path gems' folders arrive there.

`Fledge::PathPackage` reads the gemspec named for the gem among those the glob finds (Bundler's `{,*,*/*}.gemspec` by default), and refuses a folder with none, or one of another version than the lockfile's.

## Compiling a gem

A gem whose chosen build has an extension still to compile (a `ruby`-platform gem with `extensions`, a git gem, or a path gem whose gemspec names extensions) is compiled by `Fledge::NativeBuild`, for the platform Fledge runs on, which is the only platform it builds for (ADR 006). A precompiled build that fits always wins over compiling ("Choosing each gem's build"); a gem compiles when it publishes no build for the target, when its precompiled build excludes the runtime's Ruby, or when the Gemfile asks for its source with `force_ruby_platform`, as `examples/nokogiri_app` does.

`NativeBuild::RuntimeRuby` unpacks the target's runtime and its build-only companion, which unpacks over it, into the build's work folder. The companion carries the library extension builds link against: the static libruby on macOS and Linux, which mkmf links the test programs of `have_func` and the rest against (`mkmf.rb`, line 542, at Ruby 4.0.9; an extension of a static Ruby links no libruby itself, lines 2753 to 2769), and the import library of Ruby's DLL on Windows. Its contents are in `doc/contributors/design/runtimes.md`. `Fledge::Runtimes#dev_archive` finds the companion as it finds the runtime, checked against the SHA-256 the gem pins (ADR 014), and nothing in it is copied into an app.

The runtime's own Ruby (`bin/ruby`, or `ruby\bin\ruby.exe`) runs `NativeBuild::SCRIPT` on a plan:

- a gem from a server is installed as RubyGems installs one, `Gem::Installer.at(...).install`, with its build options, `ignore_dependencies`, and no documents, into the build's own gem folder;
- a git gem's or path gem's extensions are built in a copy of its checkout at `bundler/gems/SCOPE` in that folder, with `Gem::Ext::Builder#build_extensions` and the specification's `extension_dir` set as Bundler's `Gem::Specification#extension_dir` would set it (`bundler/gems/extensions/PLATFORM/ABI/` and the scope and folder joined with `-`, `bundler/rubygems_ext.rb`, lines 226 to 236). A path gem is copied from the files its gemspec lists, as `gem build` and `gem install` would see them.

So the headers, `RbConfig`, compiler flags, `Gem::Platform.local`, and `Gem.extension_api_version` are the runtime's (`4.0.0-static` for rv-ruby's static Ruby, `4.0.0` for RubyInstaller's), and the extension lands where the app's RubyGems and Bundler look. The developer's Ruby compiles nothing.

**Order.** Every gem with an extension is installed after the gems it depends on that come from a gem server, which its `extconf.rb` may require (rb_sys and its rake-compiler-dock for an rb-sys gem, mini_portile2 for nokogiri); those are installed into the build's gem folder first, from the lockfile's own files.

**Environment.** The script runs with the caller's environment less every variable the launcher hides from an app's boot (`RUBY*`, `GEM_*`, `GEMRC`, `BUNDLE_*`, `BUNDLER_*`, `RI_FORCE_PATH_FOR_DLL`; `NativeBuild::SCRUBBED`, after `runtime/launcher/scrub.c`), so that `bundle exec fledge build` cannot load the developer's Bundler into it, with `GEM_HOME` and `GEM_PATH` naming the build's gem folder, and on macOS with `MACOSX_DEPLOYMENT_TARGET` set to the runtime's oldest macOS. On Windows the script first runs `RubyInstaller::Runtime.enable_msys_apps(for_gem_install: true)`, as RubyInstaller's own `operating_system.rb` does in its `Gem.pre_install` hook, which finds MSYS2 by `MSYS2_PATH`, beside Ruby, at `C:\msys64`, in the registry, or on `PATH`; the runtime keeps RubyInstaller's Ruby library for this. The compiler's output goes to standard error. A gem that fails to compile fails the build, saying which.

## The toolchain and the oldest systems

The compiler is the developer's: Xcode's command line tools on macOS, a C compiler and make on Linux, MSYS2's UCRT64 toolchain on Windows, and cargo for a Rust extension. A Rust extension for RubyInstaller's Ruby takes Rust's GNU target, as rb-sys requires, and bindgen needs a libclang (`LIBCLANG_PATH` and `BINDGEN_EXTRA_CLANG_ARGS` on Windows, as Ferro's CI and Fledge's set them).

A compiler targets the computer it runs on unless told otherwise, and a runtime runs on older ones. `MACOSX_DEPLOYMENT_TARGET`, which clang and rustc both read, aims macOS builds at the runtime's oldest macOS. `NativeBuild::Floors` then reads every Mach-O and ELF file a build wrote and fails one built for a newer macOS than the platform's oldest (its `LC_BUILD_VERSION`) or needing a newer glibc than the floor (its newest `GLIBC_` symbol version, as auditwheel reads it), saying to keep the deployment target or to build on a Linux with the floor's glibc. The floors are `Fledge::Platform::MACOS_MINIMUM` and `GLIBC_MINIMUM` (`decisions.md`, 2026-10-26, decision 7, for glibc); musl Linux has no glibc floor to check. The release policy for floors is in `doc/contributors/design/releases.md`.

## What a compiled gem ships

`Fledge::CompiledGem` ships:

- what the gem's package holds: a `.gem`'s files, specification, and cache copy, as for a precompiled gem; a git gem's folder; a path gem's folder or files;
- the files the build wrote into the gem's require paths, where RubyGems installs an extension: those the package lacks, and those whose bytes differ from the package's (a path gem's own copy, compiled by its developer for their Ruby, is replaced);
- its extensions folder, with `gem.build_complete`, without `gem_make.out` and `mkmf.log`; without `gem.build_complete`, RubyGems and Bundler take the gem as not yet installed;
- `build_info/FULL_NAME.info`, when it was built with options (`Gem::Installer#write_build_info_file`, which `gem pristine` reads).

The build's other leftovers (the Makefile beside `extconf.rb`, a Cargo target folder, debug symbols, the logs) stay behind: nothing an app runs reads them, and they hold the build computer's paths.

## Build options

`bundle config build.NAME` at any level Bundler reads (the project's `.bundle/config`, `BUNDLE_BUILD__NAME`, or the developer's own) reaches the gem's `extconf.rb`, split as a shell would, as `Bundler::GemInstaller#spec_settings` splits it (`Fledge::Bundle#build_args`). A project that needs an option to build a gem the way it should ship says so as it already would for `bundle install`. `examples/nokogiri_app` keeps `build.nokogiri --disable-xml2-legacy` in its `.bundle/config`, so that its libxml2, built from source on a Mac, links none of the build computer's own libraries (Homebrew's `liblzma`, which the linkage check refuses). nokogiri built from source compiles in libxml2, libxslt, and libgumbo; on a Mac it loads macOS's own iconv, and on Windows its `extconf.rb` builds GNU libiconv and links it in statically, which ships (ADR 007).

## The app's .bundle/config and gemspecs

`Fledge::Bundle#app_files` writes what the app's `app/` folder holds in place of the project's own files:

- **`.bundle/config`**, Warbler's settings for a packed app (`Fledge::Bundle::SETTINGS`): `BUNDLE_VERSION: "system"` (never switch to another Bundler at run time, since the launcher already loads the one the lockfile names: "The lockfile's Bundler"), `BUNDLE_FROZEN: "true"` (refuse a Gemfile that moved past its lockfile, and never rewrite or touch the lockfile, so an app in a read-only folder starts), `BUNDLE_PATH__SYSTEM: "true"` (the gems are in Ruby's own gem folder), `BUNDLE_AUTO_INSTALL: "false"`, then `BUNDLE_WITHOUT` and, when the project asks for a group, `BUNDLE_WITH` ("Groups"). A phone's app adds `BUNDLE_FORCE_RUBY_PLATFORM: "true"`. This is the local level of Bundler's settings, which wins over every other (`Settings#configs`), in the app and in any Ruby it starts; the launcher also has Bundler read it as the global file, so the person's `~/.bundle/config` is never read (`doc/contributors/design/launcher.md`).
- **Each gemspec of the project's own gems** (the root's, and path gems' inside the root), evaluated now and written as `spec.to_ruby`, as Bundler caches a git gem's, so a gemspec that runs `git ls-files` needs no git where the app runs.

The developer's own `.bundle` folder, `vendor/bundle`, and `vendor/cache` never ship (ADR 005).

## binding.irb and force_activate

A frozen bundle refuses one thing an unfrozen one allows: a bundled gem the lockfile does not lock, activated for a moment. `binding.irb` in an app whose Gemfile does not name irb fails to require it, and Ruby's `prelude.rb` then calls `Gem::BUNDLED_GEMS.force_activate("irb")`, which sets up the Gemfile's gems and irb as a temporary bundle it never writes to the lockfile (`Definition.no_lock`; `prelude.rb`, lines 8 to 11, and `bundled_gems.rb`, lines 214 to 259, at Ruby 4.0.9; Ruby's master has the same code). Frozen, Bundler refuses it ("You have added to the Gemfile: * irb", naming `Gemfile.lock`) and would resolve only the lockfile's gems. A developer's bundle is not frozen, so `bundle exec` works; `bundle exec` in a bundle the developer froze fails the same way.

Fledge's RubyGems defaults (`runtime/rubygems/operating_system.rb`, which RubyGems loads for whoever packages Ruby) prepend to `Gem::BUNDLED_GEMS.force_activate` so that, while it runs and on its thread only, `Bundler.frozen_bundle?` answers false. The modules are anonymous, so an app sees no constant of Fledge's (ADR 003). The bundle the launcher set up stays frozen, and nothing is written. The file creates `Gem::BUNDLED_GEMS` as an empty module when it is not yet defined, since `bundled_gems.rb` loads after it and reopens the module.

Two other ways were weighed and not taken:

- **No `BUNDLE_FROZEN`** in the app's `.bundle/config`: Bundler would touch the lockfile on every setup (`Definition#write_lock`, `definition.rb`, lines 401 to 426), fail in a read-only folder, and add the running platform to its resolution.
- **Adding irb to the app's bundle at build time:** the app's `$LOAD_PATH` and loaded gems would differ from what `bundle exec` gives.

On Windows, `binding.irb` in such a bundle fails under `bundle exec` as well, and the app matches it: reline, which irb requires, requires `fiddle/import` there, and fiddle, a bundled gem, is a dependency of neither irb nor reline, so the temporary bundle leaves it out. With `fiddle` in the Gemfile it opens IRB. `test/built_app_test.rb` skips its `binding.irb` test on Windows for this reason.

## The linkage check

`Fledge::Linkage` (ADR 046) reads each compiled file of every gem an app ships, precompiled or compiled, in the format of the target's own loader (ELF, Mach-O, or PE; a loader loads no other), with `Fledge::Binary`: the system's objdump on macOS and Linux, and on Windows the `llvm-readobj.exe` the runtime carries in its tools folder (ADR 013). A file may need only a library that:

- **the target's operating system provides** (`Linkage::SYSTEM_LIBRARIES`): on glibc Linux, the libraries PEP 600 lets a manylinux_2_39 wheel assume (auditwheel 6.4.2's `manylinux-policy.json`, `lib_whitelist`) and glibc's loader; on musl Linux, musllinux_1_2's (auditwheel 6.8.2's `musllinux-policy.json`: musl's C library by its own name and Alpine's, and zlib); on macOS, anything in `/usr/lib` and `/System/Library/Frameworks`; on Windows, the API sets, the system DLLs `runtime/licenses.yml` lists, `bcryptprimitives.dll` (whose `ProcessPrng` Rust's standard library imports), and the DLLs a game's or windowed program's libraries link for windows, input, graphics, and sound (`avrt`, `cfgmgr32`, `comctl32`, `d3d9`, `d3d11`, `dinput8`, `dsound`, `dwmapi`, `dxgi`, `hid`, `imm32`, `setupapi`), each in System32 on every x64 Windows from 7 SP1 and every ARM64 Windows from 10, as delvewheel 1.13.2's `_dll_list.py` lists them;
- **the runtime ships** (`RuntimeContents#libraries`: Ruby's DLL, `libgmp-10.dll`, `libcrypt.so.2`, and the rest);
- **the gem itself carries**, by file name, and on macOS only where dyld would find it ("dyld's rules on macOS");
- on Linux, **`fledge.yml` lists** under `linux: system_libraries` ("Libraries from the Linux distribution").

A file that needs another Ruby's DLL (a precompiled gem's `lib/nokogiri/3.4/nokogiri.so`, which needs `x64-ucrt-ruby340.dll`) is built for that Ruby, never loaded, and not judged. Every other library fails the build. `Fledge::AppGems` collects every problem of every gem, then raises once, so one build shows them all. The message names the gem, the file, and the library, and says to build the gem so that it carries the library or links it statically, and on Linux, to list it when every computer the app goes to has it. The check reads only what each file needs, never what is compiled into it (ADR 007).

## dyld's rules on macOS

A library the gem carries counts only where dyld would find it, so that a bundle that names `@rpath/libfoo.dylib` with the one run path `/opt/homebrew/lib` fails, however the gem's copy is named. `Fledge::Linkage::Dyld` expands each name as `dyld(1)` describes ("Dynamic Library Loading"):

- `@loader_path` is the folder of the file that names the library.
- `@rpath` is tried with each run path the file's LC_RPATH commands give, then those of each file that loaded it, as dyld searches the chain of loaders; the run paths are passed down until no file gains one. A run path that begins with `@loader_path` is the folder of the file whose LC_RPATH it is.

A name that leads to no file of the gem fails, with a message that names the file, the library, where the gem carries it, and the run paths searched, and suggests the `@loader_path` run path that would reach it (`install_name_tool -add_rpath`). The rule refuses only what certainly would not load:

- A run path that is absolute (`/opt/homebrew/lib`, `/Library/Frameworks`) reaches nothing in the app, and a relative one depends on the folder the program starts in; neither is a fault when another run path reaches the library.
- A name or run path that begins with `@executable_path`, or that climbs out of the gem's folder, depends on where the gem sits in the app, which differs between a console app and a macOS bundle, so it is judged by its file name only.
- A library the runtime ships is the runtime's to place, and is judged by its file name.
- Ruby, the program that loads every bundle, contributes no run paths: its own lead into the runtime, never into a gem.
- An absolute name outside `/usr/lib` and `/System/Library/Frameworks` whose file name the gem carries is accepted by that name. dyld would load it only from that path, or from an image already loaded under the same install name, and telling those apart needs the load order, which a check of files at rest does not have.

The fixtures for these rules are built by `test/linkage_test.rb` with Xcode's clang and `install_name_tool`, which only a Mac has; elsewhere those tests skip.

## Libraries from the Linux distribution

`fledge.yml`'s `linux: system_libraries` (ADR 030; `Fledge::Config::Linux`) is a list of sonames, each a library's name as a compiled file's `DT_NEEDED` gives it: letters, digits, and `. _ + -`, ending in `.so` and its version numbers, with no folder (`Config::Linux::SONAME`, and the schema's same pattern). A repeat is dropped. No wildcards. The key applies on glibc and musl Linux alike (`Config#system_libraries` answers it for every Linux platform) and every other build ignores it.

- **Accepted:** a compiled file may need any library on the list (`Linkage`'s `system:`).
- **Refused when unlisted:** every other library still fails, and on Linux the message ends with the key to copy: `list it in fledge.yml as linux: { system_libraries: [libxml2.so.2] }`.
- **Refused when unused:** a listed library that no gem's compiled file needs beyond what the baseline, the runtime, and the gems provide fails the build too (`Linkage#unused`), asked after every gem is judged. So the list cannot name what a gem opens with `dlopen`, which no compiled file names.

The list goes into `fledge.cfg` as `system_libraries = …`, which the Linux launcher checks before Ruby starts, exiting 72 with the missing library's name (`doc/contributors/design/launcher.md`). A `.deb` depends on the packages dpkg-shlibdeps finds for the files that need them (`doc/contributors/design/desktop-apps.md`). An AppImage and a `.tar.gz` do not carry them.

The prior art behind the soname list: auditwheel 6.4.2, `src/auditwheel/main_repair.py`, lines 102 to 112 (`--exclude`); delvewheel at 0cf6869e, `delvewheel/__main__.py`, line 63; Tauri at 32576120, `crates/tauri-utils/src/config.rs` lines 339 and 340, `crates/tauri-bundler/src/bundle/linux/debian.rs` lines 204 to 207, `crates/tauri-cli/src/interface/rust.rs` lines 1419 to 1430, and `appimage/linuxdeploy.rs` lines 150 to 165, 197 to 203, and 242 to 245; Briefcase at fee777ed, `docs/en/reference/platforms/linux/system.md` lines 182 to 194 and `appimage.md` lines 55 and 138 to 153; AppImage's excludelist (pkg2appimage at 19e30b27); Debian Policy 8.6.1; dpkg-shlibdeps(1) at dpkg 1.22; sysexits(3). These were read when ADR 030 was decided.

## Checks that are not about licenses

Fledge judges no gem by its license, whether it declares one, or what its compiled files hold (ADR 007). Each check that remains decides whether the app runs where it goes, or whether its inputs are the ones the developer locked:

- **The lockfile locks the target**, as the app's frozen Bundler would refuse it otherwise ("The lockfile's checks").
- **Checksums and git pins:** each `.gem` matches the lockfile's SHA-256, and each git gem is locked to a whole commit. This is about which bytes ship.
- **`required_ruby_version` and the Gemfile's `ruby`:** a gem whose chosen build's `required_ruby_version` excludes the runtime's Ruby fails, naming it, as RubyGems would refuse it (`GemPackage.ruby_problems`), and so does a Gemfile `ruby` the runtime does not satisfy.
- **Path gems:** one outside the project whose folder is missing, or whose path ends in `.` or `..`, fails.
- **Servers:** one that refuses the login, or has no file for the gem, fails ("Fetching a gem's file").
- **Linkage:** each compiled file needs only libraries the system, the runtime, the gem, or the list provides ("The linkage check").
- **Floors:** what Fledge compiled needs no newer macOS or glibc than the runtime's oldest ("The toolchain and the oldest systems").
- **A gem that fails to compile** fails the build.

Two behaviors once given license reasons stand on technical ones: a git gem ships its own folder of the checkout, not the whole repository ("Git gems"), and the runtime prunes nkf's JRuby sources, which is about the runtime (`doc/contributors/design/runtimes.md`).

## Examples that exercise these rules

CI builds each on every desktop platform it names and runs the result on a fresh runner with no Ruby (`.github/workflows/ci.yml`, the Build and Delivery jobs):

- `examples/my_cool_app`: a gem-shaped app (i18n, which needs concurrent-ruby, and sqlite3, precompiled), compared with `bundle exec ruby exe/my_cool_app` by the parity check.
- `examples/native_app`: gems compiled from source (redcarpet, bigdecimal for spreadsheet), a git gem with a Rust extension (ferro-idna, from its tag), and ratatui_ruby, precompiled where it has a build and compiled with cargo where it has none.
- `examples/nokogiri_app`: nokogiri from source with a build option, on macOS and Windows.
- `examples/real_gems`: a gem through a loopback mirror of RubyGems.org that asks for a login (`.github/scripts/gem-mirror.rb`, named by Bundler's own mirror and credential settings in the example's `.bundle/config`); a path gem with an executable outside the project (`examples/real_gems_shared`); a path gem with a C extension inside it; a git gem with a submodule; and a gem in an optional group the example's `.bundle/config` asks for. CI fails the build unless the mirror served the gems with the login. It runs no `bundle exec` comparison, since Bundler compiles no path gem's extension. Its lockfile was made through the mirror, as a developer behind one would make it, so locking it again needs the mirror.
- `examples/system_library`: a path gem whose C extension links libpng, listed under `linux: system_libraries` (ADR 030).

The musl and ARM64 Windows builds take no part in the examples that compile, since their CI runners have no C toolchain.
