# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The parity probe: an app that reports what Ruby looks like from
# inside it.
#
# An app's Ruby code should run under Fledge exactly as it runs under
# ruby main.rb (ADR 003). tasks/parity.rb builds this app with fledge
# build, runs it, runs the same file with the Ruby the runtime came from
# as ruby main.rb, and compares the two reports.
#
# With no command, it prints one line, "FLEDGE-PARITY " followed by a
# JSON object of facts: the globals an app sees, what is loaded and
# loadable, RubyGems' paths, the encodings, the environment, and what a
# child Ruby sees. Under Bundler (bundle exec, or a built app with a
# Gemfile) it also reports the environment Bundler recorded as the one it
# started from, and what a child Ruby sees inside
# Bundler.with_original_env and Bundler.with_unbundled_env, which is how
# a Bundler app starts a person's own tools. Paths are raw; the
# comparison normalizes them. The arguments it was given are among the
# facts.
#
# Delivery, which has no Ruby to compare with, asks it one thing at a
# time instead:
#
#   parity child-env NAME   prints ENV[NAME] as a child Ruby started
#                           through RbConfig.ruby sees it, or (unset)
#   parity original-child-env NAME
#   parity unbundled-child-env NAME
#                           the same, for a child Ruby started inside
#                           Bundler.with_original_env or
#                           Bundler.with_unbundled_env, or (no Bundler)
#   parity gem-path         prints Gem.path, one folder per line
#   parity irb              opens IRB with binding.irb, with a local
#                           variable, answer, of 42 in scope
#   parity restart          restarts itself as a Ruby program does, with
#                           exec RbConfig.ruby, $0, and prints what the
#                           restarted probe found different from the
#                           first start, a line each, or "restarted as
#                           itself" (ADR 026)
#
# It uses nothing but Ruby's standard library, so it runs under any Ruby
# 4.0.

require "json"
require "rbconfig"

# What a child Ruby, started as an app would start one, prints for
# +code+.
def child_ruby(code)
  IO.popen([RbConfig.ruby, "-e", code], err: File::NULL, &:read)
rescue SystemCallError => e
  "#{e.class}: #{e.message}"
end

# What a child Ruby prints for +code+ when Bundler's +method+
# (with_original_env or with_unbundled_env) starts it, or nil without
# Bundler.
def bundler_child_ruby(method, code)
  Bundler.public_send(method) { child_ruby(code) } if defined?(Bundler)
end

# The child's ENV as a Hash, through +start+, a method that runs code in
# a child Ruby, or nil when it ran none, or what went wrong when no child
# could start, as on a phone, where an app starts no programs.
def child_env(start, *)
  output = method(start).call(*, "require 'json'; print JSON.generate(ENV.to_h)")
  output && JSON.parse(output)
rescue JSON::ParserError
  output
end

# The features each gem's own files provide, so a gem named io-console
# is required as io/console and english as English.
def feature_of(spec)
  features = spec.files.filter_map { |file| file.sub(%r{\A(?:lib|ext/[^/]+)/}, "")[/\A(.+)\.(?:rb|so|bundle)\z/, 1] }
  candidates = [spec.name, spec.name.tr("-", "/")]
  candidates.each do |candidate|
    found = features.find { |feature| feature.casecmp?(candidate) }
    return found if found
  end
  candidates.last
end

# Gems whose require does more than load code: debug starts a debugger
# session, and test/unit runs every test case at exit. For these, the
# probe only checks that RubyGems can find the file.
RESOLVE_ONLY = %w[debug test-unit].freeze

# A gem that exits while it loads (prism 2.1 does, when the parser gem it
# translates for is missing) raises SystemExit, which is no StandardError:
# the probe reports it as it reports a LoadError and keeps going. A gem
# loads when its require leaves it active, as RubyGems activates it; a
# require that loads something else of the same name, as a linked
# extension found before the gem, is "loads, but not its gem".
def requireable(spec)
  feature = feature_of(spec)
  if RESOLVE_ONLY.include?(spec.name)
    return (Gem.find_files(feature).empty? && !$LOAD_PATH.resolve_feature_path(feature)) ? "missing" : "found"
  end

  require feature
  Gem.loaded_specs.key?(spec.name) ? "loads" : "loads, but not its gem"
