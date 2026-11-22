<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Publishing Fledge 1.0.0 on RubyGems.org

This is the maintainer's checklist for publishing the gem. Fledge is a single pure-Ruby gem, `fledge`, so each release is one push. Agents wrote this page (AGENTS.md, Provenance) from the maintainer's words: nothing goes to RubyGems.org before 1.0.0, from 1.0.0 the gem is published there as well, and every release still has its git tag and GitHub Release (decisions, 2026-11-03 and 2026-11-04); and a deterministic process he decides to trust with the push, such as a GitHub Actions workflow, counts as his act (decisions, 2026-11-22). So `release.yml` pushes the gem, once you have set RubyGems.org to trust it and told the workflow so, and you never type `gem push` unless that fails. The release tooling (`rake bump:*`, `release:update_stable`) does not block 1.0.0; releases through 1.0.0 are made by hand, as `doc/contributors/design/releases.md`, "How a release is made", says (decisions, 2026-11-07). The runtimes still come from the GitHub Release, which the gem's pins check, so the tag and the Release come first and the push comes last.

## Who does what

Agents prepare 1.0.0: the release commit, the pin commit, the tag, and the GitHub Release, exactly as for any release (`doc/contributors/design/releases.md`, "How a release is made"). They never run `gem push` or `gem signin`, never touch RubyGems.org, and never set up its trust (AGENTS.md, Releasing). They do not change `allowed_push_host` before the 1.0.0 release commit, which is the commit that changes it.

You set up the trust ("Trust the release workflow", below), before the 1.0.0 tag. `release.yml`'s last job, "Publish the gem on RubyGems.org", then pushes each release from 1.0.0 on, after `installed.yml` has installed that very `.gem` and delivered apps with it on every platform. It does nothing for a 0.x version, and nothing until you set the variable below.

## What the 1.0.0 release commit changes

As it stands, a push is refused twice over. `fledge.gemspec` sets `spec.metadata["allowed_push_host"] = "https://fledge.invalid"`, and `gem push` refuses any host but that one. `tasks/package.rake` clears Bundler's `release` task and replaces it with one that aborts, so `rake release` does nothing. The 1.0.0 release commit, `chore: release 1.0.0`, makes the gem pushable, in addition to the usual version bump (`doc/contributors/design/releases.md`, "How a release is made"):

