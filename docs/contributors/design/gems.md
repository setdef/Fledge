# Gems

This part turns a project's `Gemfile.lock` into the files of an app's gems, laid out as RubyGems and Bundler lay them out, compiled for the runtime's Ruby, and judged: every compiled file must be able to load on another computer of the platform. It ships exactly what `bundle exec` would set up there, and nothing a developer's Ruby installed.

## The pieces

| Piece | Role |
| - | - |
| `Bundle` | reads the Gemfile and lockfile into Bundler's definition, frozen, and answers which gems a platform gets, and the settings the app's `.bundle/config` carries |
| `Bundle::Selection` | walks the Gemfile's dependencies for a platform and groups, and picks each gem's best locked build as Bundler would |
| `Bundle::Sources` | turns each locked spec into a gem value by its source: `LockedGem` (a gem server), `GitGem`, or `PathGem` |
| `Bundle::GemspecLoads` | evaluates a gemspec in a child Ruby to record the project files its evaluation loaded |
| `AppGems` | drives the rest for one platform: packages, compilation, executables, problems, and the entries to write |
| `GemFetcher` | finds a `.gem` file whose SHA-256 matches the lockfile's, in the project's `vendor/cache`, RubyGems' caches, or Fledge's, or downloads it |
| `GitCheckout` | clones a git gem's repository into a cached bare mirror, and checks out the locked commit |
| `GemPackage`, `GitPackage`, `PathPackage` | one gem's files, in the layout `gem install` or Bundler gives it, and its problems |
| `CompiledGem` | a package with what its build left: compiled files, extension files, and build info |
| `NativeBuild` | compiles packages with extensions, and writes gems' executables, by running scripts on the runtime's Ruby (`NativeBuild::RuntimeRuby`) |
| `NativeBuild::Floors`, `::Skipped`, `::BuiltFiles` | the oldest macOS and glibc a compiled file needs; extensions that built nothing; which built files ship |
| `Linkage`, `Linkage::Dyld` | judges whether each compiled file's needed libraries are provided where it will load |
| `Binary`, `Binary::Readers` | reads compiled files' needs, run paths, processors, and floors, with `objdump` or `llvm-readobj` |
| `CarriedLibraries` | copies listed macOS libraries into the app, and points the files that load them at the copies |
| `VisualCRuntime` | copies the Visual C++ runtime's DLLs, and the DLLs they need, from System32 |
| `GemWrapper` | writes a gem executable's wrapper for Android, as RubyGems writes it |

## The lockfile is the truth

Fledge never resolves. `Bundle` builds Bundler's definition with the lockfile frozen, so a Gemfile that moved past it fails in Bundler's words, and every gem that ships is the one the lockfile locks: from a server, checked against its entry in `CHECKSUMS`; from git, at the full revision locked; from a folder, at the version locked. The platform check accepts a lockfile that locks the platform, its generic form, or `ruby`. A Mac lockfile locked for another Darwin version is rewritten for the runtime's, as `bundle exec` would write it, and that rewritten lockfile ships in the app.

`Selection` follows Bundler's rules, not its code paths: dependencies of the requested groups, filtered by `platforms:` and `install_if`, each gem's best platform match, with the source build when a precompiled one's `required_ruby_version` excludes the runtime's Ruby. The groups are those Bundler's settings request (`without`, `with`, `only`), so development and test gems ship, as `bundle exec` sets them up, and the app's `.bundle/config` records the same settings for the launcher.

## Packages, and where their files go

Each package answers the same questions: its spec, whether it has extensions, its files, its problems, and the entries that install it under the runtime's gem folder. A server gem installs as `gem install` lays it out, with its spec in `specifications` and its `.gem` in `cache`; a git gem where Bundler keeps git gems (`bundler/gems/NAME-REVISION`); a path gem in the app's copy of the project, or, from outside the project, in `app/vendor/cache/NAME`, where Bundler looks for it. A gem the runtime already holds at the same version is the runtime's, and ships nothing.

