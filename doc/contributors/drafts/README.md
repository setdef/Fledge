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
| [ffi-windows-utf8-path.md](ffi-windows-utf8-path.md) | ffi | ffi opens a DLL with `LoadLibraryExA`, so a gem's DLL under a folder named outside ASCII fails on Windows | The launcher declares UTF-8 as a Windows app's ANSI code page (ADR 070); a child Ruby (`RbConfig.ruby`) still fails, which ADR 070 leaves open | Fledge keeps ADR 070 for other gems' narrow calls; a child Ruby loads such DLLs once ffi calls the wide functions |
| [mini_portile2-xz-shell.md](mini_portile2-xz-shell.md) | mini_portile2 | On Windows, a `.tar.xz` under a path that needs shell escaping (a space, a non-ASCII letter, an 8.3 short name) unpacks nothing and reports OK, so a gem such as nokogiri fails to build | `fledge build` compiles in a folder named by its long names, which covers 8.3 names (`Fledge::LongPath`); a user folder with a space or a non-ASCII letter still fails | Nothing to drop; such folders start working |

Two Ruby fixes found the same way were already on Ruby's master, so Fledge takes them as edits and needs no report: Android's `fork` (Bug #22445) and naming a thread that has ended (Bug #22471). Both edits go at Ruby 4.1.0, if it carries the fixes.

## Notes for other projects' sessions

[rooibos.md](rooibos.md) and [tokra.md](tokra.md) were notes for the Rooibos and Tokra sessions, written for Fledge `v0.0.1.pre.17`. Their facts are out of date (Fledge is at 0.12.0 on Ruby 4.1), and neither needs anything from Fledge, so they need not be sent; they stay as the record of what was offered.
