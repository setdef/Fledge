# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "tmpdir"
require_relative "license_audit"
require_relative "../lib/fledge/platform"
require_relative "../lib/fledge/mobile_platform"
require_relative "../lib/fledge/archive"
require_relative "../lib/fledge/version"

# Writes docs/reference/licensing.md, the page that tells developers who build
# apps with Fledge what ships inside each app and what each license asks of
# them, from the license audit of each platform's runtime.
#
# This page comes from the pipeline, never by
# hand, so it holds only what the
# audit finds in the runtimes, what runtime/licenses.yml records of each
# component, and prose that names license sections. Most of a change to
# the page comes from the repository: Fledge's version, the map's names,
# versions, licenses, and words for how each component ships, and this
# file's prose. Only the rest comes from a runtime, and
# runtime/audited.yml records it, as Findings: which of the map's
# components a runtime lacks, the few files the page names, and the
# runtime's gems. So the page is written from runtime/audited.yml and the
# repository, in milliseconds, with no runtime, and a unit test fails
# before a push when it is stale; CI audits the nine runtimes it builds,
# the seven desktops' and the two phones', and fails when either file
# differs from what they say.
#
#   ruby tasks/licensing_page.rb                       # both files, from runtime/audited.yml
#   ruby tasks/licensing_page.rb RUNTIMES_DIR          # both files, from the runtimes
#   ruby tasks/licensing_page.rb --check RUNTIMES_DIR  # exit 1 if either differs from the runtimes
#
# RUNTIMES_DIR holds one fledge-runtime-VERSION-PLATFORM.tar.gz for each
# platform; their contents, not their version, decide the page (a
# runtime's files do not change with Fledge's version), and the page names
# Fledge::VERSION.
class LicensingPage
  PAGE = File.join(LicenseAudit::ROOT, "docs", "reference", "licensing.md")
  AUDITED = File.join(LicenseAudit::ROOT, "runtime", "audited.yml")
  RELEASES = "https://github.com/setdef/Fledge/releases"

  # What a person sees for each platform.
  TITLES = {
    "arm64-darwin" => "macOS on Apple Silicon (arm64-darwin)",
    "x86_64-linux" => "Linux on x86-64 (x86_64-linux)",
    "aarch64-linux" => "Linux on ARM64 (aarch64-linux)",
    "x86_64-linux-musl" => "musl Linux, such as Alpine, on x86-64 (x86_64-linux-musl)",
    "aarch64-linux-musl" => "musl Linux, such as Alpine, on ARM64 (aarch64-linux-musl)",
    "x64-mingw-ucrt" => "Windows on x64 (x64-mingw-ucrt)",
    "aarch64-mingw-ucrt" => "Windows on ARM64 (aarch64-mingw-ucrt)",
    "ios" => "iOS and iPadOS (arm64-ios, arm64-ios-simulator)",
    "android" => "Android (aarch64-linux-android, x86_64-linux-android)",
  }.freeze

  # The platforms the page lists: every desktop's, then each phone's.
  PLATFORMS = [*Fledge::Platform.names, *Fledge::MobilePlatform.names].freeze

  # The platform whose runtime's files of Fledge's the page names, for
  # every desktop.
  OWN_FILES = "x86_64-linux"

  # The Ruby every runtime is made from, for the page's prose.
  RUBY_VERSION_SHIPPED = YAML.safe_load_file(LicenseAudit::SOURCES).fetch("ruby").fetch("version")

  # What the page reads of one platform's runtime that only the runtime
  # can say, as runtime/audited.yml records it: the tree's {prefix} and
  # {abi} (LicenseAudit#prefix, LicenseAudit#abi); the ids of the
  # components runtime/licenses.yml maps for the platform that the
  # runtime does not hold (+absent+); the files the page names, by
  # component id, of each component LicensingPage.files? says (+files+,
  # the files it owns; +embedded+, the files it is compiled into); and the
  # license each gem's specification declares, by the gem's name (+gems+).
  class Findings < Data.define(:prefix, :abi, :absent, :files, :embedded, :gems)
    # The findings of +report+, the audit +audit+ made of +platform+'s
    # tree.
    def self.of(platform, audit, report)
      present = report.present.map(&:id)
      held, lacked = report.components.reject(&:gem_dir).partition { |component| present.include?(component.id) }
      named = held.select { |component| LicensingPage.files?(platform, component) }
      own = held.select { |component| LicensingPage.embedded?(platform, component) }
      new(prefix: audit.prefix, abi: audit.abi, absent: lacked.map(&:id), files: named.to_h { |component| [component.id, report.owned(component)] },
        embedded: own.to_h { |component| [component.id, report.embedded_in(component)] },
        gems: LicenseAudit::Inventory.new(audit).declared_licenses.sort.to_h)
    end

    # The findings runtime/audited.yml records as +entry+.
    def self.from_h(entry)
      new(prefix: entry.fetch("prefix"), abi: entry.fetch("abi"), absent: entry.fetch("absent"), files: entry.fetch("files"),
        embedded: entry.fetch("embedded"), gems: entry.fetch("gems"))
    end

    # These findings without what +components+, the map's components for
    # +platform+, no longer asks of them: an absent id the map no longer
    # lists, and the files of a component the page no longer names. An
    # audit under that map would find the same, so this needs no runtime.
    def within(platform, components)
      listed = components.to_h { |component| [component.id, component] }
      with(absent: absent.select { |id| listed.key?(id) },
        files: files.select { |id, _files| listed.key?(id) && LicensingPage.files?(platform, listed.fetch(id)) },
        embedded: embedded.select { |id, _files| listed.key?(id) && LicensingPage.embedded?(platform, listed.fetch(id)) })
    end

    # The findings as runtime/audited.yml records them.
    def to_h
      { "prefix" => prefix, "abi" => abi, "absent" => absent, "files" => files, "embedded" => embedded, "gems" => gems }
    end
  end

  # What the page needs of a platform: its components but gems, its
  # gems' names by license, and its LGPL libraries, and whether the
  # runtime carries their source in notices/sources/.
  class Summary < Data.define(:components, :gems, :lgpl, :sources); end

  # A component, as the page shows it.
  class Row < Data.define(:name, :version, :license, :ships, :files, :embedded, :first_party); end

  # Whether the page names the files +component+ owns on +platform+: an
  # LGPL library's, whose obligations name them, and Fledge's own, on
  # the platform the page names them from (OWN_FILES).
  def self.files?(platform, component)
    lgpl?(component) || embedded?(platform, component)
  end

  # Whether the page names the files +component+ is compiled into on
  # +platform+: Fledge's own, on OWN_FILES, where bin/ruby holds them.
  def self.embedded?(platform, component)
    component.first_party && platform == OWN_FILES
  end

  # Whether +component+ is an LGPL library, whose obligations the page
  # states, and not its published source.
  def self.lgpl?(component)
    component.kind != "source" && component.license.include?("LGPL")
  end

  # The findings of each platform's runtime archive in +runtimes+, by
  # platform, of every platform or those of +platforms+. Raises when a
  # runtime breaks the license policy.
  def self.audit(runtimes, version: Fledge::VERSION, platforms: PLATFORMS)
    platforms.to_h do |platform|
      archives = Dir.glob(File.join(runtimes, "fledge-runtime-*-#{platform}.tar.gz"))
      raise "#{runtimes} holds no single runtime for #{platform}: #{archives}" unless archives.size == 1

      Dir.mktmpdir("licensing-#{platform}") do |directory|
        Fledge::Archive.unpack(archives.first.to_s, into: directory)
        tree = Dir.glob(File.join(directory, "fledge-runtime-*")).first or raise "#{archives.first} holds no runtime folder"
        audit = LicenseAudit.new(platform:, tree:, fledge_version: version)
        report = audit.call
        raise "the #{platform} runtime breaks the license policy: #{report.violations.first}" unless report.violations.empty?

        [platform, Findings.of(platform, audit, report)]
      end
    end
  end

  # The findings runtime/audited.yml (or +path+) records, by platform.
  def self.load(path = AUDITED)
    parse(File.read(path))
  end

  # The findings +text+, as runtime/audited.yml holds them, records.
  def self.parse(text)
    YAML.safe_load(text).transform_values { |entry| Findings.from_h(entry) }
  end

  # The two files the page's generator writes, by path, from +findings+:
  # runtime/audited.yml and docs/reference/licensing.md.
  def self.files(findings, version: Fledge::VERSION)
    page = new(findings, version:)
    { AUDITED => page.audited, PAGE => page.text }
  end

  def initialize(findings, version: Fledge::VERSION, map: LicenseAudit::MAP, sources: LicenseAudit::SOURCES)
    @version = version
    @map = YAML.safe_load_file(map)
    @sources = YAML.safe_load_file(sources)
    @findings = findings.to_h do |platform, found|
      [platform, found.within(platform, components(platform, found))]
    end
  end

  # runtime/audited.yml: the findings, without what the map no longer
  # asks of them (Findings#within).
  def audited
    <<~HEADER + YAML.dump(@findings.transform_values(&:to_h))
      # SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT
      #
      # Generated by tasks/licensing_page.rb from the license audit of each
      # runtime. Do not edit; CI fails when it is stale. What
      # docs/reference/licensing.md reads of each platform's runtime that only
      # the runtime can say (LicensingPage::Findings): the map's components the
      # runtime lacks, the files the page names, and the license each gem
      # declares.
    HEADER
  end

  # The page, from the findings of each platform's runtime.
  def text
    reports = PLATFORMS.to_h { |platform| [platform, summary(platform)] }
    [
      header,
      everywhere(reports),
      phones(reports),
      app_gems,
      *reports.map { |platform, report| section(platform, report) },
      lgpl(reports),
      footer,
].join("\n")
  end

  # The map's components for +platform+ and the build of Ruby its pin
  # names (LicenseAudit.entries), their words expanded with what
  # +found+ says of the tree.
  private def components(platform, found)
    facts = @map.fetch("platforms").fetch(platform)
    expand = -> (text) { LicenseAudit.expand(text, facts, prefix: -> { found.prefix }, abi: -> { found.abi }, fledge_version: @version) }
    LicenseAudit.entries(@map, @sources, platform).map { |entry| LicenseAudit::Component.from_map(entry, expand) }
  end

  private def summary(platform)
    found = @findings.fetch(platform) { raise stale("records no runtime for #{platform}") }
    components = components(platform, found).reject { |component| found.absent.include?(component.id) }
    components = components.sort_by { |component| [component.first_party ? 0 : 1, component.name.downcase] }
    row = lambda do |component|
      files = LicensingPage.files?(platform, component) ? found.files.fetch(component.id) { raise stale("names no files of #{component.id} on #{platform}") } : []
      embedded = LicensingPage.embedded?(platform, component) ? found.embedded.fetch(component.id) { raise stale("names nothing #{component.id} is compiled into on #{platform}") } : []
      Row.new(name: component.name, version: component.version, license: component.license, ships: component.ships, files:, embedded:,
        first_party: component.first_party)
    end
    corrections = @map.fetch("gems", {})
    gems = found.gems.group_by { |name, declared| corrections.fetch(name, {}).fetch("license", declared) }
    sources, libraries = components.partition { |component| component.kind == "source" }
    Summary.new(components: components.map(&row), gems: gems.transform_values { |list| list.map(&:first).sort }.sort.to_h,
      lgpl: libraries.select { |component| LicensingPage.lgpl?(component) }.map(&row), sources: !sources.empty?)
  end

  # Why the findings cannot write the page: they come from runtimes
  # built before this change, which only runtimes built with it can
  # correct.
  private def stale(what)
    "runtime/audited.yml #{what}, which only a runtime built with this change can say: " \
      "build every platform's runtime and run bundle exec rake \"licensing[DIR]\""
  end

  private def header
    <<~HEADER
      <!--
        SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
        SPDX-License-Identifier: CC-BY-SA-4.0
      -->

      <!-- Generated by tasks/licensing_page.rb from the license audit of each runtime. Do not edit; CI fails when it is stale. -->

      # What Ships Inside an App Built with Fledge, and What Its Licenses Ask of You

      This page lists, for Fledge #{@version}, every third-party component of the runtime that `fledge build` copies into an app on each platform, the license it is under, and what that license asks of you when you give the app to other people. Your app's own gems are yours, not Fledge's, and [their section](#your-apps-own-gems) says what Fledge does with them. Fledge's CI writes it from the same license audit that every runtime must pass before it is published, so it lists what the runtimes hold, not what someone remembered.

      It states facts and cites the sections of each license they come from. It is not legal advice, and it makes no claim about what any license requires of you in your situation: ask your own lawyer.

      Each app carries the same facts in `notices/NOTICES.txt` (every component, its license, and the full text of every license) and `notices/sbom.spdx.json` (an SPDX 2.3 software bill of materials listing every file with its checksums and what each compiled file links). Each [release](#{RELEASES}) publishes both for every platform, beside the runtime they describe, as `fledge-runtime-VERSION-PLATFORM-NOTICES.txt` and `fledge-runtime-VERSION-PLATFORM.spdx.json`.
    HEADER
  end

  private def everywhere(reports)
    ours = reports.fetch("x86_64-linux").components.find(&:first_party) or raise "no runtime holds Fledge's own files"
    <<~EVERYWHERE
      ## On every platform

      **Your own code stays yours.** Nothing in a runtime asks for your app's source code or object files. The GPL appears in a runtime only with an exception that lifts its terms from programs compiled with the code (GCC's runtime library exception, LLVM's exception, Bison's exception) or beside a permissive license you may take instead (Perl's Artistic License, for Ruby's `win32/win32.c`); the LGPL appears only as a separate shared library, or linked into a program that is not Fledge's own and whose source Fledge publishes with the library's (AppImage's runtime, in a Linux app's AppImage). Fledge's license policy (`runtime/licenses.yml`) fails the build of any runtime that holds anything else, including an LGPL library linked into Fledge's launcher, the program your app's users run.

      **Keep the notices.** The permissive licenses below ask that copies of the software keep their copyright notices and license texts: MIT asks that "the above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software"; BSD-2-Clause and BSD-3-Clause ask that a redistribution in binary form "reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution"; Apache-2.0, section 4, asks for a copy of the license and the attribution notices; Ruby is under Ruby's license or, at your choice, BSD-2-Clause. Fledge puts all of them in the app's `notices/NOTICES.txt`; ship the app's folder with its `notices/` folder in it.

      **The CA certificates** (`cert.pem`) are under the Mozilla Public License 2.0, whose obligations attach to the file itself. It ships unmodified, in its source form, which MPL-2.0, section 3.1, asks be distributed under the MPL with word of how to get a copy of it; `notices/NOTICES.txt` holds that copy, and the file's own notices stay intact (section 3.4).

      **A windowed app's installers** hold the app, its `notices/` with them, and on Windows and Linux more of the runtime's components, which its section lists as shipping in `tools/`: a Windows app's setup program is made of NSIS's stub and plug-ins (the zlib license, which asks nothing of a binary) and compressed with NSIS's LZMA module, which is under the Common Public License 1.0: its section 3 asks that a program distributed in object code say that its source is available and how to get it, and Fledge does both, putting NSIS's source in the app's `notices/sources/nsis/`, which the setup program installs with the app, publishing it in `fledge-runtime-VERSION-x64-mingw-ucrt-lgpl-sources.tar.gz` beside each Windows runtime, and saying so in the app's `notices/NOTICES.txt`; and a Linux app's AppImage begins with AppImage's runtime (MIT), as AppImage releases it, with libfuse (LGPL-2.1, as [below](#libraries-under-the-lgpl) says), squashfuse (BSD-2-Clause), zstd (BSD-3-Clause), zlib, mimalloc, and musl (MIT) linked in. A macOS app's disk image holds nothing but the app. Each installer's notices are the app's `notices/`, which it holds: `NOTICES.txt`, and on Linux and Windows the sources in `notices/sources/`.

      **Fledge's own files** in an app are #{own_files(ours)}. Fledge's code in them is Fledge's work, copyright 2026 setdef, under the MIT License, which asks only that its copyright notice and permission notice be included in all copies; `notices/NOTICES.txt` names those files and carries Fledge's license text, so keeping `notices/` meets it.
    EVERYWHERE
  end

  # Fledge's files in a desktop app, as a sentence: the launcher it owns,
  # each file its code is compiled into beside Ruby's (bin/ruby), and
  # its other files.
  private def own_files(ours)
    launcher, *rest = ours.files
    parts = ["`#{launcher}`, the program your app's users run, renamed for your app"]
    parts.concat(ours.embedded.map { |file| "`#{file}`, the Ruby that `RbConfig.ruby` names, which is Ruby's `main.c` with Fledge's code compiled in" })
    parts.concat(rest.map { |file| "`#{file}`" })
    return parts.join if parts.size == 1

    "#{parts[0...-1].to_a.join('; ')}; and #{parts.last}"
  end

  # What the page says of an app for a phone, which is not a
  # copy of the runtime but an app the developer builds from the project
  # fledge build writes, around the runtime's library.
  private def phones(reports)
    ours = reports.fetch("ios").components.find { |row| row.first_party && row.ships.include?("libfledgeruby") } or
      raise "no mobile runtime holds Fledge's embedding API"
    <<~PHONES
      ## On iOS and Android

      For a phone, `fledge build ios` and `fledge build android` write a project that you build into the app. The app links the runtime's library, `FledgeRuby.xcframework` on iOS and `FledgeRuby.aar` on Android, into which Ruby, OpenSSL, libyaml, on Android libffi and the NDK's own compiler support libraries, and #{ours.name.sub(/,.*/, '')} are compiled; it carries Ruby's library, its default and bundled gems, and the CA certificates as files, in its bundle's `fledge/` folder on iOS and in its asset `fledge.zip` on Android; and the project's `fledge/notices/` goes into the app with them, so the app carries `NOTICES.txt` and the SBOM as a desktop app does. Each phone's section below lists the components. None is under the LGPL, so keeping the notices is all they ask of you.

      **Fledge's own code** in a phone's app is #{ours.name.sub(/,.*/, '')}, compiled into the runtime's library, and the host app in the project's template, `Host/main.m` on iOS and `MainActivity.java` on Android, which you compile into the app and may change. Both are Fledge's work under the MIT License, as the desktop launcher is, and ask only that you keep the notices. The project's Gradle wrapper (`gradlew` and `gradle/wrapper/`, Gradle's, under Apache-2.0) builds the app and is not part of it.
    PHONES
  end

  # What the page says of an app's own gems: that they, and their
  # licenses, are the developer's,
  # and where their own notices are in the app.
  private def app_gems
    <<~GEMS
      ## Your app's own gems

      Fledge takes no position on the licenses of the gems your app depends on. Which gems your app uses, and what their licenses ask of you, are your choice and your responsibility, as they are however else you ship a Ruby app. `fledge build` ships every gem your `Gemfile.lock` locks for each platform, in every group `bundle exec` loads, whatever its license, whether or not it declares one, and whatever its compiled files hold. Everything else on this page, the policy and the obligations alike, is about what Fledge itself puts into your app: its runtime.

      Each gem ships as RubyGems or Bundler installs it, with all of its own files, its license files among them, in the app's gem folder (`lib/ruby/gems/4.1.0+5/` on macOS and Linux, `ruby\\lib\\ruby\\gems\\4.1.0+6\\` on Windows, each named for its Ruby's library), and its specification, which declares its license, in that folder's `specifications/`. Fledge writes no notices of its own for your gems: `bundle licenses` lists the license each one's specification declares, and each gem's own notices say what it asks of you. `fledge build` refuses a gem only when it would not run where the app goes: one with an extension that does not compile, one whose `required_ruby_version` excludes Ruby #{RUBY_VERSION_SHIPPED}, or one whose compiled files need a library that neither the operating system, nor the runtime, nor the gem itself provides.
    GEMS
  end

  private def section(platform, summary)
    rows = summary.components.map do |row|
      "| #{cell(row.name)} | #{cell(row.version)} | `#{cell(row.license)}` | #{cell(row.ships)} |"
    end
    gems = summary.gems.map { |license, names| "- `#{cell(license)}`: #{names.join(', ')}" }
    obligations = summary.lgpl.empty? ? "Nothing beyond keeping the notices: no LGPL library ships on this platform." : obligation(platform, summary)
    <<~SECTION
      ## #{TITLES.fetch(platform)}

      | Component | Version | License | How it ships |
      |---|---|---|---|
      #{rows.join("\n")}

      Its #{summary.gems.values.sum(&:size)} default and bundled gems, the ones every Ruby #{RUBY_VERSION_SHIPPED} installs, by the license each one's specification declares (or `runtime/licenses.yml` corrects):

      #{gems.join("\n")}

      **What you must do on this platform:** #{obligations}
    SECTION
  end

  private def obligation(platform, summary)
    libraries = summary.lgpl.map do |row|
      where = row.files.empty? ? "linked into AppImage's runtime" : row.files.map { |file| "`#{file}`" }.join(", ")
      "#{row.name.sub(/,.*/, '')} (#{where})"
    end
    "keep the notices, and meet the LGPL for #{libraries.join(' and for ')}, as " \
      "[below](#libraries-under-the-lgpl) says. The source is #{source_place(platform, summary)}."
  end

  private def source_place(platform, summary)
    bundle = "`#{LicenseAudit::Notices.source_bundle(@version, platform)}`"
    return "#{bundle} in Fledge's release" unless summary.sources

    "in every app, in `#{LicenseAudit::SourceBundle::FOLDER}/`, and in Fledge's release as #{bundle}"
  end

  private def lgpl(_reports)
    <<~LGPL
      ## Libraries under the LGPL

      Three libraries are under the GNU Lesser General Public License: libxcrypt, in Linux apps, as `lib/libcrypt.so.2`, and GNU MP (GMP), in Windows apps, as `ruby\\bin\\ruby_builtin_dlls\\libgmp-10.dll`, each its own shared library, which the app loads when it starts, and which CI proves on every push can be replaced with another build (`ci.yml`, Replace libcrypt and Replace GMP); and libfuse, linked into AppImage's runtime, the program at the front of a Linux app's AppImage, which mounts the app's files and starts the app, never into the app itself. The LGPL asks nothing of your app's own source or object files used either way. It does ask the following of whoever gives the app to others. Fledge does the parts marked as Fledge's; the rest are yours.

      ### libxcrypt (LGPL-2.1-or-later)

      - A prominent notice that the library is used in the app and that it and its use are covered by the LGPL, and a copy of the license (LGPL-2.1, section 6). Fledge's `notices/NOTICES.txt` does this.
      - If your app displays copyright notices while it runs, include the library's among them, with a reference to the license (section 6).
      - Use a suitable shared library mechanism, so that a modified, interface-compatible version the user installs works (section 6(b)). Fledge's layout does this: leave `lib/libcrypt.so.2` a separate file.
      - Make the library's source available, in one of the ways section 6 lists: accompany the app with it (6(a)), offer access to it from the same place you offer the app (6(d)), or include a written offer, valid for at least three years, to give it (6(c)). Fledge puts the exact source, and how its copy was built, into every app, in `notices/sources/libxcrypt/`, so an app that keeps its `notices/` folder is accompanied by the source wherever it goes, as section 6(a) describes, whatever becomes of any server. Fledge also publishes the same folders as the release asset `fledge-runtime-VERSION-PLATFORM-lgpl-sources.tar.gz`, and keeps every release published. Because the license is "or later", you may instead take LGPL-3.0's terms, which convey source by GNU GPL version 3, section 6; its section 6(d) allows the source to be "on a different server (operated by you or a third party)" with "clear directions next to the object code", while you "remain obligated to ensure that it is available for as long as needed".
      - Your app's terms must permit modification of the work for the customer's own use and reverse engineering for debugging such modifications (section 6, first paragraph). This falls on your license agreement, if your app has one.

      ### libfuse (LGPL-2.1-only), in a Linux app's AppImage

      libfuse is linked into AppImage's runtime (MIT), a program of its own that is not your app and not Fledge's launcher; the app inside the AppImage is started by it, and links nothing of libfuse. The LGPL's terms for a work linked with the library apply to that runtime, and Fledge meets the ones that ask for source:

      - A prominent notice that the library is used and is covered by the LGPL, and a copy of the license (LGPL-2.1, section 6). Fledge's `notices/NOTICES.txt`, which the AppImage holds, does this, and so does the runtime's own `--appimage-help`.
      - The complete machine-readable source of the library, and of the runtime it is linked into, so that whoever receives the AppImage can modify libfuse and relink the runtime with it (section 6(a)). Fledge puts both into every Linux app, and so into its AppImage, in `notices/sources/appimage-runtime/` (AppImage's runtime at the commit it was built from, with its build scripts and its patch to libfuse) and `notices/sources/libfuse/` (libfuse's release), which is section 6(a)'s way, and publishes the same folders in `fledge-runtime-VERSION-PLATFORM-lgpl-sources.tar.gz` beside each Linux runtime.
      - Terms that permit modification of the runtime for the customer's own use and reverse engineering for debugging such modifications (section 6, first paragraph) concern the runtime, which is MIT and permits both; your app's own terms need say nothing of it.

      ### GNU MP (LGPL-3.0-or-later OR GPL-2.0-or-later)

      GMP offers a choice of licenses; under the LGPL-3.0 option:

      - A prominent notice that the library is used and is covered by the LGPL (LGPL-3.0, section 4(a)), and copies of the GNU GPL and the LGPL (4(b)). Fledge's `notices/NOTICES.txt` does this.
      - If your app displays copyright notices while it runs, include the library's, with a reference to those licenses (4(c)).
      - Use a suitable shared library mechanism (4(d)(1)). Fledge's layout does this: leave `libgmp-10.dll` a separate file in `ruby\\bin\\ruby_builtin_dlls\\`.
      - Convey the library's Corresponding Source as GNU GPL version 3, section 6 describes, as for libxcrypt above; the source then reaches each person in the same download, or on the same medium, as the app. Every Windows app holds, in `notices\\sources\\gmp\\`, MSYS2's source package of the very build RubyInstaller ships, which CI checks byte for byte, and Fledge's Windows release asset holds it too.
      - Installation Information (4(e)) is needed only where GPL-3.0, section 6, would require it, which is when the app is conveyed in, with, or specifically for use in a "User Product", such as a consumer device it comes installed on.
      - Your app's terms must not restrict modification of the library's portions and reverse engineering for debugging such modifications (section 4, first paragraph).

      Some companies' open-source policies forbid LGPL-3.0 components; if yours does, GMP in Windows apps is the one to raise.
    LGPL
  end

  private def footer
    <<~FOOTER
      ## Where this comes from

      `runtime/licenses.yml` holds the policy and the map of what is compiled into what; `tasks/license_audit.rb` checks each runtime against it as the runtime is built; this page and each runtime's `notices/` come from that audit. Questions about Fledge's own licensing go to the maintainer, through [the repository](https://github.com/setdef/Fledge).
    FOOTER
  end

  private def cell(text)
    text.to_s.gsub("|", "\\|").gsub("\n", " ")
  end
end

if $PROGRAM_NAME == __FILE__
  check = ARGV.delete("--check")
  runtimes = ARGV.first
  abort "usage: licensing_page.rb [[--check] RUNTIMES_DIR]" if check && !runtimes
  findings = runtimes ? LicensingPage.audit(runtimes) : LicensingPage.load
  expected = LicensingPage.files(findings)
  if check
    stale = expected.reject { |path, text| File.exist?(path) && File.read(path) == text }
    if stale.empty?
      puts "docs/reference/licensing.md and runtime/audited.yml match the runtimes"
    else
      stale.each { |path, text| File.write(File.join(runtimes, File.basename(path)), text) }
      names = stale.keys.map { |path| path.delete_prefix("#{LicenseAudit::ROOT}/") }
      abort "#{names.join(' and ')} differ from these runtimes: run bundle exec rake \"licensing[DIR]\" on them and commit both files " \
        "(the expected files are in #{runtimes})"
    end
  else
    expected.each { |path, text| File.write(path, text) }
    puts "Wrote #{expected.keys.join(' and ')}"
  end
end