On a phone, `AppGems` marks each extension's folder as built, so RubyGems loads the gem without a compiled file there, and leaves the compiling to [Phone projects](phone-projects.md).

## Compiling with the runtime's Ruby

`NativeBuild` unpacks the runtime into the work folder, writes a plan of jobs as JSON, and runs a script on the runtime's `ruby` that installs each gem with `Gem::Installer`, or builds a git or path gem's extensions with `Gem::Ext::Builder`, and writes back where each landed. The gems compile as `gem install` compiles them, with the runtime's `rbconfig`, headers, and libraries, so their compiled files link what the app has. Dependencies compile first, in order, so an extension that builds against another gem finds it.

The script's environment is the developer's minus `RUBY*`, `GEM_*`, `BUNDLE_*`, and `BUNDLER_*`, with `GEM_HOME` the work folder, the runtime's `pkgconfig` and headers first on the search paths and the developer's Ruby's taken off them, and `MACOSX_DEPLOYMENT_TARGET` set to the platform's oldest macOS. On Windows, the script puts RubyInstaller's MSYS2 toolchain on `PATH`, as `gem install` does. A second script writes each gem's executables with RubyGems' wrapper.

After the build, `BuiltFiles` keeps what the build left in the gem's folder that the package didn't hold, so a gem whose build writes files outside its extension folder ships them where its Ruby looks.

## Judging compiled files

Every compiled file the app's gems carry passes `Linkage` for the platform. A file for another processor or another system's loader is never judged, since it is never loaded. A needed library passes when the system provides it (a fixed list for each OS, and every DLL in `linkage/windows.yml`), the runtime ships it, the gem itself carries it, or `fledge.kdl` lists it (`system-libraries`, `carried-libraries`, `host-libraries`, `visual-c-runtime`). Everything else is a refusal, grouped one per file, with the `fledge.kdl` line that would allow it where one could. On macOS, `Linkage::Dyld` follows `@rpath` and `@loader_path` through the run paths of each file and of the files that load it, as dyld does, so a library the gem carries but no run path reaches is refused too.

`Floors` reads each file's oldest macOS (a refusal above the platform's) and newest glibc symbol (a warning above 2.28, and the figure `fledge.cfg` and a `.deb` record).

`Linkage#unused` refuses a listed library nothing needs, so `fledge.kdl` can't carry stale entries.

## Reading compiled files

`Binary` reads files' formats by their first bytes, then hands batches to the platform's reader: `objdump -p` for ELF and Mach-O on macOS and Linux, and on Windows the `llvm-readobj` that Windows runtimes carry in their tools folder. Each dialect module turns a tool's text into `Binary` values. Reading needs a tool, so a build whose gems hold compiled files needs `objdump` on macOS and Linux; one without needs nothing.

## Traps

- **Bundler is process state.** Everything here that evaluates a Gemfile does it inside `Bundle#at_project`, which sets and restores `BUNDLE_GEMFILE` and resets Bundler's settings and root around it. The fledge process is itself running under the developer's Bundler.
- **What a gemspec prints is not the build's output.** Gemfile and gemspec evaluations run inside `Evaluation.to_stderr`, which points standard output at standard error.
- **A cached file is not trusted by its name.** `GemFetcher` and `Download.save` check every file against its SHA-256, wherever it came from, and a downloaded file lands only once it matches.
- **Credentials stay with their host.** A gem server's login comes from Bundler's settings, goes only to that host (not to a redirect elsewhere), and never into a message.

## What this part doesn't do

- Resolve, update, or install gems for the developer's Ruby.
- Judge a gem by its license. A gem ships whatever its license and whatever its compiled files hold, as long as they can load.
- Use the gems the developer's Ruby installed. Every gem is installed again from its `.gem` file, checkout, or folder, so that what ships is what the lockfile locks, compiled for the app's Ruby.
