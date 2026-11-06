<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## C. What must be proven, or available, before 1.0.0? (open, no deadline)

You have not decided this, and nothing waits on it. It is here so that it stays on your list.

**Axis 1: what is proven.** You wrote that there is no 1.0 until "at least some of these things are proven": a game run on a real iPhone or iPad with App Review, a signing chain made by a real Apple or Microsoft certificate, and Android's arm64-v8a build running. None is proven today. The last two cost money you have said not to spend. The nearest to hand is a playtest of a Ruby game on your iPad Pro and your OnePlus Nord; the runbook for it is `doc/contributors/device-test.md`.

**Axis 2: how people get and update apps.** You have not said whether any of these is needed for 1.0.0:

- *App stores, for windowed apps.* iOS and Google Play look compatible by their documents, and Fledge writes the Xcode and Gradle projects they need. The Microsoft Store can take the setup program Fledge already builds if the developer holds a trusted certificate, or an MSIX, which Fledge does not build. The Mac App Store needs a sandbox, a `.pkg` and provisioning, a different program and not only a different file. Flathub and the Debian and Ubuntu archives refuse prebuilt output by their rules, and Snap and a developer's own repository accept it. No Fledge app has been through any review.
- *Package managers, for console apps.* Scoop, a Homebrew tap, winget, an AUR `-bin` package and mise work today with a text file the developer writes; Fledge writes none. An apt repository needs a console `.deb` and dnf needs an `.rpm`, which Fledge does not build. The Windows launcher may not follow a symlink, which winget uses by default; that is unchecked. Homebrew's official casks require notarization, which costs $99 a year.
- *Self-updating.* Nothing is built. The proposal is that Fledge keeps what any updater needs (a stable identifier, the version in each system's place, one signing identity, a per-user install) and documents each system's own tool.

A new `fledge.yml` key, command, installer or output file is compatible within 1.x, because today's parser refuses every unknown one. So none of these forces a change to what 1.0 freezes. Whether to wait for any of them is a choice about what 1.0 tells developers, not a technical need.

**Default.** 1.0.0 waits for a real-device playtest of a game on both your devices and for nothing in axis 2. The rest is named as unproven or not offered in the README.

**To reverse.** Say what else blocks 1.0.0, or that nothing does. Agents then change the "1.0" story in Plan 003.
