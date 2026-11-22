<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Drafts for the maintainer

Agents never file a report upstream or message another project's maintainers; they draft it here, and the maintainer decides whether to send it. Each draft says where to file it and holds the text. This page says, for each, why it matters to Fledge, what Fledge does meanwhile, and what changes in Fledge once upstream acts.

## Upstream bug reports

Each was found by Fledge's checks, root-caused to the upstream line, and searched for in the project's tracker before it was drafted. None is filed. Fledge works today without any of them being fixed; filing them is for the projects, and for Fledge to carry fewer workarounds later.

| Draft | Upstream | What breaks | What Fledge does meanwhile | When upstream fixes it |
|---|---|---|---|---|
| [ruby-ios-configure.md](ruby-ios-configure.md) | Ruby | `configure` refuses to build for iOS since ruby/ruby 3e96f16643 | The `configure_macos_minimum` edit to the generated `configure`, iOS only (`doc/contributors/design/phone-runtimes.md`, "Scripted edits to Ruby's source") | Drop that edit at the Ruby release that carries the fix |
| [ruby-group-member.md](ruby-group-member.md) | Ruby | Where `getgroups` fails, as in an iOS app, `File.readable?`, `#writable?`, `#executable?`, and `#grpowned?` raise, because `file.c` takes its −1 for a count | The `file_c` edit, iOS only (same table) | Drop the edit |
| [ruby-glob-base-dir.md](ruby-glob-base-dir.md) | Ruby | `Dir.glob(base: dir)` with a `Dir` opened by a relative path finds nothing, on Linux too; Android meets it more often | The `dir_c` edit, Android only (same table) | Drop the edit |
| [ruby-umask-fortify.md](ruby-umask-fortify.md) | Ruby | `File.umask(-1)` and `umask: -1` abort an app built with `_FORTIFY_SOURCE` on Android, where bionic checks the mask | The `process_c_umask` and `file_c_umask` edits, Android only (same table) | Drop the edits |
| [ffi-windows-utf8-path.md](ffi-windows-utf8-path.md) | ffi | ffi opens a DLL with `LoadLibraryExA`, so a gem's DLL under a folder named outside ASCII fails on Windows | The launcher, and the runtime's `ruby.exe` and `rubyw.exe`, which `RbConfig.ruby` names, declare UTF-8 as a Windows app's ANSI code page (`doc/contributors/design/launcher.md`, "The locale") | Fledge keeps the code page for other gems' narrow calls |
| [mini_portile2-xz-shell.md](mini_portile2-xz-shell.md) | mini_portile2 | On Windows, a `.tar.xz` under a path that needs shell escaping (a space, a non-ASCII letter, an 8.3 short name) unpacks nothing and reports OK, so a gem such as nokogiri fails to build | `fledge build` compiles in a folder named by its long names, which covers 8.3 names (`Fledge::LongPath`); a user folder with a space or a non-ASCII letter still fails | Nothing to drop; such folders start working |
| [rubygems-binary-spec-names.md](rubygems-binary-spec-names.md) | RubyGems | Since 4.1 a packed gem's specification has BINARY names, so installing an executable named outside ASCII into a folder named outside ASCII raises, JSON cannot write the name, and on Windows a gem's path expanded in a folder named outside ASCII cannot be opened | The runtime's Ruby runs `fledge build`'s scripts with `RUBYGEMS_USE_PSYCH=true`, which reads metadata with Psych as RubyGems 4.0 did (`doc/contributors/design/gems.md`, "Compiling a gem") | Drop the variable once the runtimes carry the fixed RubyGems |
| [ruby-c-locale-paths.md](ruby-c-locale-paths.md) | Ruby | Under the C locale, Ruby gives a path outside ASCII as a US-ASCII string that is invalid in its own encoding (`__dir__`, `$0`, `-I` and `RUBYLIB` entries, the features it loads at boot), where `Dir.pwd` and `ENV` give BINARY, so matching or splitting the path raises | Every Ruby of a runtime turns a bare C locale into a UTF-8 one (`doc/contributors/design/launcher.md`, "The locale") | Nothing to drop: the app would still meet BINARY and US-ASCII paths, and the coercion stays |
| [ruby-c-locale-utf8.md](ruby-c-locale-utf8.md) | Ruby (feature) | With no locale, as a double-clicked macOS app and a phone app are started, Ruby reads paths and text as US-ASCII where the developer's terminal gave UTF-8 | The locale coercion (`doc/contributors/design/launcher.md`, "The locale") | The coercion becomes Ruby's own behavior at the Ruby release that takes it: `Parity::JUSTIFIED` and `RubySpec::JUSTIFIED` lose their locale entries, and the coercion's reversal, in the same section, can run |
| [bundler-c-locale-paths.md](bundler-c-locale-paths.md) (pull request) | Bundler | Under the C locale, `bundler/setup` and `bundle` fail in seven places when Ruby, or a load path entry, is in a folder named outside ASCII, and the error report raises in its turn and hides the cause; `bundle exec` fails there with a UTF-8 locale too | The locale coercion (`doc/contributors/design/launcher.md`, "The locale"); the launcher sets up Bundler itself (`runtime/launcher/bundler.c`) and runs no `bundle exec` | Nothing to drop |
| [thor-c-locale-paths.md](thor-c-locale-paths.md) (pull request) | Thor | Under the C locale, a Thor CLI run by its absolute path from a folder named outside ASCII fails as it defines its commands, and so does Bundler's vendored Thor | The locale coercion | Nothing to drop; Bundler needs a release that vendors the fixed Thor |

Two Ruby fixes found the same way were already on Ruby's master, so Fledge takes them as edits and needs no report: Android's `fork` (Bug #22445) and naming a thread that has ended (Bug #22471). Both edits go at Ruby 4.1.0, if it carries the fixes.

## Notes for other projects' sessions

[rooibos.md](rooibos.md) and [tokra.md](tokra.md) were notes for the Rooibos and Tokra sessions, written for Fledge `v0.0.1.pre.17`. Their facts are out of date (Fledge is at 0.12.0 on Ruby 4.1), and neither needs anything from Fledge, so they need not be sent; they stay as the record of what was offered.
