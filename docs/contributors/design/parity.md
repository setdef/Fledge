# Parity

Fledge's central promise is that an app's Ruby behaves as it does under `ruby main.rb`, or `bundle exec`. Parity is how the project holds itself to that: it builds probe apps, has them report what Ruby sees, and compares each report with the same probe run under the runtime's Ruby, as a developer would run it. A difference fails the check unless a justification says why it must be.

## The pieces

| Piece | Role |
| - | - |
| `tasks/parity.rb`, `rake parity` | on a desktop: builds the probe and a gem-shaped app, runs each built and as a reference, and compares the reports |
| `Parity::Reports`, `::Difference` | reads a report (the last marked line of output), normalizes paths so the two runs compare, and lists what differs, element by element |
| `Parity::Justification`, and the lists of them for desktops and for phones (`Parity::MOBILE_JUSTIFIED`) | the differences that are right, each with its reason and the platforms it holds on |
| `Parity::Windowed`, `ShellExecute` | the same comparison for a windowed app, started as a desktop starts one |
| `tasks/mobile_parity.rb` and `MobileParity::IOS`, `::Android` | builds the phone probes and apps, runs them on the Simulator and emulators, reads their reports from the log, and compares them with `ruby main.rb` |
| `tasks/ruby_spec.rb`, `rake ruby_spec` | runs ruby/spec under stock Ruby and in a built app, and compares failures, with its own justifications |

## What a report holds

The probe reports facts a program could observe, such as its environment and what requiring `openssl` adds to it, its locale, which gems load (a development gem must, and a file the gemspec requires must), the gem folders RubyGems searches, what a child Ruby sees inside and outside the bundle, and, on a phone, whether `Thread.main` is the thread the process started on. A hash's order doesn't count in a comparison, and an array's does. The reference runs the same probe with the runtime's Ruby, from a person's plain environment, with the first UTF-8 locale the computer has.

## Justifications

A justification is for one fact: it lists the elements of the fact that may differ, the platforms it holds on, and why. Justifications combine element by element, never cover another element of their fact, and hold only where they're listed: a path spelled as Windows spells it is justified only in the run that spelled it, and a UTF-8 locale in place of C only when the environment named no locale. `test/parity_justified_test.rb` fails when an entry is added or widened, so that each new justification shows in a test's failure.

## Traps

- **Normalize, don't loosen.** When two reports differ only by where the app is, the fix is in `Reports`' normalization of paths, longest first; a justification that allows any value hides real differences.
- **A phone's report arrives in pieces.** Logs split long lines, so `MobileParity` reassembles the report from log entries, launches the probe again when the log cut it short, and fails after a few tries.
- **Parity runs on each platform.** Its differences are platform-specific, so a justification for one platform proves nothing about another.

## What parity doesn't do

- Test an app's behavior: it checks that the app's Ruby is the Ruby its developer ran.
- Excuse a difference that could be closed. Only a difference Fledge can't remove gets a justification; any other is a bug in the runtime or the launcher.
