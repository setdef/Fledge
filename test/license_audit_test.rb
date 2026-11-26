# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# SPDX-FileComment: Adapted from test/license_audit_test.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require_relative "test_helper"
require_relative "support/binaries"
require_relative "support/ca_bundles"
require_relative "../tasks/license_audit"
require "stringio"

# The license audit against small runtime trees shaped like a Linux
# runtime, built from real (minimal) ELF files and gem specifications,
# and checked against the real runtime/licenses.yml. CI runs it against
# the four real runtimes and the whole trees they come from.
class LicenseAuditTest < Minitest::Test
  RUST = "/rustc/db9d1b20bba1968c1ec1fc49616d4742c1725b4b/"
  ARCH = "lib/ruby/4.1.0+5/x86_64-linux"

  def setup
    TestReaders.need(self, :elf)
    @tree = Dir.mktmpdir("license-audit")
    write("launcher", Binaries.elf(needed: %w[libcrypt.so.2 libm.so.6 libc.so.6 ld-linux-x86-64.so.2],
      payload: "ruby 4.1.0preview1 (revision 2d08b5f42f) #{RUST} GCC: (Ubuntu 13.3.0)"))
    write("lib/libcrypt.so.2", Binaries.elf(needed: %w[libc.so.6], payload: "XCRYPT_4.4\0yescrypt-ROMhash"))
    write("#{ARCH}/openssl.so", Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL 3.5.5 "))
    write("lib/ruby/4.1.0+5/set.rb", "class Set; end\n")
    write("lib/ruby/4.1.0+5/rubygems/defaults/operating_system.rb", "# Fledge's RubyGems defaults for a built app.\n")
    write("libexec/cert.pem", CaBundles.jdx)
    write_gem("csv", "3.3.5", ["Ruby", "BSD-2-Clause"])
  end

  def teardown
    FileUtils.rm_rf(@tree) if @tree
  end

  def write(path, content)
    full = File.join(@tree, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, content)
  end

  def write_gem(name, version, licenses, executables: [])
    spec = Gem::Specification.new do |gem|
      gem.name = name
      gem.version = version
      gem.summary = name
      gem.authors = ["someone"]
      gem.licenses = licenses
      gem.executables = executables
    end
    write("lib/ruby/gems/4.1.0+5/specifications/#{name}-#{version}.gemspec", spec.to_ruby)
    write("lib/ruby/gems/4.1.0+5/gems/#{name}-#{version}/lib/#{name}.rb", "module #{name.capitalize}; end\n")
    write("lib/ruby/gems/4.1.0+5/gems/#{name}-#{version}/LICENSE.txt", "#{licenses.join(' or ')}\n")
  end

  # Writes RubyGems' cache/NAME-VERSION.gem holding +files+, as the tar
  # of metadata.gz and data.tar.gz that RubyGems writes.
  def write_cached_gem(name, version, files)
    data = StringIO.new(+"".b)
    Gem::Package::TarWriter.new(data) { |tar| files.each { |path, bytes| tar.add_file(path, 0o644) { |io| io.write(bytes) } } }
    gem = StringIO.new(+"".b)
    Gem::Package::TarWriter.new(gem) { |tar| tar.add_file("data.tar.gz", 0o444) { |io| io.write(Zlib.gzip(data.string)) } }
    write("lib/ruby/gems/4.1.0+5/cache/#{name}-#{version}.gem", gem.string)
  end

  def audit
    LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0").call
  end

  def rules(report)
    report.violations.map { |violation| [violation.rule, violation.path] }
  end

  def test_a_runtime_of_permissive_code_and_a_replaceable_lgpl_library_meets_the_policy
    report = audit

    assert_empty report.violations.map(&:to_s)
    assert_equal %w[fledge gem-csv-3.3.5 libxcrypt openssl-jdx ruby rust-std-jdx ca-certificates-jdx gcc-runtime].sort, report.present.map(&:id).sort
    assert_equal "lib/libcrypt.so.2", report.links.fetch("launcher").fetch("libcrypt.so.2")
    assert_equal :system, report.links.fetch("launcher").fetch("libc.so.6")
  end

  def test_each_file_belongs_to_the_most_specific_component
    owners = audit.owners.transform_values(&:id)

    assert_equal "fledge", owners.fetch("lib/ruby/4.1.0+5/rubygems/defaults/operating_system.rb")
    assert_equal "ruby", owners.fetch("lib/ruby/4.1.0+5/set.rb")
    assert_equal "gem-csv-3.3.5", owners.fetch("lib/ruby/gems/4.1.0+5/gems/csv-3.3.5/lib/csv.rb")
    assert_equal "libxcrypt", owners.fetch("lib/libcrypt.so.2")
  end

  # A preview's folders are named for its ABI (4.1.0+5), and a snapshot
  # of Ruby's master may name another (4.1.0+6): the tree says which.
  def test_the_folders_of_rubys_library_are_named_as_the_tree_names_them
    FileUtils.mv(File.join(@tree, "lib/ruby/4.1.0+5"), File.join(@tree, "lib/ruby/4.1.0+6"))
    FileUtils.mv(File.join(@tree, "lib/ruby/gems/4.1.0+5"), File.join(@tree, "lib/ruby/gems/4.1.0+6"))
    report = audit

    assert_empty report.violations.map(&:to_s)
    assert_equal "ruby", report.owners.fetch("lib/ruby/4.1.0+6/set.rb").id
    assert_includes report.present.find { |component| component.id == "gem-csv-3.3.5" }.ships, "lib/ruby/gems/4.1.0+6/gems/csv-3.3.5"
  end

  def test_a_tree_with_two_ruby_libraries_is_refused
    write("lib/ruby/4.0.0/set.rb", "class Set; end\n")

    error = assert_raises(ArgumentError) { audit }
    assert_equal "#{File.expand_path(@tree)} holds more than one Ruby library: 4.0.0/, 4.1.0+5/", error.message
  end

  def test_a_file_no_component_owns_fails
    write("stray.txt", "hello\n")

    assert_includes rules(audit), ["unaccounted", "stray.txt"]
  end

  def test_a_compiled_file_its_component_does_not_list_fails
    write("#{ARCH}/gpl_thing.so", Binaries.elf(needed: %w[libc.so.6]))

    assert_includes rules(audit), ["unlisted-binary", "#{ARCH}/gpl_thing.so"]
  end

  def test_libxcrypt_compiled_into_another_file_fails
    write("bin/ruby", Binaries.elf(needed: %w[libc.so.6], payload: "#{RUST} yescrypt-ROMhash"))

    assert_includes rules(audit), ["static-copyleft", "bin/ruby"]
  end

  # AppImage's runtime as AppImage builds it: static, with libfuse (LGPL)
  # and permissive libraries linked in, each proven by its own string.
  APPIMAGE_RUNTIME = "https://github.com/AppImage/type2-runtime/commit/dd6cebe 3.15.0 squashfuse 0.5.2 1.5.6 inflate 1.3.1 " \
    "musl libc, licensed under the terms of mimalloc: GCC: (Alpine 14.2.0) 14.2.0 fuse: unsupported protocol version: "

  # libfuse may be linked into AppImage's runtime, which is not Fledge's
  # own, because Fledge publishes the runtime's source and libfuse's;
  # the audit finds every library it says is linked in.
  def test_libfuse_linked_into_the_appimage_runtime_whose_source_is_published_passes
    write("tools/appimage-runtime", Binaries.elf(payload: APPIMAGE_RUNTIME))

    report = audit
    assert_empty report.violations.map(&:to_s)
    present = report.present.map(&:id)
    %w[appimage-runtime libfuse squashfuse zstd zlib-appimage musl mimalloc gcc-runtime-alpine].each { |id| assert_includes present, id }
  end

  # The same code in the launcher, the program an app's developer ships
  # as their own, fails.
  def test_libfuse_linked_into_the_launcher_fails
    write("launcher", Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "ruby 4.1.0preview1 (revision 2d08b5f42f) #{RUST} GCC: (Ubuntu 13.3.0) " \
                                                                          "fuse: unsupported protocol version: "))

    assert_includes rules(audit), ["static-copyleft", "launcher"]
  end

  # GNU MP's code is allowed in GNU MP's own DLL on each Windows, whose
  # entries are gmp and gmp-arm64, two ids of one source pin.
  def test_gnu_mp_in_its_own_dll_passes_on_both_windows
    TestReaders.need(self, :pe)
    dll = "ruby/bin/ruby_builtin_dlls/libgmp-10.dll"
    tree = Dir.mktmpdir("license-audit-windows")
    FileUtils.mkdir_p(File.join(tree, "ruby/lib/ruby/4.1.0+6"))
    FileUtils.mkdir_p(File.join(tree, File.dirname(dll)))
    File.binwrite(File.join(tree, dll), Binaries.pe(needed: %w[KERNEL32.dll], payload: "GNU MP: Cannot allocate memory"))

    %w[x64-mingw-ucrt aarch64-mingw-ucrt].each do |platform|
      report = LicenseAudit.new(platform:, tree:, fledge_version: "0.0.0", readers: TestReaders.all).call

      assert_equal (platform == "x64-mingw-ucrt") ? "gmp" : "gmp-arm64", report.owners.fetch(dll).id
      refute_includes rules(report), ["static-copyleft", dll], platform
    end
  ensure
    FileUtils.rm_rf(tree) if tree
  end

  # An LGPL library linked into a component whose source Fledge does not
  # publish fails the policy.
  def test_an_lgpl_library_linked_into_a_component_whose_source_is_unpublished_fails
    map = YAML.safe_load_file(LicenseAudit::MAP)
    map.fetch("components").find { |entry| entry.fetch("id") == "appimage-runtime" }.delete("source")
    path = File.join(@tree, "..", "#{File.basename(@tree)}-map.yml")
    File.write(path, map.to_yaml)
    write("tools/appimage-runtime", Binaries.elf(payload: APPIMAGE_RUNTIME))

    report = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, map: path, fledge_version: "0.0.0").call
    assert_includes report.violations.map { |violation| [violation.rule, violation.path] }, ["policy", "tools/appimage-runtime"]
  ensure
    FileUtils.rm_f(path) if path
  end

  # NSIS's LZMA module is under the Common Public License, which asks that
  # a binary say where its source is: NSIS ships only with its source
  # pinned, which Fledge publishes.
  def test_a_component_whose_license_asks_for_its_source_needs_its_source_published
    write("tools/nsis/COPYING", "NSIS is under the zlib/libpng license\n")
    map = YAML.safe_load_file(LicenseAudit::MAP)
    nsis = map.fetch("components").find { |entry| entry.fetch("id") == "nsis" }
    nsis["platforms"] << "x86_64-linux"
    path = File.join(@tree, "..", "#{File.basename(@tree)}-map.yml")
    File.write(path, map.to_yaml)
    published = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, map: path, fledge_version: "0.0.0").call
    assert_empty published.violations.map(&:to_s)

    nsis.delete("source")
    File.write(path, map.to_yaml)
    unpublished = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, map: path, fledge_version: "0.0.0").call
    assert_includes unpublished.violations.map { |violation| [violation.rule, violation.path] }, ["policy", "tools/nsis/COPYING"]
  ensure
    FileUtils.rm_f(path) if path
  end

  def test_a_library_neither_the_system_nor_the_runtime_provides_fails
    write("launcher", Binaries.elf(needed: %w[libreadline.so.8 libc.so.6], payload: "2d08b5f42f #{RUST}"))

    assert_includes rules(audit), ["unresolved", "launcher"]
  end

  # Mozilla's CA bundle is a file, not code, so no evidence string says
  # which one a runtime carries: each entry pins the SHA-256 of the
  # extract its version names, and the audit refuses any other bytes.
  def test_a_ca_bundle_that_is_not_the_one_its_entry_names_fails
    write("libexec/cert.pem", "## Bundle of CA Root Certificates\n")

    assert_includes rules(audit), ["stale", "libexec/cert.pem"]
  end

  def test_the_bundle_a_windows_runtime_carries_is_pinned_too
    TestReaders.need(self, :pe)
    cert = "ruby/lib/ruby/4.1.0+6/etc/ssl/cert.pem"
    tree = Dir.mktmpdir("license-audit-windows")
    FileUtils.mkdir_p(File.join(tree, File.dirname(cert)))
    File.write(File.join(tree, cert), "## Bundle of CA Root Certificates\n")

    report = LicenseAudit.new(platform: "x64-mingw-ucrt", tree:, fledge_version: "0.0.0", readers: TestReaders.all).call

    assert_includes rules(report), ["stale", cert]
  ensure
    FileUtils.rm_rf(tree) if tree
  end

  def test_each_ca_bundle_entry_pins_the_sha256_of_its_file
    entries = YAML.safe_load_file(LicenseAudit::MAP).fetch("components").select { |entry| entry.fetch("id").start_with?("ca-certificates") }
    sources = YAML.safe_load_file(LicenseAudit::SOURCES)

    assert_equal %w[ca-certificates ca-certificates-jdx ca-certificates-msys2], entries.map { |entry| entry.fetch("id") }
    entries.each { |entry| assert_equal entry.fetch("files"), entry.fetch("sha256", {}).keys, entry.fetch("id") }
    mobile = sources.dig("mobile", "ca-certificates", "sha256")

    assert_equal mobile, sources.dig("musl-ruby", "ca-certificates", "sha256")
    assert_equal [mobile], entries.first.fetch("sha256").values
  end

  def test_a_component_whose_version_changed_fails
    write("#{ARCH}/openssl.so", Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL 3.6.3 "))

    assert_includes rules(audit), ["stale", "#{ARCH}/openssl.so"]
  end

  # A runtime made from Fledge's own build of Ruby holds that build's Rust
  # and OpenSSL, not jdx/ruby's. The platform's Ruby pin says which build
  # it is, so today's pins ask for jdx/ruby's, and Fledge's passes only
  # under a pin that names it.
  def test_the_build_of_ruby_a_pin_names_decides_what_the_runtime_must_hold
    write("launcher", Binaries.elf(needed: %w[libcrypt.so.2 libm.so.6 libc.so.6 ld-linux-x86-64.so.2],
      payload: "ruby 4.1.0preview1 (revision 2d08b5f42f) /rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/ GCC: (Ubuntu 13.3.0)"))
    openssl = YAML.safe_load_file(File.expand_path("../runtime/sources.yml", __dir__)).dig("musl-ruby", "openssl", "version")
    write("#{ARCH}/openssl.so", Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL #{openssl} "))
    stale = [["stale", "launcher"], ["stale", "#{ARCH}/openssl.so"]]

    assert_equal stale, rules(audit) & stale
    write("libexec/cert.pem", CaBundles.curl)
    Dir.mktmpdir("sources") do |dir|
      sources = YAML.safe_load_file(LicenseAudit::SOURCES)
      sources.dig("ruby", "platforms", "x86_64-linux")["build"] = "fledge"
      File.write(File.join(dir, "sources.yml"), YAML.dump(sources))
      report = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, sources: File.join(dir, "sources.yml"),
        fledge_version: "0.0.0").call

      assert_empty report.violations
    end
  end

  FLEDGE_RUST = "/rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/"

  # Fledge's own Ruby archive (tasks/ruby_archive.rb) is a Ruby prefix:
  # no launcher, no Fledge code in bin/ruby, no AppImage. The audit reads
  # it as that build, whatever the platform's Ruby pin names.
  def write_archive_tree
    openssl = YAML.safe_load_file(File.expand_path("../runtime/sources.yml", __dir__)).dig("musl-ruby", "openssl", "version")
    FileUtils.rm_f(File.join(@tree, "launcher"))
    write("bin/ruby", Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "ruby 4.1.0preview1 (revision 2d08b5f42f) #{FLEDGE_RUST} GCC: (Ubuntu 11.4.0)"))
    write("#{ARCH}/openssl.so", Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL #{openssl} "))
    write("libexec/cert.pem", CaBundles.curl)
    FileUtils.rm_f(File.join(@tree, "lib/ruby/4.1.0+5/rubygems/defaults/operating_system.rb"))
  end

  def archive_audit(**)
    run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0", archive: true, **)
    [run, run.call]
  end

  def test_the_audit_of_fledges_ruby_archive_holds_its_build_and_none_of_a_runtimes_own_files
    write_archive_tree
    _run, report = archive_audit

    assert_empty report.violations.map(&:to_s)
    assert_equal %w[ca-certificates gcc-runtime gem-csv-3.3.5 libxcrypt openssl-fledge ruby rust-std-fledge], report.present.map(&:id).sort
  end

  def test_the_audit_of_the_archive_refuses_a_runtimes_files
    write_archive_tree
    write("launcher", Binaries.elf(needed: %w[libc.so.6], payload: "#{FLEDGE_RUST} GCC: (Ubuntu 11.4.0)"))
    write("tools/appimage-runtime", Binaries.elf(payload: APPIMAGE_RUNTIME))
    _run, report = archive_audit

    assert_includes rules(report), ["unaccounted", "launcher"]
    assert_includes rules(report), ["unaccounted", "tools/appimage-runtime"]
  end

  # The notices of the archive speak of the archive, name no app and no
  # Fledge file, and point at the source inside the archive alone: the
  # pre-release that holds it carries no source bundle of a release.
  def test_the_notices_of_the_archive_speak_of_the_archive_and_point_at_its_own_sources
    write_archive_tree
    Dir.mktmpdir do |directory|
      linux_bundle(directory, archive: true).copy_into(@tree)
    end
    run, report = archive_audit
    notices = LicenseAudit::Notices.new(report, version: "0.0.0", map: run.map, archive: true)
    text = notices.text

    assert_empty report.violations.map(&:to_s)
    assert_empty notices.missing
    assert_equal "Fledge's own build of Ruby in this archive", text.lines.first.chomp
    assert_includes text, "LIBRARIES UNDER THE GNU LESSER GENERAL PUBLIC LICENSE"
    assert_includes text, "in this archive, in\n\n  notices/sources/libxcrypt/\n"
    assert_includes text, "=== libxcrypt/COPYING.LIB"
    refute_includes text, "FLEDGE'S OWN FILES"
    refute_includes text, "This app"
    refute_includes text, "lgpl-sources.tar.gz"
    assert_equal %w[libxcrypt], Dir.children(File.join(@tree, "notices/sources"))
  end

  # An entry may describe several builds of Ruby but not every one, as
  # an OpenSSL that rv-ruby's and Fledge's builds share and jdx/ruby's
  # does not.
  def test_an_entry_may_name_the_builds_of_ruby_it_describes
    components = [
      { "id" => "any", "platforms" => ["x86_64-linux"] },
      { "id" => "two", "platforms" => ["x86_64-linux"], "ruby_build" => %w[upstream fledge] },
      { "id" => "jdx", "platforms" => ["x86_64-linux"], "ruby_build" => "jdx" },
    ]
    map = { "components" => components }
    ids = %w[upstream fledge jdx].to_h do |build|
      pin = (build == "upstream") ? {} : { "build" => build }
      sources = { "ruby" => { "platforms" => { "x86_64-linux" => pin } } }
      [build, LicenseAudit.entries(map, sources, "x86_64-linux").map { |entry| entry.fetch("id") }]
    end

    assert_equal({ "upstream" => %w[any two], "fledge" => %w[any two], "jdx" => %w[any jdx] }, ids)
  end

  # A pin's move rewrites the entries runtime/upstreams.yml names by id,
  # so an id names one entry: two builds of one component are two ids,
  # and a move of one cannot rewrite the other.
  def test_two_entries_of_one_id_are_refused
    components = [
      { "id" => "openssl", "platforms" => ["x86_64-linux"] },
      { "id" => "openssl", "platforms" => ["x86_64-linux-musl"] },
    ]

    error = assert_raises(ArgumentError) { LicenseAudit.entries({ "components" => components }, {}, "x86_64-linux") }
    assert_includes error.message, "openssl"
  end

  def test_each_entry_of_the_map_has_its_own_id
    ids = YAML.safe_load_file(LicenseAudit::MAP).fetch("components").map { |entry| entry.fetch("id") }

    assert_equal [], ids.tally.select { |_id, count| count > 1 }.keys
  end

  # rv-ruby's bin/ holds the gems' executables beside ruby; each belongs
  # to its gem, so its license is the gem's.
  def test_a_gems_executable_belongs_to_the_gem
    write_gem("rake", "13.3.1", ["MIT"], executables: ["rake"])
    write("bin/rake", "#!/usr/bin/env ruby\nload Gem.bin_path('rake', 'rake')\n")

    assert_equal "gem-rake-13.3.1", audit.owners.fetch("bin/rake").id
  end

  # A gem's .gem in the cache ships too, and can hold files Ruby did not
  # install into the gem's folder.
  def test_copyleft_text_inside_a_cached_gem_fails_unless_reviewed
    write_cached_gem("csv", "3.3.5", "lib/csv.rb" => "class CSV; end\n", "lib/borrowed.rb" => "# GNU General Public License\n")

    assert_includes rules(audit), ["copyleft-text", "lib/ruby/gems/4.1.0+5/cache/csv-3.3.5.gem!lib/borrowed.rb"]
    refute_includes rules(audit).map(&:last), "lib/ruby/gems/4.1.0+5/cache/csv-3.3.5.gem!lib/csv.rb"
  end

  # Such as the AppleDouble ._csv-3.3.5.gem macOS's tar adds beside a
  # file with extended attributes: the audit cannot see inside it, so it
  # must not pass it.
  def test_a_cached_gem_the_audit_cannot_read_fails
    write("lib/ruby/gems/4.1.0+5/cache/csv-3.3.5.gem", "\x00\x05\x16\x07 not a tar".b)
    write("lib/ruby/gems/4.1.0+5/cache/._csv-3.3.5.gem", ("\x01" * 512).b)

    assert_includes rules(audit), ["unreadable", "lib/ruby/gems/4.1.0+5/cache/csv-3.3.5.gem"]
    assert_includes rules(audit), ["unreadable", "lib/ruby/gems/4.1.0+5/cache/._csv-3.3.5.gem"]
  end

  def test_compiled_or_libxcrypt_code_inside_a_cached_gem_fails
    write_cached_gem("csv", "3.3.5", "lib/csv.so" => Binaries.elf(needed: %w[libc.so.6]), "lib/crypt.c" => "yescrypt-ROMhash")

    assert_includes rules(audit), ["unlisted-binary", "lib/ruby/gems/4.1.0+5/cache/csv-3.3.5.gem!lib/csv.so"]
    assert_includes rules(audit), ["static-copyleft", "lib/ruby/gems/4.1.0+5/cache/csv-3.3.5.gem!lib/crypt.c"]
  end

  def test_a_gem_under_the_gpl_fails
    write_gem("copyleft", "1.0.0", ["GPL-3.0-or-later"])

    assert_includes rules(audit), ["policy", "lib/ruby/gems/4.1.0+5/gems/copyleft-1.0.0/LICENSE.txt"]
  end

  def test_a_gem_that_declares_no_license_fails
    write_gem("mystery", "1.0.0", [])

    assert(audit.violations.any? { |violation| violation.message.include?("gem-mystery-1.0.0 is NOASSERTION") })
  end

  def test_text_that_names_a_copyleft_license_must_have_been_reviewed
    write("lib/ruby/4.1.0+5/borrowed.rb", "# Licensed under the GNU General Public License, version 3.\n")

    assert_includes rules(audit), ["copyleft-text", "lib/ruby/4.1.0+5/borrowed.rb"]
  end

  # The audit judges every component of a runtime by
  # Fledge::LicensePolicy (test/license_policy_test.rb).
  def test_the_audit_judges_licenses_by_fledges_policy
    assert_equal :notice_only, LicenseAudit.category("Ruby OR BSD-2-Clause")
    assert_equal :notice_only, LicenseAudit.category("MIT")
    assert_equal :forbidden, LicenseAudit.category("AGPL-3.0-or-later")
  end

  # The macOS floor (doc/contributors/design/releases.md, "Platform
  # floors"): every Mach-O in a macOS runtime, the launcher and bin/ruby
  # among them, runs on Fledge's oldest macOS, and the audit refuses a
  # runtime with one that says otherwise.
  def macos_floors(files)
    Dir.mktmpdir("macos-floor") do |tree|
      files.each do |path, bytes|
        FileUtils.mkdir_p(File.dirname(File.join(tree, path)))
        File.binwrite(File.join(tree, path), bytes)
      end
      LicenseAudit.new(platform: "arm64-darwin", tree:, fledge_version: "0.0.0", readers: TestReaders.all).call
        .violations.select { |violation| violation.rule == "macos-floor" }.map(&:to_s)
    end
  end

  def test_refuses_a_mach_o_that_needs_a_newer_macos_than_the_floor
    TestReaders.need(self, :macho)

    assert_empty macos_floors({ "launcher" => Binaries.macho, "bin/ruby" => Binaries.macho })
    assert_empty macos_floors({ "launcher" => Binaries.macho(minos: "15.0") }), "a file built for a macOS below the floor"
    %w[launcher bin/ruby lib/ruby/4.1.0+5/arm64-darwin23/a.bundle].each do |path|
      assert_equal ["macos-floor: #{path}: needs macOS 27.1, and Fledge's macOS apps run on macOS 26.0 and later"],
        macos_floors({ path => Binaries.macho(minos: "27.1") })
    end
  end

  def test_refuses_a_mach_o_that_names_no_macos_at_all
    TestReaders.need(self, :macho)

    assert_equal ["macos-floor: launcher: names no macOS it runs on, and Fledge's macOS apps run on macOS 26.0 and later"],
      macos_floors({ "launcher" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], platform: "ios") })
  end

  def test_reads_the_libraries_elf_pe_and_mach_o_files_need
    TestReaders.need(self, :elf, :macho, :pe)
    audit = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0", readers: TestReaders.all)
    found = audit.compiled({
      "a.so" => Binaries.elf(needed: %w[libc.so.6 libcrypt.so.2]),
      "b.dll" => Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll],
        payload: '<dependentAssembly><assemblyIdentity type="win32" name="ruby_builtin_dlls" /></dependentAssembly>'),
      "c.bundle" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]),
      "d.a" => "!<arch>\nfoo.o/",
      "e.rb" => "puts 'MZ'\n",
    })

    assert_equal [:elf, %w[libc.so.6 libcrypt.so.2]], [found.fetch("a.so").format, found.fetch("a.so").needed]
    assert_equal [:pe, %w[KERNEL32.dll libgmp-10.dll], ["ruby_builtin_dlls"]], [
      found.fetch("b.dll").format,
      found.fetch("b.dll").needed.sort,
      found.fetch("b.dll").assemblies,
]
    assert_equal [:macho, %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]], [found.fetch("c.bundle").format, found.fetch("c.bundle").needed]
    assert_equal :archive, found.fetch("d.a").format
    refute found.key?("e.rb")
  end

  # Compiled code of a format no tool on the computer reads is still
  # compiled code: the audit says so, and fails, rather than pass it.
  def test_compiled_code_no_tool_here_reads_fails_the_audit
    readers = Fledge::Binary::Readers.new(commands: TestReaders.all.commands.slice(:elf), install: "Set FLEDGE_LLVM.")
    write("#{ARCH}/stray.bundle", Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib]))

    report = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0", readers:).call

    assert_includes rules(report), ["unreadable", "#{ARCH}/stray.bundle"]
  end

  def test_writes_an_spdx_sbom_that_accounts_for_every_file_and_link
    report = audit
    sbom = LicenseAudit::Spdx.new(report, version: "0.0.0", created: Time.utc(2026, 10, 26)).to_h
    files = sbom.fetch("files").to_h { |file| [file.fetch("fileName"), file] }
    launcher = files.fetch("./launcher").fetch("SPDXID")
    relationships = sbom.fetch("relationships").map { |relationship| relationship.values_at("spdxElementId", "relationshipType", "relatedSpdxElement") }

    assert_equal "SPDX-2.3", sbom.fetch("spdxVersion")
    assert_equal report.owners.keys.sort.map { |path| "./#{path}" }, files.keys
    assert(files.each_value.all? { |file| file.fetch("checksums").map { |checksum| checksum.fetch("algorithm") } == %w[SHA1 SHA256] })
    assert_includes relationships, [launcher, "DYNAMIC_LINK", files.fetch("./lib/libcrypt.so.2").fetch("SPDXID")]
    assert_includes relationships, [launcher, "STATIC_LINK", "SPDXRef-Package-rust-std-jdx"]
    assert_equal "LGPL-2.1-or-later", sbom.fetch("packages").find { |package| package["name"].start_with?("libxcrypt") }.fetch("licenseConcluded")
  end

  # The notices list the runtime Fledge copied in, its third-party
  # components and Fledge's own files, and nothing of the app's own code
  # or of the gems its developer chose, whose licenses are the
  # developer's (decisions, 2026-10-28). So the heading names the runtime,
  # and the opening says what is not listed.
  def test_notices_say_they_list_the_runtime_and_not_the_apps_own_code_or_gems
    audit_run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    text = LicenseAudit::Notices.new(audit_run.call, version: "0.0.0", map: audit_run.map).text

    assert_equal "The Fledge runtime in this app", text.lines.first.chomp
    refute_includes text, "Third-party software in this app"
    assert_includes text.split("COMPONENTS").first.tr("\n", " "),
      "The app's own code, and the gems its developer added, are not listed here"
    assert_match(/^This app was built with Fledge 0\.0\.0 /, text, "Delivery's scripts find the notices by this line")
  end

  # Ruby's LEGAL and the license texts hold non-ASCII bytes, and a build
  # in a container has no locale, so Ruby's default external encoding is
  # US-ASCII there: the texts are read as UTF-8 whatever it is, as they
  # are written.
  def test_notices_read_license_texts_as_utf8_whatever_the_default_encoding
    write_gem("ghost", "1.0.0", ["MIT"])
    File.delete(File.join(@tree, "lib/ruby/gems/4.1.0+5/gems/ghost-1.0.0/LICENSE.txt"))
    audit_run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    report = audit_run.call
    default = Encoding.default_external
    verbose = $VERBOSE
    $VERBOSE = nil
    Encoding.default_external = Encoding::US_ASCII
    begin
      notices = LicenseAudit::Notices.new(report, version: "0.0.0", map: audit_run.map)
      text = notices.text

      assert_equal ["gem-ghost-1.0.0"], notices.missing
      assert_equal Encoding::UTF_8, text.encoding
      assert text.valid_encoding?
    ensure
      Encoding.default_external = default
      $VERBOSE = verbose
    end
  end

  def test_notices_tell_the_recipient_how_to_replace_the_lgpl_library_and_where_its_source_is
    audit_run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    notices = LicenseAudit::Notices.new(audit_run.call, version: "0.0.0", map: audit_run.map)
    text = notices.text

    assert_includes text, "LIBRARIES UNDER THE GNU LESSER GENERAL PUBLIC LICENSE"
    assert_includes text, "  lib/libcrypt.so.2"
    assert_includes text, "https://github.com/setdef/Fledge/releases/download/v0.0.0/fledge-runtime-0.0.0-x86_64-linux-lgpl-sources.tar.gz"
    assert_includes text, "=== libxcrypt/COPYING.LIB"
    assert_includes text, "FLEDGE'S OWN FILES"
    assert_includes text, "These files are Fledge's own work, copyright 2026 setdef, under the\nMIT License"
    assert_includes text, "=== fledge/LICENSE\n\nMIT License\n\nCopyright (c) 2026 setdef\n\nPermission is hereby granted"
    refute_includes text, "AGPL"
    assert_includes text, "https://github.com/setdef/Fledge/tree/v0.0.0"
    assert_includes text, "License text: lib/ruby/gems/4.1.0+5/gems/csv-3.3.5/LICENSE.txt"
    assert_empty notices.missing
  end

  # Every platform's notices name Fledge's own files and where their
  # source is, and none names a notice of changed programs: Fledge's
  # files are MIT, which asks for none (decisions, 2026-11-07).
  def test_every_platforms_notices_name_fledges_files_and_no_notice_of_changes
    audit_run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    report = audit_run.call
    windows = LicenseAudit::Notices.new(report.with(platform: "x64-mingw-ucrt"), version: "0.0.0", map: audit_run.map).text
    linux = LicenseAudit::Notices.new(report, version: "0.0.0", map: audit_run.map).text

    [windows, linux].each do |text|
      assert_includes text, "rubygems/defaults/operating_system.rb\n\nTheir source is Fledge's"
      refute_includes text, "MODIFIED.txt"
    end
  end

  # A desktop runtime's first file of Fledge's is its launcher, which
  # fledge build renames for the app; a phone runtime has none, and the
  # app's host, which its developer builds, starts Ruby through Fledge's
  # embedding API.
  def test_only_a_desktops_notices_name_the_program_the_apps_user_runs
    audit_run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    linux = LicenseAudit::Notices.new(audit_run.call, version: "0.0.0", map: audit_run.map).text
    Dir.mktmpdir do |tree|
      FileUtils.mkdir_p([File.join(tree, "include"), File.join(tree, "lib/ruby/4.1.0+5/rubygems/defaults")])
      File.write(File.join(tree, "include/fledge_ruby.h"), "int fledge_ruby_run_app(void);\n")
      File.write(File.join(tree, "lib/ruby/4.1.0+5/rubygems/defaults/operating_system.rb"), "# Fledge's RubyGems defaults for a built app.\n")
      phone = LicenseAudit.new(platform: "android", tree:, fledge_version: "0.0.0")
      android = LicenseAudit::Notices.new(phone.call, version: "0.0.0", map: phone.map).text

      assert_includes linux, "The program the\napp's user runs is the first, renamed for the app:\n\n  launcher\n"
      assert_includes android,
        "as fledge/LICENSE). The app's host,\nwhich its developer builds, starts Ruby through them:\n\n  include/fledge_ruby.h\n"
      refute_includes android, "user runs"
    end
  end

  # Each Linux runtime's bundle holds libxcrypt's source, and, since
  # libfuse is linked into AppImage's runtime, the runtime's own source
  # and libfuse's (LGPL-2.1, section 6(a)), each with its license and how
  # it was built.
  # Puts +content+ in the download cache +downloads+ as the file +name+,
  # where DownloadCache keeps it, under its SHA-256.
  def in_download_cache(downloads, name, content)
    folder = File.join(downloads, Digest::SHA256.hexdigest(content))
    FileUtils.mkdir_p(folder)
    File.binwrite(File.join(folder, name), content)
  end

  # A sources.yml in +directory+ that pins libxcrypt, AppImage's runtime,
  # and libfuse to small files already in its download cache, and the
  # SourceBundle for x86_64-linux that reads it.
  def linux_bundle(directory, archive: false)
    downloads = File.join(directory, "downloads")
    pin = lambda do |name|
      in_download_cache(downloads, name, "pretend #{name}")
      { "url" => "https://example.com/#{name}", "sha256" => Digest::SHA256.hexdigest("pretend #{name}") }
    end
    sources = File.join(directory, "sources.yml")
    File.write(sources, {
      "libxcrypt" => { "version" => "4.5.2", **pin.call("libxcrypt-4.5.2.tar.xz") },
      "appimage-runtime" => {
        "version" => "20251108",
        "commit" => "dd6cebedcbddde9c82f89b011e8e1d40b6e43868",
        "platforms" => { "x86_64-linux" => { "url" => "https://example.com/runtime-x86_64", "sha256" => "0" * 64 } },
        "source" => pin.call("type2-runtime.tar.gz"),
      },
      "libfuse" => { "version" => "3.15.0", **pin.call("fuse-3.15.0.tar.xz") },
    }.to_yaml)
    LicenseAudit::SourceBundle.new(platform: "x86_64-linux", version: "0.0.0", sources:, downloads:, archive:)
  end

  # The app carries the source of each component whose license asks for
  # it, in notices/sources/, which it copies from the runtime, so the
  # source offer does not depend on any host. The audit
  # accounts for every file there as that component's source, the SBOM
  # lists them, and NOTICES.txt says where they are.
  def test_the_runtime_carries_the_sources_in_its_notices_and_the_audit_accounts_for_them
    Dir.mktmpdir do |directory|
      assert_equal File.join(@tree, "notices/sources"), linux_bundle(directory).copy_into(@tree)
    end
    write("tools/appimage-runtime", Binaries.elf(payload: APPIMAGE_RUNTIME))
    run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    report = run.call
    owners = report.owners.transform_values(&:id)

    assert_empty report.violations.map(&:to_s)
    assert_equal "libxcrypt-source", owners.fetch("notices/sources/libxcrypt/libxcrypt-4.5.2.tar.xz")
    assert_equal "libxcrypt-source", owners.fetch("notices/sources/libxcrypt/BUILD.txt")
    assert_equal "appimage-runtime-source", owners.fetch("notices/sources/appimage-runtime/type2-runtime.tar.gz")
    assert_equal "libfuse-source", owners.fetch("notices/sources/libfuse/LGPL2.txt")
    sbom = LicenseAudit::Spdx.new(report, version: "0.0.0", created: Time.utc(2026, 11, 4)).to_h
    assert_includes sbom.fetch("files").map { |file| file.fetch("fileName") }, "./notices/sources/libfuse/fuse-3.15.0.tar.xz"
    text = LicenseAudit::Notices.new(report, version: "0.0.0", map: run.map).text
    lgpl = text[/^LIBRARIES UNDER THE GNU LESSER.*?(?=^SOURCE THAT)/m].to_s
    assert_includes lgpl, "in this app, in\n\n  notices/sources/libxcrypt/\n"
    assert_includes lgpl, "\n  https://github.com/setdef/Fledge/releases/download/v0.0.0/fledge-runtime-0.0.0-x86_64-linux-lgpl-sources.tar.gz\n"
    refute_includes lgpl, "  notices/sources/libxcrypt/BUILD.txt"
    published = text[/^SOURCE THAT FLEDGE PUBLISHES.*?(?=^LICENSE TEXTS)/m].to_s
    assert_includes published, "  notices/sources/appimage-runtime/\n"
    assert_includes published, "  notices/sources/libfuse/\n"
    refute_includes published, "source code, as"
  end

  DESCRIPTION = "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f)\n"

  # RUBY_DESCRIPTION holds Ruby's words, copied out of its program, and
  # no app holds it, so it is Ruby's file, not Fledge's: the notices an
  # app carries name only the files of Fledge's that the app holds, the
  # program its user runs first, and doc/licensing.md's sentence on
  # Fledge's own files, made from the same files, stays true.
  def test_the_rubys_description_is_rubys_and_not_among_fledges_own_files
    write("RUBY_DESCRIPTION", DESCRIPTION)
    audit_run = LicenseAudit.new(platform: "x86_64-linux", tree: @tree, fledge_version: "0.0.0")
    report = audit_run.call
    ours = LicenseAudit::Notices.new(report, version: "0.0.0", map: audit_run.map).text[/^FLEDGE'S OWN FILES.*?(?=^Their source)/m].to_s

    assert_empty report.violations.map(&:to_s)
    assert_equal "ruby", report.owners.fetch("RUBY_DESCRIPTION").id
    assert_equal %w[launcher lib/ruby/4.1.0+5/rubygems/defaults/operating_system.rb], ours.scan(/^  (\S+)$/).flatten
  end

  # Every platform's runtime holds the file, and on each it is Ruby's.
  def test_every_platforms_ruby_owns_its_description
    Dir.mktmpdir do |tree|
      File.write(File.join(tree, "RUBY_DESCRIPTION"), DESCRIPTION)
      [*Fledge::Platform.names, *Fledge::MobilePlatform.names].each do |platform|
        report = LicenseAudit.new(platform:, tree:, fledge_version: "0.0.0").call

        ruby = platform.end_with?("mingw-ucrt") ? "ruby-windows" : "ruby"

        assert_equal [ruby, false], report.owners.fetch("RUBY_DESCRIPTION").then { |owner| [owner.id, owner.first_party] }, platform
      end
    end
  end

  # The notices folder is audited too, but for the two files the audit
  # itself writes there: anything else in it belongs to a component.
  def test_a_file_in_the_notices_folder_that_no_component_owns_fails
    write("notices/NOTICES.txt", "The Fledge runtime in this app\n")
    write("notices/sbom.spdx.json", "{}\n")
    write("notices/sources/stray.txt", "hello\n")
    write("notices/extra.txt", "hello\n")
    found = rules(audit)

    assert_includes found, ["unaccounted", "notices/sources/stray.txt"]
    assert_includes found, ["unaccounted", "notices/extra.txt"]
    refute_includes found, ["unaccounted", "notices/NOTICES.txt"]
    refute_includes found, ["unaccounted", "notices/sbom.spdx.json"]
  end

  def test_the_source_bundle_holds_the_pinned_sources_their_licenses_and_how_they_were_built
    Dir.mktmpdir do |directory|
      bundle = linux_bundle(directory)
      path = bundle.write(directory)
      top = File.join(Fledge::Archive.unpack(path, into: File.join(directory, "unpacked")), "fledge-runtime-0.0.0-x86_64-linux-lgpl-sources")
      runtime = File.join(directory, "runtime")
      bundle.copy_into(runtime)
      assert_equal Dir.glob("**/*", base: top).sort - ["README.txt"], Dir.glob("**/*", base: File.join(runtime, "notices/sources")).sort

      assert_equal "pretend libxcrypt-4.5.2.tar.xz", File.read(File.join(top, "libxcrypt/libxcrypt-4.5.2.tar.xz"))
      assert_includes File.read(File.join(top, "libxcrypt/BUILD.txt")), "--enable-shared --disable-static --disable-obsolete-api"
      assert_path_exists File.join(top, "libxcrypt/COPYING.LIB")
      assert_equal "pretend type2-runtime.tar.gz", File.read(File.join(top, "appimage-runtime/type2-runtime.tar.gz"))
      assert_includes File.read(File.join(top, "appimage-runtime/BUILD.txt")), "section 6(a)"
      assert_path_exists File.join(top, "appimage-runtime/LICENSE")
      assert_equal "pretend fuse-3.15.0.tar.xz", File.read(File.join(top, "libfuse/fuse-3.15.0.tar.xz"))
      assert_path_exists File.join(top, "libfuse/LGPL2.txt")
      readme = File.read(File.join(top, "README.txt"))
      %w[libxcrypt appimage-runtime libfuse].each { |id| assert_includes readme, "  #{id}/" }
    end
  end

  # Windows on ARM64's GNU MP is MSYS2's CLANGARM64 build of the same
  # source package, and its bundle says so
  # (doc/contributors/design/runtimes.md, "Windows on ARM64").
  def test_the_windows_on_arm_source_bundle_names_msys2s_clangarm64_build
    Dir.mktmpdir do |directory|
      downloads = File.join(directory, "downloads")
      in_download_cache(downloads, "gmp.src.tar.zst", "pretend gmp")
      in_download_cache(downloads, "nsis-src.tar.bz2", "pretend nsis")
      sources = File.join(directory, "sources.yml")
      File.write(sources, {
        "nsis" => {
          "version" => "3.13",
          "binary" => { "url" => "https://example.com/nsis.zip", "sha256" => "5" * 64 },
          "source" => { "url" => "https://example.com/nsis-src.tar.bz2", "sha256" => Digest::SHA256.hexdigest("pretend nsis") },
        },
        "gmp" => {
          "version" => "6.3.0",
          "url" => "https://example.com/gmp.src.tar.zst",
          "sha256" => Digest::SHA256.hexdigest("pretend gmp"),
          "package" => { "url" => "https://example.com/ucrt64/gmp.pkg.tar.zst", "sha256" => "1" * 64 },
          "dll_sha256" => "2" * 64,
          "arm64" => { "package" => { "url" => "https://example.com/clangarm64/gmp.pkg.tar.zst", "sha256" => "3" * 64 }, "dll_sha256" => "4" * 64 },
        },
      }.to_yaml)

      path = LicenseAudit::SourceBundle.new(platform: "aarch64-mingw-ucrt", version: "0.0.0", sources:, downloads:).write(directory)
      top = File.join(Fledge::Archive.unpack(path, into: File.join(directory, "unpacked")), "fledge-runtime-0.0.0-aarch64-mingw-ucrt-lgpl-sources")
      build = File.read(File.join(top, "gmp/BUILD.txt"))

      assert_includes build, "clangarm64/bin/libgmp-10.dll"
      assert_includes build, "#{'4' * 64})"
      assert_includes build, "CLANGARM64 environment"
      assert_includes build, "aarch64-w64-mingw32"
      refute_includes build, "ucrt64"
    end
  end

  def test_the_command_fails_on_a_violation_unless_it_was_expected
    write("stray.txt", "hello\n")
    out = StringIO.new
    expect = File.join(@tree, "..", "#{File.basename(@tree)}-expect.yml")
    File.write(expect, ["unaccounted: stray.txt"].to_yaml)

    assert_equal 1, LicenseAudit::CLI.new(["--platform", "x86_64-linux", "--tree", @tree, "--version", "0.0.0"], out:).call
    assert_includes out.string, "VIOLATION: unaccounted: stray.txt"
    assert_equal 0, LicenseAudit::CLI.new(["--platform", "x86_64-linux", "--tree", @tree, "--version", "0.0.0", "--expect", expect], out: StringIO.new).call
  ensure
    FileUtils.rm_f(expect)
  end

  # The bytes each mobile runtime's one library holds of what is linked
  # into it, as runtime/licenses.yml's evidence says: Ruby's revision,
  # OpenSSL's version string, libyaml's, BLAKE3's, and libffi's, which
  # move with their pins.
  MOBILE_LIBRARY = YAML.safe_load_file(File.expand_path("../runtime/licenses.yml", __dir__)).fetch("components")
    .select { |component| Array(component["platforms"]).include?("ios") }
    .flat_map { |component| Array(component["embedded"]).map { |embedded| embedded["evidence"] } }.compact.join(" ")

  # What runtime/licenses.yml says marks the library +id+ in a phone's
  # runtime, which moves with its pin.
  def mobile_evidence(id)
    YAML.safe_load_file(File.expand_path("../runtime/licenses.yml", __dir__)).fetch("components")
      .find { |component| component["id"] == id }.fetch("embedded").first.fetch("evidence")
  end

  # A path of Rust's standard library, as YJIT's panic messages carry it
  # into Android's libfledgeruby.so.
  ANDROID_RUST = "/rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/library/core/src/panicking.rs\0"

  # An iOS runtime: an XCFramework whose two slices each carry Ruby's
  # framework and the Ruby it runs, its extensions files there, as
  # CPython's iOS XCFramework does (doc/contributors/design/phone-runtimes.md,
  # "Ruby's extensions on iOS"), audited as one runtime with a Ruby tree
  # per slice, each gem one component, and OpenSSL's privacy manifest
  # OpenSSL's.
  def test_an_ios_runtime_accounts_for_the_ruby_of_each_slice
    Dir.mktmpdir do |tree|
      put = lambda do |path, bytes|
        FileUtils.mkdir_p(File.dirname(File.join(tree, path)))
        File.binwrite(File.join(tree, path), bytes)
      end
      put.call("FledgeRuby.xcframework/Info.plist", "<plist/>\n")
      %w[ios-arm64 ios-arm64-simulator].each do |slice|
        root = "FledgeRuby.xcframework/#{slice}"
        framework = "#{root}/FledgeRuby.framework"
        put.call("#{framework}/FledgeRuby", "Ruby 2d08b5f42f\n")
        put.call("#{framework}/Info.plist", "<plist/>\n")
        put.call("#{framework}/Headers/ruby.h", "/* ruby */\n")
        put.call("#{framework}/Headers/fledge_ruby.h", "/* fledge */\n")
        put.call("#{framework}/Headers/ruby/internal/ctype.h", "/* not GPL'ed, but ISO C's own */\n")
        put.call("#{framework}/Modules/module.modulemap", "framework module FledgeRuby {}\n")
        put.call("#{root}/fledge.links", "fledgerubyext.openssl.bundle\tlib/ruby/4.1.0+5/arm64-darwin/openssl.bundle\n")
        put.call("#{root}/privacy/fledgerubyext.openssl.bundle.xcprivacy", "<plist/>\n")
        put.call("#{root}/lib/ruby/4.1.0+5/arm64-darwin/openssl.bundle", mobile_evidence("openssl-mobile"))
        put.call("#{root}/lib/ruby/4.1.0+5/arm64-darwin/psych.bundle", mobile_evidence("libyaml-mobile"))
        put.call("#{root}/lib/ruby/4.1.0+5/set.rb", "class Set; end\n")
        put.call("#{root}/lib/ruby/4.1.0+5/rubygems/defaults/operating_system.rb", "# Fledge's RubyGems defaults for a built app.\n")
        put.call("#{root}/libexec/cert.pem", CaBundles.curl)
        put.call("#{root}/lib/ruby/gems/4.1.0+5/specifications/csv-3.3.5.gemspec", File.read(File.join(@tree, "lib/ruby/gems/4.1.0+5/specifications/csv-3.3.5.gemspec")))
        put.call("#{root}/lib/ruby/gems/4.1.0+5/gems/csv-3.3.5/lib/csv.rb", "module Csv; end\n")
        put.call("#{root}/lib/ruby/gems/4.1.0+5/gems/csv-3.3.5/LICENSE.txt", "Ruby or BSD-2-Clause\n")
      end

      TestReaders.need(self, :macho)
      report = LicenseAudit.new(platform: "ios", tree:, fledge_version: "0.0.0").call

      assert_empty report.violations.map(&:to_s)
      assert_equal 1, report.present.count { |component| component.id == "gem-csv-3.3.5" }
      owners = report.owners.transform_values(&:id)
      assert_equal "gem-csv-3.3.5", owners.fetch("FledgeRuby.xcframework/ios-arm64-simulator/lib/ruby/gems/4.1.0+5/gems/csv-3.3.5/lib/csv.rb")
      assert_equal "fledge-embedding", owners.fetch("FledgeRuby.xcframework/ios-arm64/FledgeRuby.framework/FledgeRuby")
      assert_equal "fledge-embedding", owners.fetch("FledgeRuby.xcframework/ios-arm64/fledge.links")
      assert_equal "ruby", owners.fetch("FledgeRuby.xcframework/ios-arm64/FledgeRuby.framework/Headers/ruby.h")
      assert_equal "openssl-mobile", owners.fetch("FledgeRuby.xcframework/ios-arm64/privacy/fledgerubyext.openssl.bundle.xcprivacy")
      assert_includes report.embeds.fetch("FledgeRuby.xcframework/ios-arm64/lib/ruby/4.1.0+5/arm64-darwin/openssl.bundle"), "openssl-mobile"
      %w[ruby openssl-mobile libyaml-mobile ca-certificates].each { |id| assert_includes report.present.map(&:id), id }
    end
  end

  # An Android runtime's AAR is a zip; the app ships what it holds, so
  # the audit reads each entry as AAR!ENTRY, and finds a copyleft
  # library's code in one as it would in a file. One of Ruby's own
  # extensions there, which the runtime's fledge.links names, is read as
  # the file the app's Ruby has it as, and belongs to Ruby; Ruby's own
  # library, which it links from libdir, is read in the AAR, where the
  # embedding API is.
  def test_an_aar_is_audited_by_what_it_holds
    Dir.mktmpdir do |tree|
      aar = File.join(tree, "aar")
      library = Binaries.elf(needed: %w[liblog.so libz.so libdl.so libm.so libc.so], payload: "ruby 4.1.0preview1 (revision 2d08b5f42f) #{ANDROID_RUST}")
      extension = -> (payload) { Binaries.elf(needed: %w[libc.so], payload:) }
      openssl = "libfledgerubyext.4.1.0+5.x86_64-linux-android.openssl.so"
      psych = "libfledgerubyext.4.1.0+5.x86_64-linux-android.psych.so"
      {
        "AndroidManifest.xml" => "<manifest/>\n",
        "classes.jar" => "PK\x03\x04",
        "jni/x86_64/libfledgeruby.so" => library,
        "jni/x86_64/#{openssl}" => extension.call(mobile_evidence("openssl-mobile")),
        "jni/x86_64/#{psych}" => extension.call(mobile_evidence("libyaml-mobile")),
      }.each do |path, bytes|
        FileUtils.mkdir_p(File.dirname(File.join(aar, path)))
        File.binwrite(File.join(aar, path), bytes)
      end
      system("zip", "-q", "-r", File.join(tree, "FledgeRuby.aar"), ".", chdir: aar, exception: true)
      FileUtils.rm_rf(aar)
      FileUtils.mkdir_p(File.join(tree, "include"))
      File.write(File.join(tree, "include", "fledge_ruby.h"), "/* fledge */\n")
      File.write(File.join(tree, "fledge.links"), "x86_64\tlibfledgeruby.so\tlib/libfledgeruby.so\n" \
        "x86_64\t#{openssl}\tlib/ruby/4.1.0+5/x86_64-linux-android/openssl.so\n" \
        "x86_64\t#{psych}\tlib/ruby/4.1.0+5/x86_64-linux-android/psych.so\n")

      report = LicenseAudit.new(platform: "android", tree:, fledge_version: "0.0.0").call

      assert_empty report.violations.map(&:to_s)
      assert_equal "fledge-embedding", report.owners.fetch("FledgeRuby.aar!jni/x86_64/libfledgeruby.so").id
      assert_equal "ruby", report.owners.fetch("lib/ruby/4.1.0+5/x86_64-linux-android/openssl.so").id
      assert_equal :system, report.links.fetch("FledgeRuby.aar!jni/x86_64/libfledgeruby.so").fetch("liblog.so")
      %w[ruby openssl-mobile libyaml-mobile rust-std-android].each { |id| assert_includes report.present.map(&:id), id }
      sbom = LicenseAudit::Spdx.new(report, version: "0.0.0", created: Time.utc(2026, 10, 28)).to_h
      assert_includes sbom.fetch("files").map { |file| file.fetch("fileName") }, "./FledgeRuby.aar!jni/x86_64/libfledgeruby.so"

      FileUtils.mkdir_p(File.join(aar, "jni", "x86_64"))
      File.binwrite(File.join(aar, "jni", "x86_64", "libfledgeruby.so"), Binaries.elf(needed: %w[libc.so], payload: "#{MOBILE_LIBRARY} yescrypt-ROMhash"))
      system("zip", "-q", "-r", File.join(tree, "FledgeRuby.aar"), "jni", chdir: aar, exception: true)
      FileUtils.rm_rf(aar)
      tampered = LicenseAudit.new(platform: "android", tree:, fledge_version: "0.0.0").call
      assert_includes rules(tampered), ["static-copyleft", "FledgeRuby.aar!jni/x86_64/libfledgeruby.so"]
    end
  end
end
