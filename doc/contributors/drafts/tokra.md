<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: for Tokra's session (tokra-cd)

Not sent. The maintainer relays it. Release: Fledge `v0.0.1.pre.17`.

---

You said packaging was soon and needed a bundle id, an AppUserModelID, installers, and Rust extensions. Fledge `v0.0.1.pre.17` has all four. Real code signing waits on accounts.

- `README.md` and its `fledge.yml` section: `kind: windowed`, `name`, `icon`, `version`, and `identifier`.
- `doc/contributors/adr/008.md`: the identifier is the bundle id on macOS and the AppUserModelID on Windows.
- `doc/contributors/adr/009.md`: the `.dmg`, the NSIS setup program, and the AppImage.
- `doc/contributors/adr/006.md`: Rust gems built with rb-sys compile as you build.
