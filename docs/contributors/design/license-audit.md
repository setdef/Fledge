# License audit

Every app carries a runtime, so a runtime's licenses are every app developer's. Fledge's policy is that a runtime carries no obligation beyond keeping its notices: no GPL or AGPL code, and LGPL code only as a separate library a person can replace, with its source published beside the runtime. The license audit enforces that on each runtime as it is built, and writes the notices and the SBOM the release publishes. It never judges an app's gems, which are the developer's choice.

## The pieces

| Piece | Role |
| - | - |
| `runtime/licenses.yml` | the license map: each component of every runtime, the files that belong to it, its SPDX license expression, its notice text, and how it is linked; plus each platform's system libraries and the byte signatures that find a component compiled into another file |
| `runtime/audited.yml` | what the audit found in each platform's runtime, generated: each gem's license, the files it accounted for, and what it found embedded |
| `LicenseAudit` | audits one runtime tree for a platform: owns every file by its most specific component, reads compiled files' needs, and applies the policy |
| `LicenseAudit::Inventory`, `::Component`, `::Binaries` | the files and their owners; one component; what each compiled file needs and what is compiled into it |
| `LicenseAudit::Policy`, `Fledge::LicensePolicy` | categorizes an SPDX expression, taking the least restrictive alternative of an `OR` and the most restrictive part of an `AND`, and says what each category requires |
| `LicenseAudit::CopyleftText` | finds copyleft license text in files, such as inside a cached gem, which must have been reviewed |
| `LicenseAudit::Notices`, `::Spdx`, `::SourceBundle` | write the runtime's `NOTICES`, its SPDX SBOM accounting for every file and link, and the bundle of LGPL components' sources and build instructions |
| `LicenseAudit::Report`, `::Violation`, `::Failure`, `::CLI` | the result, each breach of the policy, and the command CI runs |
| `LicensingPage` | writes `docs/reference/licensing.md` and `runtime/audited.yml` from every platform's runtime |

## The categories

`LicensePolicy` puts every license in one of five categories, from least to most restrictive:

| Category | Licenses | What a runtime may do with it |
| - | - | - |
| notice only | MIT, BSD, Apache-2.0, ISC, Zlib, Ruby, PSF-2.0, the Unicode licenses, and the rest of `NOTICE_ONLY` | anything, keeping its notice |
| file level | MPL-2.0, EPL-2.0 | ship its files unmodified, with its notice |
| source offer | CPL-1.0 | ship it with its source published |
| shared library | the LGPL versions | ship it only as its own shared library, which nothing of Fledge's links, with its source and how to replace it |
| forbidden | everything else, GPL and AGPL included, and any expression the policy can't read | nothing: the audit fails |

A license `WITH` an exception the policy lists (the GCC runtime exception, Bison's, LLVM's) is notice only.

## What the audit refuses

- A file no component owns, or a compiled file its component doesn't list.
- A library a compiled file needs that neither the system nor the runtime provides.
- LGPL code inside another file, found by its byte signatures (`libxcrypt` linked into `bin/ruby`, say), or an LGPL library linked into the launcher or any binary whose source isn't published.
- A component whose license asks for its source, without the source published.
- A gem in the runtime under a forbidden license, one that declares none, or a cached gem holding copyleft text nobody reviewed.
- A CA bundle that isn't the one its entry pins, and a component whose version changed from the pin.
- On macOS, a Mach-O file that needs a newer macOS than the floor, or declares none.

The audit runs inside every runtime build, so a runtime that breaks the policy is never archived, and runs again on each platform's archive when `docs/reference/licensing.md` is regenerated.

## Traps

- **Add the component first.** A new library in a runtime fails the audit until its entry in `licenses.yml` lists its files, license, and notice. Write the entry before the pin in `sources.yml`.
- **Generated files are generated.** `docs/reference/licensing.md` and `runtime/audited.yml` say so in their headers; change `tasks/licensing_page.rb` or the map, and regenerate with `rake licensing[DIR]`.
- **The notices describe the runtime alone.** They say so, and point at the release's source bundle; an app's gems and code are the developer's to give notices for.

## What the audit doesn't do

- Judge the gems an app depends on. `fledge build` ships a gem whatever its license.
- Give legal advice. `docs/reference/licensing.md` cites the licenses' sections and says to ask a lawyer.
