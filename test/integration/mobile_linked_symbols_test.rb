# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"
require_relative "../support/android"
require_relative "../support/ios"
require_relative "../../tasks/mobile_parity"

# Which definition each extension linked into a phone's app calls when
# two parts of the app define one name: every iOS
# extension, and on Android those a Rakefile builds, which go into
# libfledgeext.so. Each app is a developer's project of path gems:
# fledge build writes its Xcode or Gradle project, Xcode or Gradle
# builds it, and it runs on the iOS Simulator or the attached Android
# device as tasks/mobile_parity.rb runs the examples, and prints what
# each gem's functions return. Without the runtime, the tools, or a
# Simulator or device they skip, and fail instead where
# FLEDGE_REQUIRE_IOS or FLEDGE_REQUIRE_ANDROID is set.
class MobileLinkedSymbolsTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  # Builds the static library libclash.a from vendor/clash_lib.c, as an
  # extconf.rb's own library is built, and links it into the extension.
  LIB_MK = <<~MAKE
    LIBCLASH = $(shell pwd)/libclash/libclash.a
    LOCAL_LIBS += "$(LIBCLASH)"
    $(OBJS): $(LIBCLASH)
    $(LIBCLASH): $(srcdir)/vendor/clash_lib.c
    \tmkdir -p $(@D) && $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) -c $(srcdir)/vendor/clash_lib.c -o $(@D)/clash_lib.o && $(AR) rcs $@ $(@D)/clash_lib.o
  MAKE

  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Three ways two parts of an iOS app define one name, in one app. The
  # clash gems define clash_file in a second source, clash_lib in a
  # static library their extconf.rb links, and clash_variable in a
  # third: until the cure the app linked without a word and clash_b
  # answered clash_a's 1 100 10. The same gems define both names beside
  # Init: same_b answered its own function and same_a's variable, 4 30.
  # yamlish defines libyaml's yaml_get_version, which the runtime's
  # library holds too: it answered the runtime's, the version
  # runtime/sources.yml pins.
  # The libyaml the mobile runtimes are built from.
  LIBYAML = YAML.safe_load_file(File.expand_path("../../runtime/sources.yml", __dir__)).dig("mobile", "libyaml", "version")

  def test_ios_extensions_that_define_one_name_each_call_their_own
    ios_missing("Xcode builds an iOS app on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"
    app = app("LinkedSymbols", clash_gem("clash_a", 1), clash_gem("clash_b", 2), same_gem("same_a", 3), same_gem("same_b", 4), yaml_gem)
    runtimes = runtimes("ios")
    FileUtils.mkdir_p(File.join(@dir, "ios"))
    ios = MobileParity::IOS.new(runtimes:, work: File.join(@dir, "ios"), out: StringIO.new)
    project = MobileParity.projects("ios", runtimes:, out: File.join(@dir, "dist"), apps: [app]).fetch(app)
    bundle = ios.build_app(app, project)
    printed = everything = nil
    ios.on_simulator("iPhone", { app => bundle }) { |_, logged, _| printed, everything = said(logged), logged.entries }

    assert_equal ["clash_a 1 100 10", "clash_b 2 200 20", "same_a 3 30", "same_b 4 40", "yamlish 9.9.9, psych's libyaml #{LIBYAML}"], printed,
      "The app logged:\n#{Array(everything).last(40).join("\n")}"
  end

  # Two Rakefiles' extensions in libfledgeext.so whose names are in other
  # files and a library: until the cure rake_b answered rake_a's 5 500 50.
  def test_android_rakefile_extensions_whose_names_are_in_other_files_each_call_their_own
    printed = on_android(app("RakeApart", clash_gem("rake_a", 5, rake: true), clash_gem("rake_b", 6, rake: true)))

    assert_equal ["rake_a 5 500 50", "rake_b 6 600 60"], printed
  end

  # The same names beside Init: until the cure fledge build stopped with
  # lld's "duplicate symbol: same_function", which names no gem.
  def test_android_rakefile_extensions_whose_names_are_beside_init_each_call_their_own
    printed = on_android(app("RakeSame", same_gem("rakesame_a", 7, rake: true), same_gem("rakesame_b", 8, rake: true)))

    assert_equal ["rakesame_a 7 70", "rakesame_b 8 80"], printed
  end

  # A gem +name+ whose Clash module's values are clash_file, clash_lib,
  # and clash_variable, defined from +number+ in two more sources and a
  # static library; built by its extconf.rb, or by a Rakefile that runs
  # it, as digest-crc's does (+rake+).
  private def clash_gem(name, number, rake: false)
    calls = { "file" => "LONG2NUM(clash_file())", "lib" => "LONG2NUM(clash_lib())", "variable" => "LONG2NUM(clash_variable)" }
    gem(name, rake:, calls:, extra: 'File.open("Makefile", "a") { |makefile| makefile.puts "include $(srcdir)/lib.mk" }',
      declarations: "long clash_file(void);\nlong clash_lib(void);\nextern long clash_variable;\n", files: {
        "clash_file.c" => "long clash_file(void) { return #{number}; }\n",
        "clash_data.c" => "long clash_variable = #{number * 10};\n",
        "vendor/clash_lib.c" => "long clash_lib(void) { return #{number * 100}; }\n",
        "lib.mk" => LIB_MK,
      })
  end

  # A gem +name+ whose same_function and same_variable, from +number+,
  # are in Init's own source.
  private def same_gem(name, number, rake: false)
    gem(name, rake:, calls: { "function" => "LONG2NUM(same_function())", "variable" => "LONG2NUM(same_variable)" },
      declarations: "long same_function(void) { return #{number}; }\nlong same_variable = #{number * 10};\n")
  end

  # A gem whose extension defines libyaml's yaml_get_version, and whose
  # line also names the libyaml Psych reports.
  private def yaml_gem
    gem("yamlish", calls: { "version" => "version()" }, line: "\"yamlish \#{Yamlish.version}, psych's libyaml \#{Psych::LIBYAML_VERSION}\"",
      declarations: <<~C, files: { "yaml_version.c" => "void yaml_get_version(int *major, int *minor, int *patch) { *major = 9; *minor = 9; *patch = 9; }\n" })
        void yaml_get_version(int *major, int *minor, int *patch);
        static VALUE version(void) { int a, b, c; yaml_get_version(&a, &b, &c); return rb_sprintf("%d.%d.%d", a, b, c); }
      C
  end

  # A path gem +name+ in this test's folder: its extension's module
  # defines a function for each of +calls+ that returns the C expression
  # given, after +declarations+, beside +files+; and its lib file
  # requires it and says its line, the functions' values in order, or
  # +line+.
  private def gem(name, calls:, declarations:, files: {}, rake: false, extra: "", line: nil)
    module_name = name.split("_").map(&:capitalize).join
    folder = File.join(@dir, "gems", name)
    functions = calls.map { |function, value| "static VALUE #{function}_value(VALUE self) { return #{value}; }" }
    definitions = calls.keys.map { |function| "rb_define_module_function(module, \"#{function}\", #{function}_value, 0);" }
    files = files.merge("extconf.rb" => "require \"mkmf\"\ncreate_makefile(\"#{name}/#{name}\")\n#{extra}\n", "#{name}.c" => <<~C)
      #include <ruby.h>
      #{declarations}
      #{functions.join("\n")}
      void Init_#{name}(void) {
          VALUE module = rb_define_module("#{module_name}");
          #{definitions.join("\n    ")}
      }
    C
    files["Rakefile"] = "task :default do\n  ruby \"extconf.rb\"\n  sh \"make\"\nend\n" if rake
    files.each do |file, text|
      path = File.join(folder, "ext", name, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
    line ||= "\"#{name} #{calls.keys.map { |function| "\#{#{module_name}.#{function}}" }.join(' ')}\""
    FileUtils.mkdir_p(File.join(folder, "lib"))
    File.write(File.join(folder, "lib", "#{name}.rb"), "require \"#{name}/#{name}\"\nrequire \"psych\"\n\nmodule #{module_name}\n  def self.line\n    #{line}\n  end\nend\n")
    listed = ["lib/#{name}.rb", *files.keys.map { |file| "ext/#{name}/#{file}" }]
    File.write(File.join(folder, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "A gem that defines a name another gem defines"
        spec.files = #{listed.inspect}
        spec.extensions = [#{"ext/#{name}/#{rake ? 'Rakefile' : 'extconf.rb'}".inspect}]
      end
    RUBY
    [name, module_name]
  end

  # A developer's app +name+ of the path gems +gems+, locked for the
  # ruby platform, whose program prints each gem's line, as a
  # MobileParity::App.
  private def app(name, *gems)
    root = File.join(@dir, "apps", name)
    FileUtils.mkdir_p(root)
    gems.each { |gem, _| FileUtils.mv(File.join(@dir, "gems", gem), File.join(root, gem)) }
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n\n#{gems.map { |gem, _| "gem #{gem.inspect}, path: #{gem.inspect}\n" }.join}")
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      #{gems.map { |gem, _| "PATH\n  remote: #{gem}\n  specs:\n    #{gem} (1.0.0)\n" }.join("\n")}
      GEM
        remote: https://rubygems.org/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES
      #{gems.map { |gem, _| "  #{gem}!" }.join("\n")}

      CHECKSUMS
        bundler (4.0.20) sha256=7978a8ac648767f5e635bc522445b79e80a52b907a39a36c2d8085ed6bc762ae
      #{gems.map { |gem, _| "  #{gem} (1.0.0)" }.join("\n")}

      BUNDLED WITH
        4.0.20
    LOCK
    File.write(File.join(root, "fledge.yml"), "name: #{name}\nidentifier: com.setdef.fledge.#{name}\n")
    File.write(File.join(root, "main.rb"), "#{gems.map { |gem, _| "require #{gem.inspect}" }.join("\n")}\n" \
      "#{gems.map { |_, module_name| "puts #{module_name}.line" }.join("\n")}\n")
    MobileParity::App.new(path: root, name:, identifier: "com.setdef.fledge.#{name}", prints: /./)
  end

  # What +app+ printed on the attached Android device, built by fledge
  # build and Gradle's assembleDebug, as tasks/mobile_parity.rb builds
  # the examples.
  private def on_android(app)
    android_missing("no Android device or emulator: set ANDROID_SERIAL, as bin/android-emulator does") unless ENV["ANDROID_SERIAL"]
    project = MobileParity.projects("android", runtimes: runtimes("android"), out: File.join(@dir, "dist"), apps: [app]).fetch(app)
    log = File.join(@dir, "gradle.log")
    built = system(File.join(project, "gradlew"), "--no-daemon", "--project-dir", project, "assembleDebug", out: log, err: %i[child out])
    assert built, "Gradle built #{app.name}:\n#{MobileParity::Android.gradle_failure(File.read(log))}"
    apk = Dir.glob(File.join(project, "build", "outputs", "apk", "debug", "*-debug.apk")).first or flunk "Gradle built no debug APK"
    adb("install", "-r", apk)
    said(MobileParity::Android.new(work: File.join(@dir, "android"), out: StringIO.new).launch(app))
  ensure
    system("adb", "uninstall", app.identifier, out: File::NULL, err: File::NULL) if ENV["ANDROID_SERIAL"]
  end

  # The lines of what an app logged (MobileParity::Logged) that its gems
  # said, without the host's own.
  private def said(logged)
    logged.output.grep(/\A(?:clash|same|yamlish|rake)/)
  end

  # The folder of the runtimes, which holds +phone+'s, as rake runtime
  # writes them.
  private def runtimes(phone)
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    file = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(phone)))
    message = "no #{File.basename(file)} in #{dir}; run bundle exec rake runtime[#{phone}]"
    (phone == "ios") ? ios_missing(message) : android_missing(message) unless File.file?(file)
    dir
  end

  private def adb(*arguments)
    out, status = Open3.capture2e("adb", *arguments)
    assert_predicate status, :success?, "adb #{arguments.join(' ')}:\n#{out}"
    out
  end
end
