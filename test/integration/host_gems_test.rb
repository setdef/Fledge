# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"

# The gems a Rakefile's build requires, compiled for this computer
# (Fledge::MobileExtensions::HostGems), for real: ffi 1.17.4 from
# rubygems.org, which ffi-compiler requires, compiled with this Mac's
# runtime's Ruby and loaded by it. It needs this computer's runtime, as
# rake runtime writes it, and skips without one unless
# FLEDGE_REQUIRE_RUNTIME is set, as in CI's Test jobs.
class HostGemsTest < Minitest::Test
  FFI = "ffi-1.17.4"
  FFI_SHA256 = "bcd1642e06f0d16fc9e09ac6d49c3a7298b9789bcb58127302f934e437d60acf"
  CACHE = File.expand_path("../../tmp/host-gems", __dir__)

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    name = Fledge::Runtimes.file_name(@platform)
    unless File.file?(File.join(@runtimes, name))
      message = "no #{name} in #{@runtimes}; run bundle exec rake runtime"
      flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
      skip message
    end
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # A Mac may offer a libffi whose header and library disagree. On
  # GitHub's macos-26 runner, which has Homebrew's pkgconf, ffi's
  # extconf.rb chose the system's libffi, and the ffi it compiled failed
  # to load: symbol not found in flat namespace '_ffi_type_longdouble',
  # which its header declared and macOS's libffi exports only for x86_64.
  # macOS's own header defines it as ffi_type_double on arm64, and
  # libffi's own declares it everywhere (libffi/include/ffi.h.in in the
  # gem). Such a libffi here, a pkg-config naming a header that declares
  # it over macOS's library, changes nothing: the host's ffi is compiled
  # with the libffi it bundles, as ffi's own arm64-darwin gem is, and
  # loads.
  def test_the_hosts_ffi_compiles_with_its_own_libffi_whatever_libffi_this_mac_offers
    skip "macOS's own libffi lacks ffi_type_longdouble on arm64 only" unless @platform.name == "arm64-darwin"
    foreign = disagreeing_libffi

    with_path(foreign) do
      load_path = host_gems.load_path
      out, status = Open3.capture2e(scrubbed_env, runtime_ruby, *load_path.flat_map { |path| ["-I", path] },
        "-e", "require 'ffi'; puts FFI::Type::LONGDOUBLE.size")

      assert status.success?, out
      assert_equal "8", out.strip
    end
  end

  def host_gems
    package = Fledge::GemPackage.new(ffi_gem)
    locked = Fledge::LockedGem.new(name: "ffi", version: "1.17.4", platform: "ruby", remote: "https://rubygems.org/", sha256: FFI_SHA256,
      credentials: nil)
    spec = Gem::Specification.new do |each|
      each.name = "thing"
      each.version = "1.0.0"
      each.add_dependency "ffi"
    end
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => @runtimes)
    @build = Fledge::NativeBuild.new(platform: @platform, runtimes: Fledge::Runtimes.new(env:), work: File.join(@dir, "host-gems"),
      log: StringIO.new, env:)
    Fledge::MobileExtensions::HostGems.new(specs: [spec], dependencies: { locked => package }, build: @build,
      work: File.join(@dir, "host-gems", "gems"))
  end

  def ffi_gem
    path = File.join(CACHE, "#{FFI}.gem")
    Fledge::Download.save("https://rubygems.org/gems/#{FFI}.gem", to: path, sha256: FFI_SHA256) unless File.file?(path)
    path
  end

  # A folder holding libffi's own header, as its source ships it, beside
  # macOS's ffitarget.h, and a pkg-config that names that header and
  # macOS's library for libffi, as Homebrew's pkgconf answers with a
  # libffi.pc.
  def disagreeing_libffi
    folder = File.join(@dir, "foreign")
    include = File.join(folder, "include")
    FileUtils.mkdir_p(include)
    sdk = Open3.capture2("xcrun", "--sdk", "macosx", "--show-sdk-path").first.strip
    FileUtils.cp(File.join(sdk, "usr", "include", "ffi", "ffitarget.h"), include)
    header = File.read(File.join(sdk, "usr", "include", "ffi", "ffi.h"))
      .sub("#define ffi_type_longdouble ffi_type_double", "FFI_EXTERN ffi_type ffi_type_longdouble;")
    File.write(File.join(include, "ffi.h"), header)
    File.write(File.join(folder, "pkg-config"), <<~SH)
      #!/bin/sh
      for arg in "$@"; do
        case "$arg" in
          --exists|--atleast-pkgconfig-version*) exit 0 ;;
          --modversion) echo 3.4-rc1; exit 0 ;;
          --cflags-only-I|--cflags) echo "-I#{include}"; exit 0 ;;
          --libs-only-l|--libs) echo "-lffi"; exit 0 ;;
          --cflags-only-other|--libs-only-L|--libs-only-other) echo; exit 0 ;;
        esac
      done
      exit 1
    SH
    File.chmod(0o755, File.join(folder, "pkg-config"))
    folder
  end

  def with_path(folder)
    saved = ENV.fetch("PATH")
    ENV["PATH"] = "#{folder}#{File::PATH_SEPARATOR}#{saved}"
    yield
  ensure
    ENV["PATH"] = saved
  end

  def runtime_ruby
    Dir.glob(File.join(@dir, "host-gems", "native-#{@platform}", "ruby", "*", "bin", "ruby")).fetch(0)
  end

  def scrubbed_env
    ENV.keys.grep(Fledge::NativeBuild::SCRUBBED).to_h { |name| [name, nil] }
  end
end