rescue LoadError, StandardError, SystemExit => e
  "#{e.class}: #{e.message.lines.first.to_s.chomp}"
end

# The root of the project the probe runs in: Bundler's, when Bundler set
# it up (bundle exec, or a built gem-shaped app), and the probe's own
# folder otherwise.
def project_root
  (defined?(Bundler) && Bundler.respond_to?(:root)) ? Bundler.root.to_s : __dir__
end

# The program this process runs, as the operating system knows it, by
# its real path: the launcher, or bin/ruby. Windows and phones are not
# asked.
def running_program
  return File.realpath("/proc/self/exe") if File.exist?("/proc/self/exe")
  return unless RUBY_PLATFORM.include?("darwin")

  File.realpath(IO.popen({ "LC_ALL" => "en_US.UTF-8" }, ["/bin/ps", "-o", "comm=", "-p", Process.pid.to_s], &:read).strip)
end

# The identifier of the bundle macOS takes this process to be part of
# (NSBundle.mainBundle), which an .app's Info.plist names, or nil. Fiddle
# is a bundled gem that a Gemfile's bundle leaves out, so under Bundler
# it is not asked.
def main_bundle
  return unless RUBY_PLATFORM.include?("darwin") && !defined?(Bundler)

  require "fiddle"
  objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
  Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
  pointer = Fiddle::TYPE_VOIDP
  find_class = Fiddle::Function.new(objc["objc_getClass"], [pointer], pointer)
  selector = Fiddle::Function.new(objc["sel_registerName"], [pointer], pointer)
  message = Fiddle::Function.new(objc["objc_msgSend"], [pointer, pointer], pointer)
  bundle = message.call(find_class.call("NSBundle"), selector.call("mainBundle"))
  identifier = message.call(bundle, selector.call("bundleIdentifier"))
  identifier.null? ? nil : message.call(identifier, selector.call("UTF8String")).to_s
end

# Whether this is Windows, where Fiddle asks Windows itself what Ruby
# does not say: the process's program, its ANSI code page, and its
# AppUserModelID, and how a DLL loads by a narrow path.
def windows?
  RUBY_PLATFORM.match?(/mingw|mswin/)
end

# A function of kernel32.dll, through Fiddle.
def kernel32(name, arguments, result)
  Fiddle::Function.new(Fiddle.dlopen("kernel32.dll")[name], arguments, result)
end

# The process's ANSI code page (GetACP), which its program's manifest
# decides (ADR 070).
def code_page
  require "fiddle"
  kernel32("GetACP", [], Fiddle::TYPE_INT).call
end

# Whether the DLL at +path+ loads as the ffi gem loads a gem's DLL, with
# LoadLibraryExA, which reads the path in the ANSI code page
# (ext/ffi_c/DynamicLibrary.c, lines 215 to 225, at ffi 1.17.4):
# "loaded", or "no DLL".
def narrow_load(path)
  require "fiddle"
  pointer = Fiddle::TYPE_VOIDP
  # LOAD_WITH_ALTERED_SEARCH_PATH, as ffi passes for a full path.
  kernel32("LoadLibraryExA", [pointer, pointer, Fiddle::TYPE_INT], pointer).call(path, nil, 8).null? ? "no DLL" : "loaded"
end

# code_page and narrow_load as code for a child Ruby, which prints what
# they return.
CHILD_CODE_PAGE = 'require "fiddle"; print Fiddle::Function.new(Fiddle.dlopen("kernel32.dll")["GetACP"], [], Fiddle::TYPE_INT).call'

