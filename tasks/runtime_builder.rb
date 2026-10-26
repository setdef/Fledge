# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "etc"
require "fileutils"
require "open3"
require "yaml"
require_relative "../lib/fledge/download"
require_relative "../lib/fledge/entry"
require_relative "../lib/fledge/platform"
require_relative "../lib/fledge/runtimes"
require_relative "../lib/fledge/tar_gz"
require_relative "../lib/fledge/version"

# Builds a runtime (ADR 001, section 2).
#
# On macOS and Linux, a runtime is the launcher in runtime/launcher/,
# compiled against rv-ruby's static libruby, beside Ruby's own program
# (bin/ruby, built from the same libruby), rv-ruby's standard library,
# default gems, and bundled gems, its CA bundle, and the license notices
# of everything it carries. Those launchers link Ruby itself, so each builds
# on its own platform's runner. On Windows, a runtime is the launcher,
# cross-compiled with llvm-mingw, beside RubyInstaller's Ruby in ruby\,
# with the notices: the Windows launcher loads Ruby's DLL when it runs
# and needs only Ruby's headers to build, so a Linux runner, or a Mac,
# builds it. Then fledge build, on any computer, copies apps into the
# results.
#
# Every input comes from runtime/sources.yml and is checked against its
# SHA-256, and RubyInstaller's archive against its PGP signature too. The
# steps that differ by operating system (unpacking Ruby, compiling,
# stripping, libxcrypt) live in a recipe per OS: Darwin and Linux, which
# share Unix, and Windows. The layout is the one the Unix and Windows
# launcher spikes settled (Plan 001).
#
# What a runtime leaves out follows one rule (ADR 003): an app's Ruby
# code must run as it does under a standard Ruby 4.0.9, so a runtime
# keeps everything such a Ruby installs that running Ruby code can
# reach (every default and bundled gem, its executables, the gem cache,
# the C extensions, RbConfig.ruby) and prunes only what no running Ruby
# code reads: documentation, man pages, headers, static and import
# libraries, and debug information. Size matters less than that rule.
#
# Run it as rake runtime (or rake "runtime[x64-mingw-ucrt]"), or as ruby
# tasks/runtime_builder.rb [PLATFORM] in a container that has a C
# toolchain and any Ruby.
class RuntimeBuilder
  ROOT = File.expand_path("..", __dir__)

  # Compiler warnings the launcher must build without. Ruby's headers are
  # included with -isystem, so these apply to Fledge's code only.
  WARNINGS = %w[
    -Wall
    -Wextra
    -Werror
    -Wpedantic
    -Wshadow
    -Wstrict-prototypes
    -Wmissing-prototypes
    -Wformat=2
    -Wconversion
    -Wsign-conversion
  ].freeze

  attr_reader :platform, :host, :sources

  def initialize(platform: Fledge::Platform.local, host: Fledge::Platform.local, work: File.join(ROOT, "tmp", "runtime"),
    downloads: File.join(ROOT, "tmp", "downloads"), sources: File.join(ROOT, "runtime", "sources.yml")
  )
    @platform = platform
    @host = host
    @work = work
    @downloads = downloads
    @sources = YAML.safe_load_file(sources)
  end

  # Builds the runtime and returns the path of its archive.
  def call
    recipe = recipe_class.new(builder: self, build_dir:)
    hosts = recipe.hosts
    raise "#{platform} runtimes build on #{hosts.join(', ')} only; this is #{host}" unless hosts.include?(host.name)

    FileUtils.rm_rf(build_dir)
    FileUtils.mkdir_p(stage)
    recipe.build(stage)
    write_notices(stage)
    archive
  end

  # The folder that becomes the runtime archive's top folder.
  def stage
    File.join(build_dir, "stage", top)
  end

  def top
    File.basename(Fledge::Runtimes.file_name(platform), Fledge::Runtimes::EXTENSION)
  end

  def build_dir
    File.join(@work, platform.name)
  end

  # Downloads +url+ into the download cache, checked against +sha256+,
  # unless a file with that SHA-256 is already there.
  def fetch(url, sha256)
    path = File.join(@downloads, File.basename(url))
    return path if File.file?(path) && Digest::SHA256.file(path).hexdigest == sha256

    puts "Downloading #{url}"
    Fledge::Download.save(url, to: path, sha256:)
  end

  # The first of +tools+ found on PATH, as a full path, or nil.
  def which(*tools)
    directories = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
    tools.each do |tool|
      directories.each do |directory|
        path = File.join(directory, tool)
        return path if File.file?(path) && File.executable?(path)
      end
    end
    nil
  end

  # Runs a command, echoing it, and raises when it fails.
  def run(*command, chdir: ROOT, out: $stdout)
    puts "+ #{command.join(' ')}"
    system(*command, chdir:, out:, exception: true)
  end

  # Runs a command and returns its standard output.
  def capture(*command)
    out, status = Open3.capture2(*command)
    raise "#{command.join(' ')} failed" unless status.success?

    out
  end

  # Removes, from a copy of a Ruby's lib/ruby at +ruby+, what no running
  # Ruby code reads, and what a standard Ruby 4.0.9 does not install.
  # Returns the names of the executables of the gems it removed, for
  # prune_bin. +bundled+ names Ruby's bundled gems, from
  # runtime/sources.yml. Each removal, and why no app can miss it:
  #
  # [*.dSYM] macOS debug symbols, read by debuggers and crash reporters,
  #          never by Ruby.
  # [*.a, *.h, pkgconfig] Static libraries, C headers, and pkg-config
  #          files, for compiling against Ruby; a runtime compiles
  #          nothing, and Ruby code never loads them.
  # [gems/4.0.0/doc] RDoc and ri documentation, read by the rdoc and ri
  #          tools a developer runs, never by an app's requires.
  # [portable_ruby_gems.rb, and gems no standard Ruby installs] rv-ruby's
  #          own additions (a load-path helper for its executables, and
  #          bootsnap and msgpack): a standard Ruby 4.0.9, and
  #          RubyInstaller's, has none of them, so an app that worked
  #          under ruby never needed them. Gems that are neither default
  #          gems nor in +bundled+ go, with their specification, cache,
  #          build information, and extensions.
  #
  # Everything else stays: the standard library, every default and
  # bundled gem, each gem's executables, the .gem cache (gem pristine and
  # Gem::Specification#cache_file read it), build information, plugins,
  # and C extensions.
  def self.prune(ruby, bundled)
    FileUtils.rm_rf(Dir.glob(File.join(ruby, "**", "*.dSYM")))
    FileUtils.rm_f(Dir.glob(File.join(ruby, "*", "*", "portable_ruby_gems.rb")))
    FileUtils.rm_f(Dir.glob(File.join(ruby, "**", "*.{a,h}")))
    FileUtils.rm_rf(Dir.glob(File.join(ruby, "**", "pkgconfig")))
    Dir.glob(File.join(ruby, "gems", "*")).flat_map { |gems| prune_gems(gems, bundled) }
  end

  # Removes the documentation, and every gem that is neither a default
  # gem nor one of +bundled+, from the gem folder +gems+. Returns the
  # removed gems' executables.
  def self.prune_gems(gems, bundled)
    FileUtils.rm_rf(File.join(gems, "doc"))
    Dir.glob(File.join(gems, "specifications", "*.gemspec")).flat_map do |path|
      spec = Gem::Specification.load(path) or raise "#{path} is not a gem specification"
      next [] if bundled.include?(spec.name)

      remove_gem(gems, spec.full_name)
      spec.executables
    end
  end

  def self.remove_gem(gems, full_name)
    FileUtils.rm_f(File.join(gems, "specifications", "#{full_name}.gemspec"))
    FileUtils.rm_rf(File.join(gems, "gems", full_name))
    FileUtils.rm_f(File.join(gems, "cache", "#{full_name}.gem"))
    FileUtils.rm_f(File.join(gems, "build_info", "#{full_name}.info"))
    FileUtils.rm_rf(Dir.glob(File.join(gems, "extensions", "*", "*", full_name)))
  end

  # Removes from +bin+ the executables of gems prune removed, which
  # would fail without their gem.
  def self.prune_bin(bin, executables)
    executables.each { |name| FileUtils.rm_f(File.join(bin, name)) }
  end

  # Removes, from a copy of RubyInstaller's tree at +tree+, what no
  # running Ruby code reads, as prune does for lib\ruby, and
  # RubyInstaller's own tools for setting up a developer's computer:
  #
  # [share\] Ruby's HTML documentation and ri data, for the rdoc and ri
  #          tools.
  # [include\, lib\*.a, lib\pkgconfig] Headers and import libraries,
  #          for compiling against Ruby.
  # [packages\, ridk_use\, bin\ridk.cmd, bin\ridk.ps1,
  #          bin\setrbvars.cmd, bin\startmenu.rb] The MSYS2 keyring and
  #          ridk, which install and select MSYS2 compilers for a
  #          developer, and the scripts that set up a developer's shell
  #          and the Start menu; they work only beside an installed
  #          RubyInstaller and MSYS2.
  #
  # Every program and DLL stays (ruby.exe and rubyw.exe for RbConfig.ruby
  # and Gem.ruby, and the DLLs some extension's manifest names), and so
  # do the gems' command-line wrappers (gem.cmd, bundle.bat, ...) and
  # RubyInstaller's own Ruby library in site_ruby.
  def self.prune_windows(tree, bundled)
    FileUtils.rm_rf(%w[share include packages ridk_use lib/pkgconfig].map { |path| File.join(tree, path) })
    FileUtils.rm_f(Dir.glob(File.join(tree, "lib", "*.a")))
    FileUtils.rm_f(%w[ridk.cmd ridk.ps1 setrbvars.cmd startmenu.rb].map { |name| File.join(tree, "bin", name) })
    prune_bin(File.join(tree, "bin"), prune(File.join(tree, "lib", "ruby"), bundled))
  end

  # Ruby's bundled gems, as runtime/sources.yml lists them.
  def bundled_gems
    sources.fetch("ruby").fetch("bundled_gems")
  end

  # The bytes of an ASCII-armored OpenPGP block (RFC 4880, section 6),
  # which gpgv reads only as binary. Raises when the armor's CRC-24 does
  # not match.
  def self.dearmor(armored)
    body = armored[/^-----BEGIN PGP [A-Z ]+-----\r?\n(.*?)^-----END PGP /m, 1] or raise "not an ASCII-armored OpenPGP block"
    lines = body.split(/\r?\n\r?\n/, 2).last.to_s.lines.map(&:strip).reject(&:empty?)
    checksum = lines.last.to_s.start_with?("=") ? lines.pop.to_s.delete_prefix("=") : nil
    bytes = lines.join.unpack1("m0")
    raise "the armor's CRC-24 does not match its data" if checksum && [crc24(bytes)].pack("N").byteslice(1, 3) != checksum.unpack1("m0")

    bytes
  end

  def self.crc24(bytes)
    bytes.each_byte.reduce(0xB704CE) do |crc, byte|
      crc ^= byte << 16
      8.times { crc = (crc << 1).then { |shifted| shifted.anybits?(0x1000000) ? shifted ^ 0x1864CFB : shifted } }
      crc
    end & 0xFFFFFF
  end

  # The Subsystem field of the Windows program at +path+ (2 for a GUI
  # program, 3 for a console one), from its PE optional header, which
  # starts 24 bytes into the PE header and holds Subsystem at offset 68
  # in both PE32 and PE32+.
  def self.pe_subsystem(path)
    bytes = File.binread(path, 4096).to_s
    raise "#{path} is not a Windows program" unless bytes.start_with?("MZ") && bytes.bytesize >= 64

    header = bytes.byteslice(0x3C, 4).to_s.unpack1("V").to_i
    raise "#{path} is not a Windows program" unless bytes.byteslice(header, 4) == "PE\0\0"

    bytes.byteslice(header + 24 + 68, 2).to_s.unpack1("v")
  end

  # Puts Fledge's rubygems/defaults/operating_system.rb into the Ruby
  # library at +ruby+ (a lib/ruby folder), replacing any there, such as
  # RubyInstaller's; see the file's own comment.
  def install_rubygems_defaults(ruby)
    version = sources.fetch("ruby").fetch("version").sub(/\.\d+\z/, ".0")
    defaults = File.join(ruby, version, "rubygems", "defaults")
    raise "#{ruby} has no RubyGems at #{version}" unless File.directory?(File.dirname(defaults))

    FileUtils.mkdir_p(defaults)
    FileUtils.cp(File.join(ROOT, "runtime", "rubygems", "operating_system.rb"), defaults)
  end

  # The notices that apply to this platform, from runtime/sources.yml.
  def notices
    sources.fetch("notices").select { |notice| notice.fetch("platforms").include?(platform.name) }
  end

  # Copies each notice into +stage+/notices and indexes them in
  # notices/README.txt.
  def write_notices(stage)
    notices.each do |notice|
      folder = File.join(stage, "notices", notice.fetch("folder"))
      FileUtils.mkdir_p(folder)
      notice_files(notice).each { |file| FileUtils.cp(file, folder) }
    end
    File.write(File.join(stage, "notices", "README.txt"), notices_index)
  end

  def notices_index
    entries = notices.map do |notice|
      <<~ENTRY
        #{notice.fetch('folder')}/
          #{notice.fetch('name')}
          License: #{notice.fetch('license')}
          Source: #{notice.fetch('source')}
      ENTRY
    end
    <<~INDEX
      This app was built with Fledge (https://github.com/setdef/Fledge). Its
      launcher, the Ruby it runs on, and the libraries Ruby uses are the work
      of the people below, under the licenses in each folder. The source of
      each is at the address given.

      #{entries.join("\n")}
    INDEX
  end

  private def notice_files(notice)
    return [File.join(ROOT, "LICENSES", "AGPL-3.0-or-later.txt")] if notice.fetch("folder") == "fledge"

    Dir.glob(File.join(ROOT, "runtime", "notices", notice.fetch("folder"), "*"))
  end

  private def recipe_class
    if platform.windows?
      Windows
    else
      platform.name.end_with?("-darwin") ? Darwin : Linux
    end
  end

  private def archive
    path = File.join(@work, Fledge::Runtimes.file_name(platform))
    mtime = Integer(ENV.fetch("SOURCE_DATE_EPOCH", Time.now.to_i.to_s))
    Fledge::TarGz.write(path, mtime:) do |tar|
      tar.add(Fledge::Entry.directory(top))
      Fledge::Entry.walk(stage).each { |entry| tar.add(entry.with(path: "#{top}/#{entry.path}")) }
    end
    puts "Built #{path} (#{(File.size(path) / 1_000_000.0).round(1)} MB)"
    path
  end

  # What every recipe shares: the builder, the folder it works in, and
  # where the launcher's sources are.
  class Recipe
    LAUNCHER = File.join(ROOT, "runtime", "launcher")

    def initialize(builder:, build_dir:)
      @builder = builder
      @build_dir = build_dir
    end

    # The platforms whose computers can build this recipe's runtime.
    def hosts
      [@builder.platform.name]
    end
  end

  # macOS and Linux: rv-ruby's Ruby, whose static libruby the launcher
  # links, so each builds only on its own platform. The runtime is the
  # launcher with bin/, lib/ruby, and libexec/cert.pem beside it.
  class Unix < Recipe
    def build(stage)
      @prefix = unpack_ruby
      copy_ruby(stage)
      compile(File.join(stage, "launcher"), launcher_sources, "$ORIGIN/lib")
      compile(File.join(stage, "bin", "ruby"), [File.join(LAUNCHER, "ruby_main.c")], "$ORIGIN/../lib")
      finish(stage)
    end

    private def launcher_sources
      [File.join(LAUNCHER, "unix.c"), File.join(LAUNCHER, "scrub.c"), File.join(LAUNCHER, os_file)]
    end

    private def includes
      headers = Dir.glob(File.join(@prefix, "include", "ruby-*")).first or raise "#{@prefix} has no Ruby headers"
      arch = Dir.glob(File.join(headers, "*")).find { |dir| File.directory?(dir) && File.basename(dir) != "ruby" }
      ["-isystem", arch.to_s, "-isystem", headers, "-I", LAUNCHER]
    end

    private def unpack_ruby
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(@builder.platform.name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      unpacked = File.join(@build_dir, "rv-ruby")
      FileUtils.mkdir_p(unpacked)
      @builder.run("tar", "-xzf", tarball, "-C", unpacked)
      prefixes = Dir.glob(File.join(unpacked, "*", @builder.sources.fetch("ruby").fetch("version")))
      raise "#{tarball} does not hold one Ruby prefix: #{prefixes}" unless prefixes.size == 1

      prefixes.first.to_s
    end

    # Copies rv-ruby's bin/ (whose ruby compile then replaces with one
    # built from the same libruby as the launcher; the rest are the gems'
    # executables), lib/ruby, and the CA bundle.
    private def copy_ruby(stage)
      FileUtils.mkdir_p(File.join(stage, "lib"))
      FileUtils.cp_r(File.join(@prefix, "bin"), File.join(stage, "bin"))
      FileUtils.rm_f(File.join(stage, "bin", "ruby"))
      FileUtils.cp_r(File.join(@prefix, "lib", "ruby"), File.join(stage, "lib", "ruby"))
      FileUtils.chmod_R("u+w", [File.join(stage, "lib"), File.join(stage, "bin")])
      removed = RuntimeBuilder.prune(File.join(stage, "lib", "ruby"), @builder.bundled_gems)
      RuntimeBuilder.prune_bin(File.join(stage, "bin"), removed)
      @builder.install_rubygems_defaults(File.join(stage, "lib", "ruby"))
      FileUtils.mkdir_p(File.join(stage, "libexec"))
      FileUtils.cp(File.join(@prefix, "libexec", "cert.pem"), File.join(stage, "libexec", "cert.pem"))
    end
  end

  # macOS: link libruby whole into the launcher, which exports its
  # symbols to extensions by default; ad hoc sign it, since Apple Silicon
  # runs only signed code.
  class Darwin < Unix
    # Compiles +sources+ with libruby into the program +output+, which
    # needs no RPATH: it links only libraries macOS ships.
    def compile(output, sources, _rpath)
      cc = ENV.fetch("CC", "clang")
      sources.each do |source|
        report = File.join(@build_dir, "#{File.basename(source, '.c')}.plist")
        @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", "-std=gnu11", *includes, source, "-o", report)
      end
      static = File.join(@prefix, "lib", "libruby.4.0-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, "-mmacosx-version-min=14.0", *includes, *sources,
        "-Wl,-force_load,#{static}", "-framework", "CoreFoundation", "-ldl", "-lobjc", "-lpthread", "-o", output)
      @builder.run("strip", "-x", output)
      @builder.run("codesign", "--sign", "-", "--force", output)
      check_libraries(output)
    end

    def finish(_stage); end

    private def os_file
      "darwin.c"
    end

    private def check_libraries(output)
      libraries = @builder.capture("otool", "-L", output).lines.drop(1).map { |line| line.strip.split.first.to_s }
      foreign = libraries.reject { |library| library.start_with?("/usr/lib/", "/System/Library/") }
      raise "the launcher links libraries macOS does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end

  # Linux: link libruby whole and export its symbols (-rdynamic), take
  # libgcc's unwinder statically, and link libxcrypt dynamically from
  # the runtime's lib/ (see runtime/launcher/unix.c).
  class Linux < Unix
    # The shared libraries the launcher may need: glibc's, and the
    # runtime's own libxcrypt.
    ALLOWED = /\A(?:libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux[-\w.]*\.so\.\d|libcrypt\.so\.\d+)\z/

    # Compiles +sources+ with libruby into the program +output+, which
    # finds the runtime's libcrypt through the RPATH +rpath+: $ORIGIN/lib
    # for the launcher at the runtime's top, $ORIGIN/../lib for bin/ruby.
    def compile(output, sources, rpath)
      xcrypt = (@xcrypt ||= build_libxcrypt)
      cc = ENV.fetch("CC", "cc")
      sources.each do |source|
        @builder.run(cc, "-fanalyzer", "-Werror", "-std=gnu11", *includes, "-c", source, "-o", File::NULL)
      end
      static = File.join(@prefix, "lib", "libruby-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, *includes, *sources, "-rdynamic", "-static-libgcc",
        "-Wl,--whole-archive", static, "-Wl,--no-whole-archive", "-L#{File.join(xcrypt, 'lib')}", "-lcrypt",
        "-Wl,--disable-new-dtags,-rpath,#{rpath}", "-lrt", "-ldl", "-lm", "-lpthread", "-o", output)
      @builder.run("strip", "--strip-unneeded", output)
      copy_libcrypt(xcrypt, File.join(@builder.stage, "lib"))
      check_dynamic_section(output, rpath)
    end

    # Strips debug sections from extensions, and removes the RUNPATHs
    # rv-ruby's build machine left in some (zlib.so names a Linuxbrew
    # folder), so no extension looks for libraries outside the runtime.
    def finish(stage)
      Dir.glob(File.join(stage, "lib", "ruby", "**", "*.so")).each do |extension|
        @builder.run("strip", "--strip-debug", extension)
        @builder.run("patchelf", "--remove-rpath", extension) unless @builder.capture("patchelf", "--print-rpath", extension).strip.empty?
      end
    end

    private def build_libxcrypt
      pin = @builder.sources.fetch("libxcrypt")
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      source = File.join(@build_dir, "libxcrypt")
      prefix = File.join(@build_dir, "libxcrypt-prefix")
      FileUtils.mkdir_p(source)
      @builder.run("tar", "-xJf", tarball, "-C", source, "--strip-components=1")
      # The options of rv-ruby's rv-portable-libxcrypt formula, shared
      # instead of static.
      @builder.run("./configure", "--prefix=#{prefix}", "--enable-shared", "--disable-static", "--disable-obsolete-api",
        "--disable-xcrypt-compat-files", "--disable-failure-tokens", "--disable-valgrind", chdir: source)
      @builder.run("make", "-j#{Etc.nprocessors}", chdir: source)
      @builder.run("make", "install", chdir: source)
      prefix
    end

    private def copy_libcrypt(xcrypt, lib)
      linked = Dir.glob(File.join(xcrypt, "lib", "libcrypt.so.*")).find { |path| File.basename(path).match?(/\Alibcrypt\.so\.\d+\z/) }
      raise "libxcrypt built no libcrypt.so.N" unless linked

      FileUtils.mkdir_p(lib)
      target = File.join(lib, File.basename(linked))
      FileUtils.cp(File.realpath(linked), target)
      FileUtils.chmod(0o755, target)
      @builder.run("strip", "--strip-unneeded", target)
    end

    private def os_file
      "linux.c"
    end

    private def check_dynamic_section(output, rpath)
      dynamic = @builder.capture("readelf", "-d", output)
      raise "#{output} has a RUNPATH, which LD_LIBRARY_PATH overrides" if dynamic.include?("(RUNPATH)")
      raise "#{output} has no RPATH of #{rpath}" unless dynamic.include?("Library rpath: [#{rpath}]")

      needed = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(ALLOWED)
      raise "#{output} needs libraries a runtime does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end

  # Windows: RubyInstaller's Ruby, checked against its signature, whose
  # tree goes into ruby\ with its shape unchanged and Fledge's RubyGems
  # defaults in place of RubyInstaller's, and the launcher cross-compiled
  # beside it with llvm-mingw. The launcher loads Ruby's DLL when it runs
  # (runtime/launcher/windows.c), so it needs Ruby's headers to build,
  # and nothing to link.
  class Windows < Recipe
    TARGET = "x86_64-w64-mingw32"

    # The PE Subsystem of a console program, which Windows gives a
    # console, and of a GUI one, which it does not.
    CONSOLE = 3
    GUI = 2

    # The DLLs a launcher may import: Windows' kernel and its universal C
    # runtime, which every supported Windows ships, and for a windowed
    # one, USER32 for its message box.
    IMPORTS = /\A(?:KERNEL32\.dll|api-ms-win-crt-[a-z0-9-]+\.dll)\z/i
    WINDOWED_IMPORTS = /\AUSER32\.dll\z/i

    def hosts
      @builder.sources.fetch("llvm-mingw").fetch("hosts").keys
    end

    def build(stage)
      tree = unpack_rubyinstaller
      @toolchain = unpack_toolchain
      compile(tree, File.join(stage, "launcher.exe"))
      ruby = File.join(stage, "ruby")
      FileUtils.cp_r(tree, ruby)
      FileUtils.chmod_R("u+w", ruby)
      RuntimeBuilder.prune_windows(ruby, @builder.bundled_gems)
      @builder.install_rubygems_defaults(File.join(ruby, "lib", "ruby"))
    end

    # Compiles the console launcher to +output+, and a windowed one beside
    # the build, which no runtime ships yet, to check that it still
    # builds as a GUI program. Both build with warnings as errors, under
    # clang's static analyzer, and may import only what IMPORTS allows.
    private def compile(tree, output)
      sources = [File.join(LAUNCHER, "windows.c"), File.join(LAUNCHER, "scrub.c")]
      flags = ["-std=gnu11", *WARNINGS, "-municode", "-DFLEDGE_RUBY_DLL=L\"#{ruby_dll(tree)}\"", *includes(tree)]
      sources.each do |source|
        report = File.join(@build_dir, "#{File.basename(source, '.c')}.plist")
        @builder.run(tool("clang"), "--analyze", "-Xclang", "-analyzer-werror", *flags, source, "-o", report)
        @builder.run(tool("clang"), "--analyze", "-Xclang", "-analyzer-werror", *flags, "-DFLEDGE_WINDOWED", source, "-o", report)
      end
      resources = File.join(@build_dir, "windows.res.o")
      @builder.run(tool("windres"), "windows.rc", "-O", "coff", "-o", resources, chdir: LAUNCHER)
      windowed = File.join(@build_dir, "launcher-windowed.exe")
      @builder.run(tool("clang"), "-O2", *flags, *sources, resources, "-mconsole", "-s", "-o", output)
      @builder.run(tool("clang"), "-O2", *flags, "-DFLEDGE_WINDOWED", *sources, resources, "-mwindows", "-s", "-o", windowed)
      check(output, CONSOLE, IMPORTS)
      check(windowed, GUI, Regexp.union(IMPORTS, WINDOWED_IMPORTS))
    end

    private def check(program, subsystem, allowed)
      actual = RuntimeBuilder.pe_subsystem(program)
      raise "#{program} has PE subsystem #{actual}, not #{subsystem}" unless actual == subsystem

      imports = @builder.capture(tool("objdump", prefix: "llvm-"), "-p", program).scan(/DLL Name: (\S+)/).flatten
      raise "#{program} imports no DLLs, which is not a Windows program" if imports.empty?

      foreign = imports.grep_v(allowed)
      raise "#{program} imports DLLs Windows does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end

    private def tool(name, prefix: "#{TARGET}-")
      File.join(@toolchain, "bin", "#{prefix}#{name}")
    end

    private def includes(tree)
      headers = Dir.glob(File.join(tree, "include", "ruby-*")).first or raise "#{tree} has no Ruby headers"
      ["-isystem", headers, "-isystem", File.join(headers, "x64-mingw-ucrt"), "-I", LAUNCHER]
    end

    # The name of Ruby's DLL in bin\, such as x64-ucrt-ruby400.dll.
    private def ruby_dll(tree)
      dlls = Dir.glob(File.join(tree, "bin", "*-ruby*.dll"))
      raise "#{tree}/bin holds no single Ruby DLL: #{dlls}" unless dlls.size == 1

      File.basename(dlls.first.to_s)
    end

    private def unpack_rubyinstaller
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(@builder.platform.name)
      archive = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      verify(archive, pin.fetch("signature"))
      unpacked = File.join(@build_dir, "rubyinstaller")
      FileUtils.mkdir_p(unpacked)
      extract_7z(archive, unpacked)
      trees = Dir.glob(File.join(unpacked, "*")).select { |path| File.directory?(path) }
      raise "#{archive} does not hold one RubyInstaller tree: #{trees}" unless trees.size == 1

      trees.first.to_s
    end

    # Checks +archive+ against its detached signature with gpgv, which
    # trusts only the keyring it is given: here, the one key the pin
    # names, and the signature must be that key's, by fingerprint.
    private def verify(archive, pin)
      signature = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      key = pin.fetch("key")
      keyring = File.join(@build_dir, "rubyinstaller-signing-key.gpg")
      File.binwrite(keyring, RuntimeBuilder.dearmor(File.read(@builder.fetch(key.fetch("url"), key.fetch("sha256")))))
      gpgv = @builder.which("gpgv") or raise "checking RubyInstaller's signature needs gpgv (GnuPG) on PATH"
      status = @builder.capture(gpgv, "--keyring", keyring, "--status-fd", "1", signature, archive)
      fingerprint = key.fetch("fingerprint")
      raise "#{archive} is not signed by #{fingerprint}" unless status.match?(/^\[GNUPG:\] VALIDSIG #{fingerprint} /)

      puts "#{File.basename(archive)}: good signature from #{fingerprint}"
    end

    # 7-Zip where it is installed (Ubuntu's runners), and libarchive's
    # bsdtar otherwise (macOS's own tar).
    private def extract_7z(archive, into)
      if (seven_zip = @builder.which("7z", "7zz"))
        @builder.run(seven_zip, "x", "-y", "-bd", "-o#{into}", archive, out: File::NULL)
      elsif (bsdtar = @builder.which("bsdtar"))
        @builder.run(bsdtar, "-xf", archive, "-C", into)
      else
        raise "unpacking #{archive} needs 7z or bsdtar on PATH"
      end
    end

    private def unpack_toolchain
      pin = @builder.sources.fetch("llvm-mingw").fetch("hosts").fetch(@builder.host.name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      toolchain = File.join(@build_dir, "llvm-mingw")
      FileUtils.mkdir_p(toolchain)
      @builder.run("tar", "-xJf", tarball, "-C", toolchain, "--strip-components=1")
      toolchain
    end
  end
end

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  puts RuntimeBuilder.new(platform:).call
end
