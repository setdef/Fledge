<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Contributing

Fledge's code, tests, and documents are written by LLM agents at the maintainer's direction. The gates in CI, and the Delivery jobs that run a built app on a clean computer, are the review.

## Ask for what you want

Open an [issue](https://github.com/setdef/Fledge/issues). Describe the problem or the feature, the platform you build on, the platform you run on, and what `bundle exec fledge --version` prints. The maintainer decides what Fledge does, and an agent builds it.

## Work on Fledge

Start with [AGENTS.md](AGENTS.md), which is binding, then read:

- [`doc/contributors/handoff.md`](doc/contributors/handoff.md): where the project stands, how to check it, and how to release it.
- [`doc/contributors/decisions.md`](doc/contributors/decisions.md): the maintainer's own words, which are the only authority.
- [`doc/contributors/plan/`](doc/contributors/plan): the plans, with the current one last.
- [`doc/contributors/adr/`](doc/contributors/adr): the decisions behind each behavior.
- [`doc/contributors/documentation_style.md`](doc/contributors/documentation_style.md): how to write the documents.

Run `bundle exec rake rubocop:autocorrect_all`, then `bundle exec rake`. The second command is the gate: it must pass with zero errors and zero warnings.
