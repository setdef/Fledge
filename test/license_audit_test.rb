# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from test/license_audit_test.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require_relative "test_helper"
require_relative "support/binaries"
require_relative "../tasks/license_audit"
require "stringio"

# The license audit against small runtime trees shaped like a Linux
# runtime, built from real (minimal) ELF files and gem specifications,
# and checked against the real runtime/licenses.yml. CI runs it against
# the four real runtimes and the whole trees they come from.
class LicenseAuditTest < Minitest::Test
  RUST = "/rustc/4eb161250e340c8f48f66e2b929ef4a5bed7c181/"
  ARCH = "lib/ruby/4.0.0/x86_64-linux"

  def setup
    @tree = Dir.mktmpdir("license-audit")
    write("launcher", Binaries.elf(needed: %w[libcrypt.so.2 libm.so.6 libc.so.6 ld-linux-x86-64.so.2], rpath: "$ORIGIN/lib",
      payload: "ruby 4.0.9 (revision 3e93b23afc) #{RUST} GCC: (Ubuntu 13.3.0)"))
    write("lib/libcrypt.so.2", Binaries.elf(needed: %w[libc.so.6], payload: "XCRYPT_4.4\0yescrypt-ROMhash"))
    write("#{ARCH}/openssl.so", Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL 3.6.2 "))
    write("lib/ruby/4.0.0/set.rb", "class Set; end\n")
    write("lib/ruby/4.0.0/rubygems/defaults/operating_system.rb", "# Fledge's RubyGems defaults for a built app.\n")
    write("libexec/cert.pem", "-----BEGIN CERTIFICATE-----\n")
    write_gem("csv", "3.3.5", ["Ruby", "BSD-2-Clause"])
  end

  def teardown
    FileUtils.rm_rf(@tree)
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
    write("lib/ruby/gems/4.0.0/specifications/#{name}-#{version}.gemspec", spec.to_ruby)
    write("lib/ruby/gems/4.0.0/gems/#{name}-#{version}/lib/#{name}.rb", "module #{name.capitalize}; end\n")
    write("lib/ruby/gems/4.0.0/gems/#{name}-#{version}/LICENSE.txt", "#{licenses.join(' or ')}\n")
  end

  # Writes RubyGems' cache/NAME-VERSION.gem holding +files+, as the tar
  # of metadata.gz and data.tar.gz that RubyGems writes.
  def write_cached_gem(name, version, files)
    data = StringIO.new(+"".b)
    Gem::Package::TarWriter.new(data) { |tar| files.each { |path, bytes| tar.add_file(path, 0o644) { |io| io.write(bytes) } } }
    gem = StringIO.new(+"".b)
    Gem::Package::TarWriter.new(gem) { |tar| tar.add_file("data.tar.gz", 0o444) { |io| io.write(Zlib.gzip(data.string)) } }
    write("lib/ruby/gems/4.0.0/cache/#{name}-#{version}.gem", gem.string)
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
    assert_equal %w[fledge gem-csv-3.3.5 libxcrypt openssl ruby rust-std ca-certificates gcc-runtime].sort, report.present.map(&:id).sort
    assert_equal "lib/libcrypt.so.2", report.links.fetch("launcher").fetch("libcrypt.so.2")
    assert_equal :system, report.links.fetch("launcher").fetch("libc.so.6")
  end

  def test_each_file_belongs_to_the_most_specific_component
    owners = audit.owners.transform_values(&:id)

    assert_equal "fledge", owners.fetch("lib/ruby/4.0.0/rubygems/defaults/operating_system.rb")
    assert_equal "ruby", owners.fetch("lib/ruby/4.0.0/set.rb")
    assert_equal "gem-csv-3.3.5", owners.fetch("lib/ruby/gems/4.0.0/gems/csv-3.3.5/lib/csv.rb")
    assert_equal "libxcrypt", owners.fetch("lib/libcrypt.so.2")
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
  # own, because Fledge publishes the runtime's source and libfuse's
  # (ADR 010); the audit finds every library it says is linked in.
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
    write("launcher", Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "ruby 4.0.9 (revision 3e93b23afc) #{RUST} GCC: (Ubuntu 13.3.0) " \
                                                                          "fuse: unsupported protocol version: "))

    assert_includes rules(audit), ["static-copyleft", "launcher"]
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
    write("launcher", Binaries.elf(needed: %w[libreadline.so.8 libc.so.6], payload: "3e93b23afc #{RUST}"))

    assert_includes rules(audit), ["unresolved", "launcher"]
  end

  def test_a_component_whose_version_changed_fails
    write("#{ARCH}/openssl.so", Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL 3.6.3 "))

    assert_includes rules(audit), ["stale", "#{ARCH}/openssl.so"]
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

    assert_includes rules(audit), ["copyleft-text", "lib/ruby/gems/4.0.0/cache/csv-3.3.5.gem!lib/borrowed.rb"]
    refute_includes rules(audit).map(&:last), "lib/ruby/gems/4.0.0/cache/csv-3.3.5.gem!lib/csv.rb"
  end

  # Such as the AppleDouble ._csv-3.3.5.gem macOS's tar adds beside a
  # file with extended attributes: the audit cannot see inside it, so it
  # must not pass it.
  def test_a_cached_gem_the_audit_cannot_read_fails
    write("lib/ruby/gems/4.0.0/cache/csv-3.3.5.gem", "\x00\x05\x16\x07 not a tar".b)
    write("lib/ruby/gems/4.0.0/cache/._csv-3.3.5.gem", ("\x01" * 512).b)

    assert_includes rules(audit), ["unreadable", "lib/ruby/gems/4.0.0/cache/csv-3.3.5.gem"]
    assert_includes rules(audit), ["unreadable", "lib/ruby/gems/4.0.0/cache/._csv-3.3.5.gem"]
  end

  def test_compiled_or_libxcrypt_code_inside_a_cached_gem_fails
    write_cached_gem("csv", "3.3.5", "lib/csv.so" => Binaries.elf(needed: %w[libc.so.6]), "lib/crypt.c" => "yescrypt-ROMhash")

    assert_includes rules(audit), ["unlisted-binary", "lib/ruby/gems/4.0.0/cache/csv-3.3.5.gem!lib/csv.so"]
    assert_includes rules(audit), ["static-copyleft", "lib/ruby/gems/4.0.0/cache/csv-3.3.5.gem!lib/crypt.c"]
  end

  def test_a_gem_under_the_gpl_fails
    write_gem("copyleft", "1.0.0", ["GPL-3.0-or-later"])

    assert_includes rules(audit), ["policy", "lib/ruby/gems/4.0.0/gems/copyleft-1.0.0/LICENSE.txt"]
  end

  def test_a_gem_that_declares_no_license_fails
    write_gem("mystery", "1.0.0", [])

    assert(audit.violations.any? { |violation| violation.message.include?("gem-mystery-1.0.0 is NOASSERTION") })
  end

  def test_text_that_names_a_copyleft_license_must_have_been_reviewed
    write("lib/ruby/4.0.0/borrowed.rb", "# Licensed under the GNU General Public License, version 3.\n")

    assert_includes rules(audit), ["copyleft-text", "lib/ruby/4.0.0/borrowed.rb"]
  end

  # The audit judges every component of a runtime by
  # Fledge::LicensePolicy (test/license_policy_test.rb).
  def test_the_audit_judges_licenses_by_fledges_policy
    assert_equal :notice_only, LicenseAudit.category("Ruby OR BSD-2-Clause")
    assert_equal :forbidden, LicenseAudit.category("AGPL-3.0-or-later")
    assert_equal :first_party, LicenseAudit.category("AGPL-3.0-or-later", first_party: true)
  end

  def test_reads_the_libraries_elf_pe_and_mach_o_files_need
    elf = LicenseAudit::Binary.parse(Binaries.elf(needed: %w[libc.so.6 libcrypt.so.2], rpath: "$ORIGIN/lib"))
    pe = LicenseAudit::Binary.parse(Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll],
      payload: '<dependentAssembly><assemblyIdentity type="win32" name="ruby_builtin_dlls" /></dependentAssembly>'))
    macho = LicenseAudit::Binary.parse(Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]))

    assert_equal [:elf, %w[libc.so.6 libcrypt.so.2], ["$ORIGIN/lib"]], [elf.format, elf.needed, elf.rpaths]
    assert_equal [:pe, %w[libgmp-10.dll KERNEL32.dll], ["ruby_builtin_dlls"]], [pe.format, pe.needed, pe.assemblies]
    assert_equal [:macho, %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]], [macho.format, macho.needed]
    assert_equal :archive, LicenseAudit::Binary.parse("!<arch>\nfoo.o/").format
    assert_nil LicenseAudit::Binary.parse("puts 'MZ'\n")
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
    assert_includes relationships, [launcher, "STATIC_LINK", "SPDXRef-Package-rust-std"]
    assert_equal "LGPL-2.1-or-later", sbom.fetch("packages").find { |package| package["name"].start_with?("libxcrypt") }.fetch("licenseConcluded")
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
    assert_includes text, "https://github.com/setdef/Fledge/tree/v0.0.0"
    assert_includes text, "License text: lib/ruby/gems/4.0.0/gems/csv-3.3.5/LICENSE.txt"
    assert_empty notices.missing
  end

  # Each Linux runtime's bundle holds libxcrypt's source, and, since
  # libfuse is linked into AppImage's runtime, the runtime's own source
  # and libfuse's (LGPL-2.1, section 6(a)), each with its license and how
  # it was built.
  def test_the_source_bundle_holds_the_pinned_sources_their_licenses_and_how_they_were_built
    Dir.mktmpdir do |directory|
      downloads = File.join(directory, "downloads")
      FileUtils.mkdir_p(downloads)
      pin = lambda do |name|
        File.binwrite(File.join(downloads, name), "pretend #{name}")
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

      path = LicenseAudit::SourceBundle.new(platform: "x86_64-linux", version: "0.0.0", sources:, downloads:).write(directory)
      top = File.join(Fledge::Archive.unpack(path, into: File.join(directory, "unpacked")), "fledge-runtime-0.0.0-x86_64-linux-lgpl-sources")

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
end
