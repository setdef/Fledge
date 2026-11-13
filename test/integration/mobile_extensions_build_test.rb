# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"

# Native gems on phones (ADR 022), compiled for real: a gem's extension
# for every target of a phone, with the real mobile runtimes and tools
# where this computer has them. test/mobile_extensions_test.rb covers
# which extensions Fledge compiles and how it writes what links them.
class MobileExtensionsBuildTest < Minitest::Test
  # The folder by its long names, as Dir.glob names what it finds in it
  # (Fledge::LongPath), where Windows' TMP names it by an 8.3 name.
  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def ios = Fledge::MobilePlatform.find("ios")
  def android = Fledge::MobilePlatform.find("android")

  # The real tools: Xcode and a built iOS runtime, as rake runtime writes
  # it, and the desktop runtime of this Mac, whose Ruby runs mkmf.
  # Without the iOS runtime they skip even where FLEDGE_REQUIRE_RUNTIME
  # is set, since that asks for this computer's own runtime, the one CI's
  # Test jobs download. Those jobs run on macos-15, which has neither the
  # Xcode runtime/sources.yml pins nor XcodeGen. The Mobile apps (iOS
  # Simulator) job has both, and builds examples/native_phone with fledge
  # build ios, compiles it with Xcode for both slices, and runs it.
  def test_a_c_extension_is_compiled_for_the_device_and_the_simulator
    runtimes = real_runtimes("ios")
    greeter = File.expand_path("../../examples/native_phone/gems/adder", __dir__)
    spec_package = Fledge::PathPackage.new(path_gem(greeter))
    built = compile(runtimes, ios, { path_gem(greeter) => spec_package })

    assert_equal [["adder/adder", "Init_fledge_0"]], built.registrations
    assert_equal ["app/vendor/cache/adder/lib/adder/adder.rb"], built.stubs.map(&:path)
    assert_equal %w[ios-arm64 ios-arm64-simulator], built.targets.keys
    platforms = built.targets.transform_values do |target|
      archive = target.archives.fetch(0)
      assert_includes Open3.capture2("xcrun", "nm", archive).first, " T _Init_fledge_0"
      object = Dir.glob(File.join(File.dirname(archive), "*.o")).first.to_s
      Open3.capture2("xcrun", "vtool", "-show-build", object).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # An extconf.rb that writes extconf.h, as many do, takes mkmf's $defs
  # off the compile line (mkmf.rb's create_makefile), so the extension's
  # Init function is still renamed only if the rename goes elsewhere.
  def test_an_extconf_that_writes_its_header_has_its_init_function_renamed
    runtimes = real_runtimes("ios")
    gem = extconf_gem("headed", <<~RUBY, "headed.c" => "#include <ruby.h>\nvoid Init_headed(void) { rb_define_module(\"Headed\"); }\n")
      require "mkmf"
      have_header("stdint.h")
      create_header
      create_makefile("headed/headed")
    RUBY

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    assert_equal [["headed/headed", "Init_fledge_0"]], built.registrations
    built.targets.each_value do |target|
      symbols = Open3.capture2("xcrun", "nm", "-g", "--defined-only", target.archives.fetch(0)).first
      assert_match(/ T _Init_fledge_0$/, symbols)
      refute_match(/ T _Init_headed$/, symbols)
    end
  end

  # examples/cmake_phone's extconf.rb runs CMake, which builds its C++
  # library from CMAKE_TOOLCHAIN_FILE for each slice (ADR 027): the
  # device's objects are for iOS and the Simulator's for the Simulator,
  # as each slice's extension is.
  def test_a_cmake_library_an_extconf_builds_is_built_for_each_ios_slice
    runtimes = real_runtimes("ios")
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?
    built = compile(runtimes, ios, { tally_gem => Fledge::PathPackage.new(tally_gem) })

    assert_equal [["tally/tally", "Init_fledge_0"]], built.registrations
    platforms = built.targets.transform_values do |target|
      library = target.archives.find { |archive| File.basename(archive) == "libtally.a" } or flunk "no libtally.a in #{target.archives}"
      assert target.cxx, "the extension names the C++ runtime"
      refute_includes target.flags, "-lc++"
      object = Dir.glob(File.join(File.dirname(library), "**", "tally.cc.o")).first.to_s
      Open3.capture2("xcrun", "vtool", "-show-build", object).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # The same for each Android ABI with the NDK, where this computer has
  # one: libfledgeext.so holds the library's code, and needs no C++
  # runtime the package does not carry.
  def test_a_cmake_library_an_extconf_builds_is_linked_for_each_android_abi
    runtimes = real_runtimes("android")
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?
    ndk = begin
      Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
    rescue Fledge::Error => e
      skip e.message
    end
    built = compile(runtimes, android, { tally_gem => Fledge::PathPackage.new(tally_gem) })
    registration = File.join(@dir, "registration.c")
    File.write(registration, Fledge::MobileExtensions.registration_source(built.registrations))
    compiler = Fledge::MobileExtensions.new(platform: android, packages: {}, build_args: {}, host: Fledge::Platform.local,
      runtimes: Fledge::Runtimes.new(env: ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes)), work: File.join(@dir, "work"), log: StringIO.new,
      gem_dir: "lib/ruby/gems/4.1.0+5")
    machines = built.targets.to_h do |name, build|
      library = compiler.shared_library(built, build, registration:, into: File.join(@dir, name, "libfledgeext.so"))
      readelf = File.join(ndk.bin, "llvm-readelf")
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", library).first
      refute_match(/UND\s+tally_/, dynamic, "#{name}: the library's code is linked in")
      refute_includes dynamic, "libc++_shared.so", "#{name}: the C++ runtime is linked in statically"
      refute_match(/UND\s+(?:_ZNSt|_Znwm|_ZdlPv|__gxx_personality)/, dynamic, "#{name}: the C++ runtime is linked in")
      assert_match(/\(RUNPATH\)\s+Library runpath: \[\$ORIGIN\]/, dynamic, "#{name}: the ruby program finds what it needs beside it")
      [name, Open3.capture2(readelf, "-h", library).first[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
  end

  # A Rakefile shaped like digest-crc's runs an extconf.rb and make in
  # the folder of each extension, and leaves each where the gem's require
  # path ext finds it. RubyGems' builder runs it with the phone's
  # rbconfig.rb, the compiler wrapper turns each shared link into an
  # archive for the slice, and each extension registers under the name
  # its path gives it, its Init function renamed.
  def test_the_extensions_a_rakefile_builds_are_archived_for_each_ios_slice
    runtimes = real_runtimes("ios")
    built = compile(runtimes, ios, { rakesum_gem => Fledge::PathPackage.new(rakesum_gem) })

    assert_equal [%w[rakesum/adler/adler_ext Init_fledge_0_adler_ext], %w[rakesum/fletcher/fletcher_ext Init_fledge_0_fletcher_ext]],
      built.registrations.sort
    assert_empty built.stubs, "RubyGems copies no Rakefile's extension into the gem's require path"
    platforms = built.targets.transform_values do |target|
      assert_equal 2, target.archives.size
      target.archives.map do |archive|
        symbols = Open3.capture2("xcrun", "nm", "-g", "--defined-only", archive).first
        assert_match(/ T _Init_fledge_0_(?:adler|fletcher)_ext$/, symbols)
        refute_match(/ T _Init_(?:adler|fletcher)_ext$/, symbols, "the extension's own Init function is renamed")
        members = File.join(@dir, "members", File.basename(archive))
        FileUtils.mkdir_p(members)
        system("ar", "-x", archive, chdir: members, exception: true)
        object = Dir.children(members).find { |member| member.end_with?(".o") }.to_s
        Open3.capture2("xcrun", "vtool", "-show-build", File.join(members, object)).first[/platform (\S+)/, 1]
      end.uniq
    end
    assert_equal({ "ios-arm64" => ["IOS"], "ios-arm64-simulator" => ["IOSSIMULATOR"] }, platforms)
  end

  # A Rakefile that links a library for Ruby's ffi, as ffi-compiler's
  # tasks do with RbConfig's compiler, makes no extension of Ruby's,
  # which is all a phone app links in: the build says so, naming the gem
  # and the library.
  def test_a_library_for_ffi_a_rakefile_links_is_refused_by_name
    runtimes = real_runtimes("ios")
    gem = rake_gem("thing", <<~'RAKEFILE', "thing.c" => "int thing(void) { return 1; }\n")
      task :default do
        sh "#{RbConfig::CONFIG['CC']} -c thing.c -o thing.o"
        sh "#{RbConfig::CONFIG['CC']} -shared -o libthing.so thing.o"
      end
    RAKEFILE

    error = assert_raises(Fledge::Error) { compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) }) }

    assert_includes error.message, "thing 1.0.0's Rakefile linked libthing.so for ios-arm64, a shared library that is not an extension mkmf built"
  end

  # A Rakefile that builds nothing, as the mkrf_conf scripts that install
  # a gem's dependencies leave behind, makes no extension to link.
  def test_a_rakefile_that_builds_nothing_registers_nothing
    runtimes = real_runtimes("ios")
    gem = rake_gem("quiet", "task :default\n")

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    assert_empty built.registrations
    assert_equal({ "ios-arm64" => [], "ios-arm64-simulator" => [] }, built.targets.transform_values(&:archives))
  end

  def test_fledge_build_ios_links_the_extensions_into_the_project
    runtimes = real_runtimes("ios")
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out:, err:, env:).call(["ios", "-o", File.join(@dir, "dist"), File.expand_path("../../examples/native_phone", __dir__)])

    assert_equal 0, status, err.string
    project = File.join(@dir, "dist", "NativePhone-ios")
    assert_equal %w[Info.plist ios-arm64 ios-arm64-simulator], Dir.children(File.join(project, "FledgeExtensions.xcframework")).sort
    unit = File.read(File.join(project, "Host", "fledge_extensions.c"))
    assert_includes unit, 'fledge_ruby_add_extension("adder/adder", Init_fledge_0)'
    stub = File.join(project, "fledge", "app", "gems", "adder", "lib", "adder", "adder.rb")
    assert_equal Fledge::MobileExtensions::Stub.source("adder/adder"), File.read(stub), "lib/adder.rb's require_relative finds it"
    yml = File.read(File.join(project, "project.yml"))
    assert_includes yml, "- framework: FledgeExtensions.xcframework"
    assert_includes yml, 'OTHER_LDFLAGS: "$(inherited) -lc++"'
    marks = Dir.glob(File.join(project, "fledge", "lib", "ruby", "gems", "*", "**", "gem.build_complete"))
    assert_empty marks, "a path gem needs no mark, as on a desktop"
  end

  def tally_gem
    folder = File.expand_path("../../examples/cmake_phone/gems/tally", __dir__)
    Fledge::PathGem.new(name: "tally", version: "1.0.0", folder:, app_path: "vendor/cache/tally", glob: "{,*,*/*}.gemspec", inside: true)
  end

  def rakesum_gem
    folder = File.expand_path("../fixtures/rakesum", __dir__)
    Fledge::PathGem.new(name: "rakesum", version: "1.0.0", folder:, app_path: "vendor/cache/rakesum", glob: "{,*,*/*}.gemspec", inside: true)
  end

  # A path gem +name+ whose gemspec names ext/NAME/extconf.rb, with
  # +extconf+ and +files+ in ext/NAME/.
  def extconf_gem(name, extconf, files = {})
    folder = File.join(@dir, "gems", name)
    FileUtils.mkdir_p(File.join(folder, "ext", name))
    File.write(File.join(folder, "ext", name, "extconf.rb"), extconf)
    files.each { |file, text| File.write(File.join(folder, "ext", name, file), text) }
    File.write(File.join(folder, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "An extconf.rb's extension"
        spec.files = #{(["ext/#{name}/extconf.rb"] + files.keys.map { |file| "ext/#{name}/#{file}" }).inspect}
        spec.extensions = ["ext/#{name}/extconf.rb"]
      end
    RUBY
    Fledge::PathGem.new(name:, version: "1.0.0", folder:, app_path: "vendor/cache/#{name}", glob: "{,*,*/*}.gemspec", inside: true)
  end

  # A path gem +name+ whose gemspec names ext/Rakefile, with +rakefile+
  # and +files+ in ext/.
  def rake_gem(name, rakefile, files = {})
    folder = File.join(@dir, "gems", name)
    FileUtils.mkdir_p(File.join(folder, "ext"))
    File.write(File.join(folder, "ext", "Rakefile"), rakefile)
    files.each { |file, text| File.write(File.join(folder, "ext", file), text) }
    File.write(File.join(folder, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "A Rakefile's extension"
        spec.files = #{(['ext/Rakefile'] + files.keys.map { |file| "ext/#{file}" }).inspect}
        spec.extensions = ["ext/Rakefile"]
      end
    RUBY
    Fledge::PathGem.new(name:, version: "1.0.0", folder:, app_path: "vendor/cache/#{name}", glob: "{,*,*/*}.gemspec", inside: true)
  end

  def cmake?
    system("cmake", "--version", out: File::NULL, err: File::NULL) || false
  end

  def real_runtimes(name)
    skip "Xcode builds the iOS slices on a Mac only" unless Fledge::Platform.local.name == "arm64-darwin" || name != "ios"
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    phone = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(name)))
    skip "no #{File.basename(phone)} in #{dir}; run bundle exec rake runtime[#{name}]" unless File.file?(phone)
    dir
  end

  def path_gem(folder)
    Fledge::PathGem.new(name: "adder", version: "1.0.0", folder:, app_path: "vendor/cache/adder", glob: "{,*,*/*}.gemspec", inside: true)
  end

  def compile(runtimes_dir, phone, packages)
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes_dir)
    runtimes = Fledge::Runtimes.new(env:)
    tree = File.join(@dir, "tree")
    Fledge::Archive.unpack(runtimes.archive(phone), into: tree)
    log = StringIO.new
    Fledge::MobileExtensions.new(platform: phone, packages:, build_args: {}, host: Fledge::Platform.local, runtimes:,
      work: File.join(@dir, "work"), log:, gem_dir: "lib/ruby/gems/4.1.0+5", env:).call(File.join(tree, Dir.children(tree).first))
  rescue Fledge::Error => e
    raise Fledge::Error, "#{e.message}\n#{log&.string}"
  end
end