1. **`fledge.gemspec`**: set `allowed_push_host` to `"https://rubygems.org"`, and rewrite the comment above it, which says a stray push is kept from publishing. Leave `rubygems_mfa_required` set to `"true"`: RubyGems then refuses a push from an account without multi-factor authentication.
2. **`test/version_test.rb`**: `test_gemspec_cannot_be_pushed_to_rubygems` asserts the invalid host. Change it to assert `https://rubygems.org` and `rubygems_mfa_required`, so the host cannot change unnoticed.
3. **`tasks/package.rake`**: keep `rake release` refusing, and say why in its comment: you push with `gem push`, by hand, and `rake release` would also push a branch and a tag, which the release process makes with git commands (`doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing", until the extracted tooling arrives). The abort message and comment stop saying that releases are never on RubyGems.org.
4. **`README.md` and `README.rdoc`**: change the install line from a git tag to a version constraint, `gem "fledge", "~> 1.0", group: :development`, and rewrite the sentence after it in README.md ("Fledge installs from a git tag") so the page says Fledge installs from RubyGems.org, and that every release is also a git tag and a GitHub Release. The release step that swaps the old version for the new one in these files then has no tag to swap there. `test/workflow_installed_test.rb` then fails until `installed.yml`'s `installed`, `installed-musl`, and `installed-mobile` jobs write the new line too, in hello's Gemfile and the Gemfile of Fledge's own, and install from the `.gem` the `gem` job builds from the tag (`gem install --local`, then `bundle install --local`), since RubyGems.org has nothing until you push; change the test's tag substitution, and the rewrite that puts a `commit` input's ref where that line names the tag, in the same commit. The gem's description is `README.rdoc` (`spec.description`), so RubyGems.org shows what you push; read both files start to finish, as AGENTS.md says, before the commit.
5. **Statements that the gem is never published**: `AGENTS.md` (Releasing, "The gemspec's `allowed_push_host` points nowhere, and `rake release` refuses") and `doc/contributors/design/releases.md` ("Where releases are") are true before this commit and false after it. Correct each to say what the code then does, and leave the rule that agents never push there.
6. **`CHANGELOG.md`**: under `## [1.0.0]`, one line saying that Fledge is also on RubyGems.org, and installs with `gem "fledge", "~> 1.0"`.

Then `cut.yml` makes the release commit and the pin commit, tags the pin commit, and runs `release.yml`, which publishes the GitHub Release and then the gem, all as `doc/contributors/design/releases.md`, "How a release is made", describes. The tagged commit is the pin commit, which changes only `lib/fledge/SHA256SUMS`, so it carries the six changes above from its parent.

## Trust the release workflow

Do this once, before the 1.0.0 tag. The steps are RubyGems' own ("Trusted Publishing", `trusted-publishing.md` in the `rubygems/guides` repository on GitHub, as of its commit of 2026-07-27).

1. Your RubyGems.org account has multi-factor authentication on. The gem asks for it (`rubygems_mfa_required`).
2. Nobody has taken the name. On 2026-11-08, `https://rubygems.org/api/v1/gems/fledge.json` answered 404. Check again.
3. Since `fledge` is not on RubyGems.org yet, add a *pending* trusted publisher, which becomes the gem's trusted publisher on its first push and makes you the gem's owner: on https://rubygems.org/profile/oidc/pending_trusted_publishers, choose Create, and enter the gem name `fledge`, the repository owner `setdef`, the repository name `Fledge`, the workflow filename `release.yml`, and the environment `release`. Leave the two "Workflow Repository" fields blank: the job is in `release.yml` itself, not in a reusable workflow from elsewhere.
4. Tell the workflow it may push: `gh variable set RUBYGEMS_TRUSTED_PUBLISHING --body true --repo setdef/Fledge`. Until this variable is `true`, the job is skipped, so a tag made before you finish the steps above publishes the GitHub Release alone.

GitHub creates the environment `release` the first time a job names it. You may give it rules in the repository's settings (Environments); a rule that asks for a reviewer puts you back in the loop for every release, which the pin watch's releases were built to avoid, and a rule that limits it to tags would refuse `cut.yml`'s dispatch of `release.yml`, which runs on `trunk` with the tag as an input.

To stop the workflow publishing, set the variable to anything but `true`, or remove the trusted publisher on the gem's page ("Trusted publishers").

## Before the tag

- Your testing that is blocked on your developer accounts is done, if you decided it must come before the tag (`questions.md`, C).
- The trust is set up, as above.

## After the tag

Watch the release run with `gh run list --workflow release.yml --limit 2`. Its Installed jobs install Fledge from the tag on every platform and deliver apps with the published runtimes, and only when all pass does its last job push the gem. Then "Confirm", below.

## If the workflow does not push

The job's run fails, which reaches you as any failed run of a workflow you started or own does. RubyGems' guide does not say whether a gem that requires multi-factor authentication (`rubygems_mfa_required`) accepts a trusted publisher's key without a one-time password; the first push shows it. If it refuses, or the trust is not set up, push by hand as below, and fix the trust before the next release. The tag and the GitHub Release are already published, and the gem is the only part missing.

## Build the gem from the tag

`fledge.gemspec` lists its files with `git ls-files`, so build in a clean checkout of the tag, with nothing untracked beside it.

```
git clone --branch v1.0.0 https://github.com/setdef/Fledge.git fledge-1.0.0
cd fledge-1.0.0
git describe --tags --exact-match
gem build fledge.gemspec
```

`git describe` prints `v1.0.0`. `gem build` writes `fledge-1.0.0.gem`.

## Verify it

1. **Version and host**: `gem specification fledge-1.0.0.gem version` prints `1.0.0`, and `gem specification fledge-1.0.0.gem metadata` prints an `allowed_push_host` of `https://rubygems.org` and `rubygems_mfa_required: 'true'`. If the host is still `https://fledge.invalid`, stop: the release commit missed item 1.
2. **Contents**: `gem contents` reads installed gems only, so list the file: `tar -xOf fledge-1.0.0.gem data.tar.gz | tar -tzf -`. It lists `exe/fledge`, `lib/`, `sig/`, `README.rdoc`, `CHANGELOG.md`, `LICENSE`, and `LICENSES/`, and none of `test/`, `tasks/`, `doc/`, `examples/`, or `.github/` (`rake package:check` fails when the gem packs one).
3. **The pins**: `lib/fledge/SHA256SUMS` is in that list, and it is the release's file byte for byte. Unpack with `gem unpack fledge-1.0.0.gem`, download the release's with `gh release download v1.0.0 --pattern SHA256SUMS --dir /tmp/release-pins`, and `diff fledge-1.0.0/lib/fledge/SHA256SUMS /tmp/release-pins/SHA256SUMS` prints nothing. A gem without it cannot check a single runtime (`doc/contributors/design/releases.md`, "The pins").
4. **It runs**: in an empty `GEM_HOME`, `gem install --local --no-document --install-dir /tmp/fledge-home fledge-1.0.0.gem`, then `GEM_HOME=/tmp/fledge-home ruby /tmp/fledge-home/bin/fledge --version` prints `fledge 1.0.0`. This is `rake package:check`'s test; run it again on the file you are about to push.

## Push

1. Sign in once: `gem signin` (it asks for your RubyGems.org login, and a key scope that includes pushing new gems).
2. `gem push fledge-1.0.0.gem`. RubyGems asks for your one-time password. A push cannot be undone: `gem yank` hides a version but never frees its number.

## Confirm

1. `https://rubygems.org/gems/fledge` shows 1.0.0, MIT, and the README as the description. The changelog link points at `CHANGELOG.md` on `trunk`.
2. In a clean directory with a `Gemfile` holding `gem "fledge", "~> 1.0", group: :development`, `bundle install` resolves 1.0.0 from RubyGems.org, and `bundle exec fledge --version` prints `fledge 1.0.0`. `bundle exec fledge build` on a small project downloads the runtime from the GitHub Release and checks it against the gem's pins.
3. The tag and the GitHub Release are still there. They stay: a release is findable by either (decisions, 2026-11-04), and each runtime's NOTICES links its LGPL sources to the Release (AGENTS.md, Releasing).

## After 1.0.0

Release branches, backports by `git cherry-pick -x`, `stable`, and `rake release` as the maintainer's command follow `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing", once RatatuiRuby's `ratatui_ruby-devtools` is extracted for Fledge (decisions, 2026-11-07). Nothing there blocks 1.0.0, and this page is replaced when it lands.