# The child finds the DLL in +folder+, whose name is ASCII, by itself:
# Ruby reads -e code in the console's code page, so a name outside ASCII
# written into the code would not survive under code page 437.
def child_narrow_load(folder)
  child_ruby(<<~RUBY)
    require "fiddle"
    load = Fiddle::Function.new(Fiddle.dlopen("kernel32.dll")["LoadLibraryExA"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
    print load.call(Dir.glob(File.join(#{folder.inspect}, "*", "*.dll")).fetch(0), nil, 8).null? ? "no DLL" : "loaded"
  RUBY
end

# A DLL of Ruby's, which RubyInstaller's tree and a runtime both hold.
def rubys_dll
  File.join(RbConfig::CONFIG["bindir"], "ruby_builtin_dlls", "libwinpthread-1.dll")
end

# The UTF-16 string of +length+ characters at +pointer+, as UTF-8.
def wide_string(pointer, length)
  pointer.to_s(length * 2).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
end

# The AppUserModelID Windows groups the process's windows under, which
# the launcher sets from the app's identifier (ADR 064), or nil.
def app_user_model_id
  pointer = Fiddle::TYPE_VOIDP
  out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
  get = Fiddle::Function.new(Fiddle.dlopen("shell32.dll")["GetCurrentProcessExplicitAppUserModelID"], [pointer], Fiddle::TYPE_INT)
  return unless get.call(out).zero?

  wide_string(out.ptr, kernel32("lstrlenW", [pointer], Fiddle::TYPE_INT).call(out.ptr))
end

# What Windows says of this process, or nil off Windows and under
# Bundler, which leaves Fiddle out, as main_bundle says: the program it
# runs, its ANSI code page, its AppUserModelID, and whether a DLL of
# Ruby's, under the app's folder, loads through a narrow path.
def windows_process
  return unless windows? && !defined?(Bundler)

  require "fiddle"
  path = Fiddle::Pointer.malloc(65_536)
  length = kernel32("GetModuleFileNameW", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT).call(nil, path, 32_768)
  {
    "program" => wide_string(path, length),
    "code page" => code_page,
    "AppUserModelID" => app_user_model_id,
    "narrow DLL load" => narrow_load(rubys_dll),
  }
end

# What a child Ruby started through RbConfig.ruby finds of its own
# process, beside what this one finds, on Windows outside Bundler, or
# nil: the ANSI code page, which a child takes from its own program's
# manifest (ADR 070), and whether a DLL under a folder named outside
# ASCII loads through a narrow path.
def windows_child
  return unless windows? && !defined?(Bundler)

  require "fileutils"
  require "tmpdir"
  Dir.mktmpdir do |dir|
    dll = File.join(dir, "Ünïcödé 日本", File.basename(rubys_dll))
    FileUtils.mkdir_p(File.dirname(dll))
    FileUtils.cp(rubys_dll, dll)
    {
      "code page" => code_page,
      "child's code page is its parent's" => child_ruby(CHILD_CODE_PAGE) == code_page.to_s,
      "narrow DLL load" => narrow_load(dll),
      "child's narrow DLL load is its parent's" => child_narrow_load(dir) == narrow_load(dll),
    }
  end
end

# +value+ with every string as valid UTF-8, for JSON: a path read in a C
# locale is US-ASCII with bytes outside it, which is itself what a
# restart compares, in "encoding".
def utf8(value)
  case value
  when Hash then value.to_h { |key, item| [utf8(key), utf8(item)] }
  when Array then value.map { |item| utf8(item) }
  when String then value.dup.force_encoding(Encoding::UTF_8).scrub
  else value
  end
end

# What a restart keeps: the process, the program it runs, where the app
# and Ruby are, the locale, the gems, and the environment, and on
# Windows what Windows says of the process. Windows has no exec that
# keeps the process: Ruby's own starts the program, waits for it, and
# exits with its status (win32/win32.c, child_result), so there a
# restart is a new process, under ruby.exe as in an app, and its PID is
# not asked.
def restart_facts
  utf8(
    "pid" => windows? ? nil : Process.pid,
    "program" => running_program,
    "main bundle" => main_bundle,
    "Windows" => windows_process,
    "$0" => $0,
    "__FILE__" => __FILE__,
    "__dir__" => __dir__,
    "encoding" => [Encoding.default_external.name, __FILE__.encoding.name],
    "RbConfig.ruby" => RbConfig.ruby,
    "Gem.path" => Gem.path,
    "Gem.loaded_specs" => Gem.loaded_specs.keys.sort,
    "Bundler.original_env" => defined?(Bundler) ? Bundler.original_env : nil,
    "ENV" => ENV.to_h,
  )
end

def facts
  {
    "paths" => { "app" => __dir__, "project" => project_root, "prefix" => RbConfig::TOPDIR, "home" => Dir.home },
    "$0" => $0,
    "__FILE__" => __FILE__,
    "__dir__" => __dir__,
    "$PROGRAM_NAME" => $PROGRAM_NAME,
    "ARGV" => ARGV,
    "$LOAD_PATH" => $LOAD_PATH.map(&:to_s),
    "$LOADED_FEATURES" => $LOADED_FEATURES.sort,
    "RbConfig.ruby" => RbConfig.ruby,
    "RbConfig.ruby is a program" => File.file?(RbConfig.ruby) && File.executable?(RbConfig.ruby),
    "RbConfig.ruby runs" => child_ruby("print 6 * 7"),
    "Gem.ruby" => Gem.ruby,
    "Gem.path" => Gem.path,
    "Gem.dir" => Gem.dir,
    "gems" => Gem::Specification.map { |spec| "#{spec.name} #{spec.version}#{' (default)' if spec.default_gem?}" }.sort,
    "Encoding.default_external" => Encoding.default_external.name,
    "Encoding.default_internal" => Encoding.default_internal&.name,
    "Encoding.find('locale')" => Encoding.find("locale").name,
    "Encoding.find('filesystem')" => Encoding.find("filesystem").name,
    "$stdout.sync" => $stdout.sync,
    "$stderr.sync" => $stderr.sync,
    "$stdin.sync" => $stdin.sync,
    "$stdout.external_encoding" => $stdout.external_encoding&.name,
    "$VERBOSE" => $VERBOSE,
    "$DEBUG" => $DEBUG,
    "ENV" => ENV.to_h,
    "child ENV" => child_env(:child_ruby),
    "Bundler.original_env" => defined?(Bundler) ? Bundler.original_env : nil,
    "Bundler.unbundled_env" => defined?(Bundler) ? Bundler.unbundled_env : nil,
    "original child ENV" => child_env(:bundler_child_ruby, :with_original_env),
    "unbundled child ENV" => child_env(:bundler_child_ruby, :with_unbundled_env),
    "RUBY_PLATFORM" => RUBY_PLATFORM,
    "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
    "RubyVM::YJIT.enabled?" => defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : nil,
    # Last but requireable, since it requires fiddle.
    "Windows" => windows_child,
  }
end

case ARGV.first
when "child-env"
  puts child_ruby("print ENV.fetch(#{ARGV.fetch(1).inspect}, '(unset)')")
when "original-child-env", "unbundled-child-env"
  method = (ARGV.first == "original-child-env") ? :with_original_env : :with_unbundled_env
  puts bundler_child_ruby(method, "print ENV.fetch(#{ARGV.fetch(1).inspect}, '(unset)')") || "(no Bundler)"
when "gem-path"
  puts Gem.path
when "irb"
  answer = 6 * 7
  binding.irb # rubocop:disable Lint/Debugger
when "restart"
  exec(RbConfig.ruby, $0, "restarted", JSON.generate(restart_facts))
when "restarted"
  before = JSON.parse(ARGV.fetch(1))
  after = JSON.parse(JSON.generate(restart_facts))
  changed = before.keys.reject { |key| before[key] == after[key] }
  puts(changed.empty? ? "restarted as itself" : changed.map { |key| "#{key}: #{before[key].inspect} became #{after[key].inspect}" })
else
  report = facts
  # Last, since requiring changes $LOADED_FEATURES.
  report["requireable"] = Gem::Specification.to_h { |spec| [spec.name, requireable(spec)] }.sort.to_h
  # In a C locale, ARGV and paths outside ASCII are US-ASCII strings with
  # bytes outside it, which JSON refuses; the encodings are among the
  # facts.
  puts "FLEDGE-PARITY #{JSON.generate(utf8(report))}"
end
