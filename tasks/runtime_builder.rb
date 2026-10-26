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

# Builds the runtime for the platform it runs on (ADR 001, section 2).
#
# A runtime is the launcher in runtime/launcher/, compiled against
# rv-ruby's static libruby, beside rv-ruby's standard library and
# default gems, its CA bundle, and the license notices of everything it
# carries. Fledge's CI runs this on each platform's own runner, because
# the launcher is native code and nothing here cross-compiles; then
# fledge build, on any computer, copies apps into the results.
#
# Every input comes from runtime/sources.yml and is checked against its
# SHA-256. The steps that differ by operating system (compiler flags,
# stripping, libxcrypt) live in a recipe per OS, Darwin and Linux, so a
# Windows recipe can join them. The layout and pruning rules are those
# the Unix launcher spike settled (Plan 001).
#
# Run it as rake runtime, or as ruby tasks/runtime_builder.rb in a
# container that has a C toolchain and any Ruby.
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

  # Folders and files of rv-ruby's gem directory that a runtime keeps.
  # Default gems stay; bundled gems, caches, docs, and build leftovers
  # go (Plan 001: "A runtime per target").
  KEPT_GEM_FOLDERS = %w[gems specifications].freeze

  attr_reader :platform, :sources

  def initialize(platform: Fledge::Platform.local, work: File.join(ROOT, "tmp", "runtime"),
    downloads: File.join(ROOT, "tmp", "downloads"), sources: File.join(ROOT, "runtime", "sources.yml")
  )
    @platform = platform
    @work = work
    @downloads = downloads
    @sources = YAML.safe_load_file(sources)
  end

  # Builds the runtime and returns the path of its archive.
  def call
    raise "#{platform} runtimes build on #{platform} only; this is #{Fledge::Platform.local}" unless platform == Fledge::Platform.local

    FileUtils.rm_rf(build_dir)
    prefix = unpack_ruby
    recipe = recipe_class.new(builder: self, prefix:, build_dir:)
    FileUtils.mkdir_p(stage)
    recipe.compile(File.join(stage, "launcher"))
    copy_ruby(prefix)
    recipe.finish(stage)
    write_notices(stage)
    archive
  end

  # The folder that becomes the runtime archive's top folder.
  def stage
    File.join(build_dir, "stage", top)
  end

  def top
    File.basename(Fledge::Runtimes.file_name(platform), platform.archive_extension)
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

  # Runs a command, echoing it, and raises when it fails.
  def run(*command, chdir: ROOT)
    puts "+ #{command.join(' ')}"
    system(*command, chdir:, exception: true)
  end

  # Runs a command and returns its standard output.
  def capture(*command)
    out, status = Open3.capture2(*command)
    raise "#{command.join(' ')} failed" unless status.success?

    out
  end

  # Removes what a shipped app never needs from a copy of rv-ruby's
  # lib/ruby at +ruby+: debug symbols, rv-ruby's bundled-gem load path
  # helper, bundled gems and their caches and docs, and anything for
  # compiling against Ruby.
  def self.prune(ruby)
    FileUtils.rm_rf(Dir.glob(File.join(ruby, "**", "*.dSYM")))
    FileUtils.rm_f(Dir.glob(File.join(ruby, "*", "*", "portable_ruby_gems.rb")))
    FileUtils.rm_f(Dir.glob(File.join(ruby, "**", "*.{a,h}")))
    FileUtils.rm_rf(Dir.glob(File.join(ruby, "**", "pkgconfig")))
    Dir.glob(File.join(ruby, "gems", "*")).each { |gems| prune_gems(gems) }
  end

  def self.prune_gems(gems)
    (Dir.children(gems) - KEPT_GEM_FOLDERS).each { |name| FileUtils.rm_rf(File.join(gems, name)) }
    default = Dir.glob(File.join(gems, "specifications", "default", "*.gemspec")).map { |spec| File.basename(spec, ".gemspec") }
    FileUtils.rm_f(Dir.glob(File.join(gems, "specifications", "*.gemspec")))
    Dir.glob(File.join(gems, "gems", "*")).each do |gem|
      FileUtils.rm_rf(gem) unless default.include?(File.basename(gem))
    end
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
    platform.name.end_with?("-darwin") ? Darwin : Linux
  end

  private def unpack_ruby
    pin = sources.fetch("ruby").fetch("platforms").fetch(platform.name)
    tarball = fetch(pin.fetch("url"), pin.fetch("sha256"))
    unpacked = File.join(build_dir, "rv-ruby")
    FileUtils.mkdir_p(unpacked)
    run("tar", "-xzf", tarball, "-C", unpacked)
    prefixes = Dir.glob(File.join(unpacked, "*", sources.fetch("ruby").fetch("version")))
    raise "#{tarball} does not hold one Ruby prefix: #{prefixes}" unless prefixes.size == 1

    prefixes.first
  end

  private def copy_ruby(prefix)
    FileUtils.mkdir_p(File.join(stage, "lib"))
    FileUtils.cp_r(File.join(prefix, "lib", "ruby"), File.join(stage, "lib", "ruby"))
    FileUtils.chmod_R("u+w", File.join(stage, "lib"))
    self.class.prune(File.join(stage, "lib", "ruby"))
    install_rubygems_defaults(File.join(stage, "lib", "ruby"))
    FileUtils.mkdir_p(File.join(stage, "libexec"))
    FileUtils.cp(File.join(prefix, "libexec", "cert.pem"), File.join(stage, "libexec", "cert.pem"))
  end

  # Keeps RubyGems to the runtime's gems; see the file's own comment.
  private def install_rubygems_defaults(ruby)
    version = sources.fetch("ruby").fetch("version").sub(/\.\d+\z/, ".0")
    defaults = File.join(ruby, version, "rubygems", "defaults")
    raise "#{ruby} has no RubyGems at #{version}" unless File.directory?(File.dirname(defaults))

    FileUtils.mkdir_p(defaults)
    FileUtils.cp(File.join(ROOT, "runtime", "rubygems", "operating_system.rb"), defaults)
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

  # What every recipe shares: the C sources and the include flags for
  # rv-ruby's headers.
  class Recipe
    LAUNCHER = File.join(ROOT, "runtime", "launcher")

    def initialize(builder:, prefix:, build_dir:)
      @builder = builder
      @prefix = prefix
      @build_dir = build_dir
    end

    private def sources(os_file)
      [File.join(LAUNCHER, "unix.c"), File.join(LAUNCHER, os_file)]
    end

    private def includes
      headers = Dir.glob(File.join(@prefix, "include", "ruby-*")).first or raise "#{@prefix} has no Ruby headers"
      arch = Dir.glob(File.join(headers, "*")).find { |dir| File.directory?(dir) && File.basename(dir) != "ruby" }
      ["-isystem", arch.to_s, "-isystem", headers, "-I", LAUNCHER]
    end
  end

  # macOS: link libruby whole into the launcher, which exports its
  # symbols to extensions by default; ad hoc sign it, since Apple Silicon
  # runs only signed code.
  class Darwin < Recipe
    def compile(output)
      cc = ENV.fetch("CC", "clang")
      sources("darwin.c").each do |source|
        report = File.join(@build_dir, "#{File.basename(source, '.c')}.plist")
        @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", "-std=gnu11", *includes, source, "-o", report)
      end
      static = File.join(@prefix, "lib", "libruby.4.0-static.a")
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, "-mmacosx-version-min=14.0", *includes, *sources("darwin.c"),
        "-Wl,-force_load,#{static}", "-framework", "CoreFoundation", "-ldl", "-lobjc", "-lpthread", "-o", output)
      @builder.run("strip", "-x", output)
      @builder.run("codesign", "--sign", "-", "--force", output)
      check_libraries(output)
    end

    def finish(_stage); end

    private def check_libraries(output)
      libraries = @builder.capture("otool", "-L", output).lines.drop(1).map { |line| line.strip.split.first.to_s }
      foreign = libraries.reject { |library| library.start_with?("/usr/lib/", "/System/Library/") }
      raise "the launcher links libraries macOS does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end

  # Linux: link libruby whole and export its symbols (-rdynamic), take
  # libgcc's unwinder statically, and link libxcrypt dynamically from
  # the runtime's lib/ (see runtime/launcher/unix.c).
  class Linux < Recipe
    # The shared libraries the launcher may need: glibc's, and the
    # runtime's own libxcrypt.
    ALLOWED = /\A(?:libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux[-\w.]*\.so\.\d|libcrypt\.so\.\d+)\z/

    def compile(output)
      xcrypt = build_libxcrypt
      cc = ENV.fetch("CC", "cc")
      sources("linux.c").each do |source|
        @builder.run(cc, "-fanalyzer", "-Werror", "-std=gnu11", *includes, "-c", source, "-o", File::NULL)
      end
      static = File.join(@prefix, "lib", "libruby-static.a")
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, *includes, *sources("linux.c"), "-rdynamic", "-static-libgcc",
        "-Wl,--whole-archive", static, "-Wl,--no-whole-archive", "-L#{File.join(xcrypt, 'lib')}", "-lcrypt",
        "-Wl,--disable-new-dtags,-rpath,$ORIGIN/lib", "-lrt", "-ldl", "-lm", "-lpthread", "-o", output)
      @builder.run("strip", "--strip-unneeded", output)
      copy_libcrypt(xcrypt, File.join(File.dirname(output), "lib"))
      check_dynamic_section(output)
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

    private def check_dynamic_section(output)
      dynamic = @builder.capture("readelf", "-d", output)
      raise "the launcher has a RUNPATH, which LD_LIBRARY_PATH overrides" if dynamic.include?("(RUNPATH)")
      raise "the launcher has no RPATH of $ORIGIN/lib" unless dynamic.include?("Library rpath: [$ORIGIN/lib]")

      needed = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(ALLOWED)
      raise "the launcher needs libraries a runtime does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end

puts RuntimeBuilder.new.call if $PROGRAM_NAME == __FILE__
