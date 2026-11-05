# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. Who may host Fledge's runtimes besides GitHub, and where?

**Question.** Each Fledge release's runtimes (a few hundred megabytes in all) and the source of the LGPL libraries in them are files on its GitHub Release, and `fledge build` downloads a runtime from there, checking it against SHA-256 values the gem carries, so any other host would serve the same bytes safely. If GitHub changed the terms for release files, every download would break. Which second place may Fledge use for them, and may an agent create an account there? Your repositories for RatatuiRuby and Rooibos already mirror to SourceHut; I haven't checked whether it can serve release files, or what it costs.

**Default.** Fledge keeps GitHub as the only host and gains an environment variable that names another place to download from, so a developer or an organization can host its own. No account is created and no money is spent (decisions, 2026-11-02).

**To reverse.** Name the host and say whether an agent may open the account. Agents then add it as a second default location, mirror each release's files to it, and test that a build works with GitHub unreachable.

## B. How should the LGPL source offer outlive GitHub?

**Question.** Every app Fledge builds carries a `NOTICES.txt` that says where to get the source of its LGPL libraries (libxcrypt on Linux, GNU MP on Windows, and libfuse in the AppImage runtime): the GitHub Release of the Fledge version that built it, where Fledge promises never to delete a release. If GitHub went away, that statement in every app already shipped would name a place that is gone. Two ways to remove the dependency are open. The sources go inside each runtime beside its notices, which adds a few megabytes to every app and keeps the offer true wherever the app goes; or the notices point at the libraries' own upstream archives by version and hash, which adds nothing to an app but depends on those hosts staying up. Which do you accept? This is a reading of the LGPL's section 6 and of your rule that a developer who buys a commercial license owes no copyleft obligation beyond notices (decisions, 2026-10-26, items 8 and 24), so it is yours.

**Default.** Neither changes: the source stays on the GitHub Release, as today.

**To reverse.** Choose one. Agents then change the runtime builder and the notices, and the license audit checks the new place.

## C. What is the least that must be proven before 1.0.0?

**Question.** You wrote that there is no 1.0 until "at least some of these things are proven", meaning an iPhone or iPad run on a real device and App Review, a signing chain a real Apple or Microsoft certificate makes, and Android's arm64-v8a build running. Today none of the three is proven, and the last two cost money you have said not to spend. Which of them is the minimum for 1.0.0: only a real-device playtest of a game on your iPad Pro and your OnePlus Nord, or more? Anything not proven would be named as unproven in the README.

**Default.** 1.0.0 waits for the real-device playtest of a game on both of your devices, and names the rest as unproven.

**To reverse.** Say which others also block 1.0.0, or that none does. Agents then change the 1.0 story in Plan 003.
