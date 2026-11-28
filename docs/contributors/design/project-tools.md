# Project tools

`tasks/` holds Fledge's tooling: the checks before a push, the jobs that keep pins current and `trunk` green, and the steps of a release. None of it ships in the gem. Most of it runs in CI; [CONTRIBUTING.md](../../../CONTRIBUTING.md) says which commands a contributor runs.

## Setting up and checking

| File | Role |
| - | - |
| `setup.rb` (`bin/setup`) | installs the tools `mise.toml` pins and the bundle, quietly, under a lock so two setups don't race, and builds the docs; on CI, puts the gems in the workspace |
| `fast_check.rb` (`bin/check`, `rake check`) | the check before a push: the commits since the base (by default `origin/trunk`), their trailers, and lint on the files they changed |
| `lint.rb`, `lint_files.rb`, `ruby_header.rb`, `rbs_parity.rb` | the lint tasks: which files each linter reads, the Ruby header's form, and that every public method has an RBS signature |
| `test_tiers.rb` | splits the tests into the unit tier and `test/integration`, and refuses a unit test that reads a runtime a build left |
| `adr_digest.rb` (`rake adr:digest`) | prints each ADR's title, problem, drivers, and chosen option |
| `windows_dlls.rb` | writes `lib/fledge/linkage/windows.yml`, the DLLs every Windows has, from a pinned list |

## Keeping pins current

| File | Role |
| - | - |
| `runtime/upstreams.yml` | for each upstream, the pins it moves, where its releases are listed, and any hold, with its reason |
| `pin_watch.rb` | reads every upstream, reports a newer release in the pinned line as the next version and a newer line as news, and fails for an unreadable upstream, an overdue hold, or a line that has ended |
| `pin_move.rb` | moves a pin to a new release: rewrites each pin, its SHA-256, its license entries, and the changelog, from the upstream's digest or a download |
| `download_cache.rb` | CI's cache of pinned downloads, kept apart by pin, with mirrors tried in order |
| `ruby_snapshot.rb`, `ruby_master_status.rb` | build against a snapshot of Ruby's master each night, and open one issue when something breaks |

## Keeping trunk green

| File | Role |
| - | - |
| `build_cop.rb` | when `trunk` turns red, bisects the batch of commits since the last green run, runs the failing jobs again before blaming a commit, and reverts the commit that fails them, unless it is a person's release or pin commit |
| `ci_runs.rb`, `green_walk.rb`, `github_api.rb` | find a commit's green run, walk to the first green commit after a change, and talk to GitHub's API with retries |
| `runnerless_runs.rb` | runs again a run whose only red jobs never got a runner, a bounded number of times |
| `keep_schedules.rb` | re-enables scheduled workflows GitHub disabled, and leaves alone one a person disabled |

## Releasing

| File | Role |
| - | - |
| `release_commit.rb` | picks the next version from the changelog's unreleased entries (a patch for fixes and moved pins; before 1.0, a minor for a breaking change or a removal), writes it in every file that holds the version, and dates the changelog |
| `runtime_pins.rb` (`rake runtime:pin`) | writes `lib/fledge/SHA256SUMS` from the runtimes a CI run built, refusing assets that aren't exactly the release's |
| `release_examples.rb`, `release_archive.rb` | stage the example apps built for each platform as release assets, and check the set is exact |
| `ruby_archive.rb` | builds and publishes a Ruby archive of Fledge's as a pre-release, never overwriting one |
| `rake release` | refuses: no task here publishes to RubyGems.org |

## Traps

- **GitHub's API is shared.** These tools ask GitHub about runs and releases; each retries on failures on GitHub's side, a few times, then stops with what GitHub answered, and never retries a request GitHub refused as wrong.
- **A person's commit is a person's to revert.** `build_cop` never reverts a release, pin, or revert commit; it says so and leaves it.
- **Pins live in several files.** A move rewrites every place `upstreams.yml` lists for its pin, and `test/pin_move_test.rb` checks that each movable pin is named where the move will look.
