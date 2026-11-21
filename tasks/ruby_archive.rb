# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "open3"
require_relative "runtime_builder"

# Builds the relocatable CRuby Fledge publishes for glibc Linux and
# macOS, in the shape of rv-ruby's archives, so that a runtime's pin in
# runtime/sources.yml can name either and the Unix recipe copies a
# runtime from either alike, and so that a developer can install it as
# their Ruby (doc/contributors/design/runtimes.md, "Fledge's own Ruby
# builds"). The archive holds one folder, ruby/VERSION/, a prefix of
# Ruby's own layout: bin/, include/, lib/ with the static libruby and
# lib/ruby, and libexec/cert.pem.
#
# The Ruby is built as the musl runtimes' is (RuntimeBuilder::RubyBuild),
# from ruby-build's ruby pin and musl-ruby's library pins, with YJIT and
# ZJIT, by the Rust compiler ruby-build pins. On glibc Linux, bin/ruby
# links libxcrypt, built from its pin as a runtime builds it, from
# lib/libcrypt.so.2 beside it, and every compiled file must run on
# GLIBC_FLOOR; on macOS, on the macOS floor (Fledge::Platform).
class RubyArchive
  # The oldest glibc the archive runs on: Ubuntu 22.04's, where Lota's CI
  # installs its development Ruby. Apps' floor stays
  # Fledge::Platform::GLIBC_MINIMUM, which Fledge's own programs set.
  GLIBC_FLOOR = "2.35"

  # OpenSSL's Configure target for each platform.
  OPENSSL_TARGETS = {
    "x86_64-linux" => "linux-x86_64",
    "aarch64-linux" => "linux-aarch64",
    "arm64-darwin" => "darwin64-arm64-cc",
  }.freeze

  def initialize(platform: Fledge::Platform.local, work: File.join(RuntimeBuilder::ROOT, "tmp", "ruby-archive"),
    builder: RuntimeBuilder.new(platform:, work:)
  )
    @platform = platform
    @work = work
    @builder = builder
  end

  # Builds, checks, and archives the Ruby, and returns the archive's path.
  def call
    FileUtils.rm_rf(build_dir)
    top = File.join(build_dir, "ruby")
    prefix = build(File.join(top, version))
    check(prefix)
    ReleaseArchive.pack(top, File.join(@work, "ruby-#{version}-#{@platform.name}.tar.gz"), top: "ruby")
  end

  def version
    pins.fetch("ruby").fetch("version")
  end

  # The pins the Ruby builds from: ruby-build's Ruby source, and the
  # libraries and certificates musl-ruby pins.
  def pins
    @builder.sources.fetch("musl-ruby").merge("ruby" => @builder.sources.fetch("ruby-build").fetch("ruby"))
  end

  def ruby_build(xcrypt)
    RuntimeBuilder::RubyBuild.new(builder: @builder, build_dir:, pins:, edits: [],
      openssl_target: OPENSSL_TARGETS.fetch(@platform.name), options: ["--enable-zjit"], library_path: xcrypt,
      env: environment(xcrypt))
  end

  # Rewrites what Ruby's install recorded of the build folder, in
  # rbconfig.rb and Ruby's pkg-config file, so that mkmf, pkg-config, and
  # what reads either (CMake, rb-sys) find Ruby's headers and libraries
  # wherever the archive is unpacked. With --enable-load-relative,
  # rbconfig.rb already finds its prefix from its own folder. It still
  # records the libxcrypt folder Ruby linked from, which becomes the
  # prefix's lib/, where the library now is, and that library's headers'
  # folder, which no installed header needs; the folder of the libraries
  # linked statically into the extensions, which nothing outside the
  # build has; and the prefix itself, in configure_args and in the
  # fallback for an rbconfig.rb loaded from elsewhere, which becomes the
  # folder's name in the archive, /ruby/VERSION. The pkg-config file's
  # prefix becomes its own folder's, by pkg-config's pcfiledir.
  def relocate(prefix, xcrypt)
    Dir.glob(File.join(prefix, "lib", "ruby", "*", "*", "rbconfig.rb")).each do |path|
      rewrite(path, xcrypt, libdir: "$(libdir)") { |text| text.gsub(prefix, "/ruby/#{version}") }
    end
    Dir.glob(File.join(prefix, "lib", "pkgconfig", "*.pc")).each do |path|
      rewrite(path, xcrypt, libdir: "${libdir}") { |text| text.sub(/^prefix=#{Regexp.escape(prefix)}$/, "prefix=${pcfiledir}/../..") }
    end
  end

  # Fails when rbconfig.rb, a pkg-config file, or a header still names a
  # folder of the build, naming each such file and its first such line.
  def check_relocated(prefix)
    named = Dir.glob(File.join(prefix, "{lib/ruby/*/*/rbconfig.rb,lib/pkgconfig/*.pc,include/**/*.h}")).filter_map do |path|
      line = File.foreach(path).find { |text| text.include?(@work) }
      "#{path}: #{line.strip}" if line
    end
    raise "these name the build folder #{@work}:\n#{named.join("\n")}" unless named.empty?
  end

  private def build(prefix)
    xcrypt = linux? ? RuntimeBuilder::Linux.build_libxcrypt(@builder, build_dir) : nil
    ruby_build(xcrypt).call(prefix)
    install_libcrypt(xcrypt, prefix) if xcrypt
    relocate(prefix, xcrypt)
    prefix
  end

  private def rewrite(path, xcrypt, libdir:)
    deps = Regexp.escape(File.join(build_dir, "deps"))
    text = File.read(path).gsub(/ ?'--with-[\w-]+-dir=#{deps}'/, "")
    if xcrypt
      text = text.gsub("-L#{File.join(xcrypt, 'lib')}", "-L#{libdir}").gsub(/-I#{Regexp.escape(File.join(xcrypt, 'include'))} ?/, "")
    end
    File.write(path, yield(text))
  end

  # The build's environment: the pinned Rust compiler first on PATH; on
  # macOS the deployment target of the macOS floor; and on glibc Linux a
  # loader path to the libxcrypt built for it, which miniruby and the
  # Ruby that make install runs need while they run in the build folder.
  # It is the build's alone: nothing installed records it, and the
  # installed bin/ruby finds its libcrypt through $ORIGIN/../lib.
  private def environment(xcrypt)
    rust = install_rust
    env = { "PATH" => [File.join(rust, "bin"), ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) }
    env["MACOSX_DEPLOYMENT_TARGET"] = Fledge::Platform::MACOS_MINIMUM unless linux?
    env["LD_LIBRARY_PATH"] = File.join(xcrypt, "lib") if xcrypt
    env
  end

  # Installs rustc and the Rust standard library, each from its pin,
  # with the installer each tarball carries.
  private def install_rust
    rust = File.join(build_dir, "rust")
    @builder.sources.fetch("ruby-build").fetch("rust").fetch("platforms").fetch(@platform.name).each do |name, pin|
      source = File.join(build_dir, "sources", name)
      FileUtils.mkdir_p(source)
      @builder.run("tar", "-xJf", @builder.fetch(pin.fetch("url"), pin.fetch("sha256")), "-C", source, "--strip-components=1")
      @builder.run("sh", "install.sh", "--prefix=#{rust}", "--disable-ldconfig", chdir: source)
    end
    rust
  end

  # Puts the libcrypt bin/ruby links into the prefix's lib/, with the
  # name the linker looks for when a gem's mkmf links -lcrypt, and has
  # bin/ruby find it there wherever the prefix is.
  private def install_libcrypt(xcrypt, prefix)
    library = Dir.glob(File.join(xcrypt, "lib", "libcrypt.so.*")).find { |path| File.basename(path).match?(/\Alibcrypt\.so\.\d+\z/) }
    raise "libxcrypt built no libcrypt.so.N" unless library

    lib = File.join(prefix, "lib")
    FileUtils.cp(File.realpath(library), File.join(lib, File.basename(library)))
    FileUtils.ln_sf(File.basename(library), File.join(lib, "libcrypt.so"))
    @builder.run("patchelf", "--force-rpath", "--set-rpath", "$ORIGIN/../lib", File.join(prefix, "bin", "ruby"))
  end

  # Fails unless nothing Ruby reads its folders from names the build
  # folder, bin/ruby needs only the system's C library (and on Linux the
  # libcrypt beside it), every compiled file runs on the floor, and both
  # JITs are compiled in.
  private def check(prefix)
    ruby = File.join(prefix, "bin", "ruby")
    check_relocated(prefix)
    check_floor(prefix)
    check_libraries(ruby) if linux?
    %w[yjit zjit].each do |jit|
      enabled = @builder.capture(ruby, "--#{jit}", "-e", "print RubyVM::#{jit.upcase}.enabled?")
      raise "#{ruby} --#{jit} leaves #{jit.upcase} disabled" unless enabled == "true"
    end
  end

  private def check_floor(prefix)
    files = Dir.glob(File.join(prefix, "{bin/ruby,lib/**/*.{so,bundle,dylib}}"))
    readers = Fledge::Binary::Readers.local(linux? ? "linux" : "darwin")
    late = Fledge::Binary.read(files, readers:).filter_map do |path, binary|
      found = linux? ? binary.glibc_minimum : binary.macos_minimum
      "#{path} (#{found})" if found && Gem::Version.new(found) > Gem::Version.new(floor)
    end
    raise "these need more than #{floor}: #{late.join(', ')}" unless late.empty?
  end

  private def check_libraries(ruby)
    dynamic = @builder.capture("readelf", "-d", ruby)
    raise "#{ruby} has a RUNPATH, which LD_LIBRARY_PATH overrides" if dynamic.include?("(RUNPATH)")
    raise "#{ruby} has no RPATH of $ORIGIN/../lib" unless dynamic.include?("Library rpath: [$ORIGIN/../lib]")

    foreign = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten.grep_v(RuntimeBuilder::Linux::ALLOWED)
    raise "#{ruby} needs libraries the archive does not hold: #{foreign.join(', ')}" unless foreign.empty?
  end

  private def floor
    linux? ? GLIBC_FLOOR : Fledge::Platform::MACOS_MINIMUM
  end

  private def linux?
    @platform.os == "linux"
  end

  private def build_dir
    File.join(@work, @platform.name)
  end
end

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  puts RubyArchive.new(platform:).call
end
