<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Security policy

## Report a vulnerability privately

Report a vulnerability in Fledge through GitHub's private vulnerability reporting, never on [the forum](https://forum.setdef.com/c/fledge), in an email thread, or anywhere else others can read it:

1. Open [the repository's Security tab](https://github.com/setdef/Fledge/security) and choose **Report a vulnerability**, or go straight to [a new private advisory](https://github.com/setdef/Fledge/security/advisories/new).
2. Fill in the form. Only the project's maintainers can see what you send.

If you aren't sure that a problem is a vulnerability, report it privately anyway.

## What to include

- The Fledge version, from `bundle exec fledge --version`.
- Your systems: the operating system and processor you built on, and those the app ran on.
- How to reproduce the problem: the app's `fledge.yml`, the command you ran, and what happened.

## Which versions get fixes

[The README's Compatibility section](README.md#compatibility) lists the systems Fledge builds for. It makes no promise that an earlier release gets a fix. A fix ships in a new release, so install [the latest release](https://github.com/setdef/Fledge/releases/latest), then build your app again: an app keeps the runtime it was built with.
