# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Spike (experiment/path-probe only): what Ruby's own answers to "where
# am I" are inside a built app, and whether an app can restart itself
# the way a Rubyist would, with exec RbConfig.ruby, $0, *ARGV.
#
#   main.rb OUT MODE GEN
#
# appends one JSON line of facts to OUT, then, while GEN is below 2,
# restarts itself with GEN + 1: MODE ruby execs RbConfig.ruby with $0
# and the arguments; MODE launcher execs the program the process is
# running (the launcher, found as a spike can: /proc/self/exe, ps, or
# Get-Process) with the arguments; MODE scrubbed execs RbConfig.ruby with
# the Ruby variables taken out of its environment; MODE none never
# restarts.

require "rbconfig"
require "json"

out, mode, gen = ARGV
gen = Integer(gen || "0")
mode ||= "none"

def safe
  yield
rescue Exception => e # rubocop:disable Lint/RescueException
  "#{e.class}: #{e.message}"[0, 300]
end

def path_fact(value)
  return value unless value.is_a?(String) && !value.empty?

  { "value" => value, "absolute" => File.absolute_path?(value), "exists" => File.exist?(value),
    "encoding" => value.encoding.name }
end

def executable_of_this_process
  if File.exist?("/proc/self/exe")
    File.readlink("/proc/self/exe")
  elsif RbConfig::CONFIG["host_os"].include?("darwin")
    IO.popen({ "LC_ALL" => "en_US.UTF-8" }, ["/bin/ps", "-o", "comm=", "-p", Process.pid.to_s], &:read)
      .force_encoding(Encoding::UTF_8).strip
  elsif Gem.win_platform?
    command = "[Console]::OutputEncoding = [Text.Encoding]::UTF8; (Get-Process -Id #{Process.pid}).Path"
    IO.popen(["powershell", "-NoProfile", "-NonInteractive", "-Command", command], &:read)
      .force_encoding(Encoding::UTF_8).strip
  end
end

# JSON needs valid UTF-8; a path read in a C locale is US-ASCII or
# binary, which is itself a finding, kept in "encoding".
def jsonable(value)
  case value
  when Hash then value.to_h { |k, v| [jsonable(k), jsonable(v)] }
  when Array then value.map { |v| jsonable(v) }
  when String
    utf8 = value.dup.force_encoding(Encoding::UTF_8)
    utf8.valid_encoding? ? utf8 : utf8.scrub
  else value
  end
end

def cocoa
  require "fiddle"
  objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
  Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
  ptr = Fiddle::TYPE_VOIDP
  klass = Fiddle::Function.new(objc["objc_getClass"], [ptr], ptr)
  sel = Fiddle::Function.new(objc["sel_registerName"], [ptr], ptr)
  send0 = Fiddle::Function.new(objc["objc_msgSend"], [ptr, ptr], ptr)
  send_long = Fiddle::Function.new(objc["objc_msgSend"], [ptr, ptr, Fiddle::TYPE_LONG], Fiddle::TYPE_CHAR)
  text = lambda do |object|
    object.null? ? nil : send0.call(object, sel.call("UTF8String")).to_s.force_encoding(Encoding::UTF_8)
  end
  bundle = send0.call(klass.call("NSBundle"), sel.call("mainBundle"))
  facts = {
    "mainBundle.bundlePath" => text.call(send0.call(bundle, sel.call("bundlePath"))),
    "mainBundle.bundleIdentifier" => text.call(send0.call(bundle, sel.call("bundleIdentifier")))
  }
  app = send0.call(klass.call("NSApplication"), sel.call("sharedApplication"))
  facts["setActivationPolicy(regular)"] = send_long.call(app, sel.call("setActivationPolicy:"), 0)
  current = send0.call(klass.call("NSRunningApplication"), sel.call("currentApplication"))
  facts["NSRunningApplication.bundleIdentifier"] = text.call(send0.call(current, sel.call("bundleIdentifier")))
  facts["NSRunningApplication.localizedName"] = text.call(send0.call(current, sel.call("localizedName")))
  url = send0.call(current, sel.call("bundleURL"))
  facts["NSRunningApplication.bundleURL"] = url.null? ? nil : text.call(send0.call(url, sel.call("path")))
  facts
end

def windows_console
  require "fiddle"
  kernel32 = Fiddle.dlopen("kernel32")
  get_console = Fiddle::Function.new(kernel32["GetConsoleWindow"], [], Fiddle::TYPE_VOIDP)
  { "GetConsoleWindow" => get_console.call.to_i != 0 }
end

facts = {
  "gen" => gen,
  "mode" => mode,
  "pid" => Process.pid,
  "ppid" => Process.ppid,
  "executable" => path_fact(safe { executable_of_this_process }),
  "__FILE__" => path_fact(__FILE__),
  "__dir__" => path_fact(__dir__),
  "$0" => path_fact($0),
  "$PROGRAM_NAME" => path_fact($PROGRAM_NAME),
  "Process.argv0" => path_fact(Process.respond_to?(:argv0) ? Process.argv0 : "(undefined)"),
  "ARGV" => ARGV,
  "RbConfig.ruby" => path_fact(RbConfig.ruby),
  "Gem.ruby" => path_fact(safe { Gem.ruby }),
  "prefix" => path_fact(RbConfig::CONFIG["prefix"]),
  "bindir" => path_fact(RbConfig::CONFIG["bindir"]),
  "libdir" => path_fact(RbConfig::CONFIG["libdir"]),
  "rubylibdir" => path_fact(RbConfig::CONFIG["rubylibdir"]),
  "archdir" => path_fact(RbConfig::CONFIG["archdir"]),
  "ruby_install_name" => RbConfig::CONFIG["ruby_install_name"],
  "RUBY_INSTALL_NAME" => RbConfig::CONFIG["RUBY_INSTALL_NAME"],
  "Gem.dir" => path_fact(Gem.dir),
  "Gem.path" => Gem.path.map { |p| path_fact(p) },
  "Gem.default_dir" => path_fact(Gem.default_dir),
  "Gem.bindir" => path_fact(Gem.bindir),
  "Gem.user_dir" => safe { Gem.user_dir },
  "Dir.pwd" => path_fact(Dir.pwd),
  "PATH" => ENV.fetch("PATH", nil),
  "env" => ENV.to_h.select { |k, _| k.match?(/\A(RUBY|GEM|BUNDLE|DYLD_|LD_LIBRARY_PATH\z|LD_PRELOAD|LANG\z|LC_|FLEDGE|APPIMAGE|APPDIR|ARGV0|__CF|XPC_SERVICE)/i) },
  "config_paths_outside_prefix" => RbConfig::CONFIG.select do |k, v|
    v.is_a?(String) && v.match?(%r{(\A|[\s=:;])(/|[A-Za-z]:[/\\])}) && !v.include?(RbConfig::CONFIG["prefix"]) &&
      v.match?(%r{runner|/opt/|/usr/local|hostedtoolcache|D:[/\\]a|/tmp/|/build|/home/|/Users/|rubyinstaller|msys64}i)
  end.transform_values { |v| v[0, 160] },
  "require json" => safe { require "json" },
  "require i18n" => safe { require "i18n" },
  "require csv (bundled gem)" => safe { require "csv" },
  "Bundler" => defined?(Bundler) ? true : false,
  "bundler/setup loaded" => $LOADED_FEATURES.any? { |f| f.end_with?("bundler/setup.rb") },
  "Bundler.original_env (RUBYOPT, GEM_HOME, BUNDLE_GEMFILE)" =>
    defined?(Bundler) ? Bundler.original_env.slice("RUBYOPT", "GEM_HOME", "BUNDLE_GEMFILE") : nil,
  "Gem.loaded_specs" => Gem.loaded_specs.keys.sort,
  "$LOAD_PATH (first 3)" => $LOAD_PATH.first(3),
  "RUBY_PLATFORM" => RUBY_PLATFORM,
  "Encoding.default_external" => Encoding.default_external.name,
  "locale_charmap" => Encoding.locale_charmap,
  "__FILE__.valid_encoding?" => __FILE__.valid_encoding?
}
facts["cocoa"] = safe { cocoa } if RbConfig::CONFIG["host_os"].include?("darwin") && File.exist?(File.join(__dir__, "windowed.marker"))
facts["windows console"] = safe { windows_console } if Gem.win_platform?
if RbConfig::CONFIG["host_os"].include?("darwin")
  facts["lsappinfo"] = safe { `/usr/bin/lsappinfo info -only bundleid,bundlepath,executablepath,name #{Process.pid}`.strip }
end

File.open(out, "a:UTF-8") { |file| file.puts(JSON.generate(jsonable(facts))) }

exit 0 if mode == "none" || gen >= 2

following = [out, mode, (gen + 1).to_s]
begin
  case mode
  when "ruby"
    exec(RbConfig.ruby, $0, *following)
  when "scrubbed"
    cleared = ENV.keys.grep(/\A(RUBY|GEM_|GEMRC|BUNDLE_|BUNDLER_)/i).to_h { |k| [k, nil] }
    exec(cleared, RbConfig.ruby, $0, *following)
  when "launcher"
    launcher = facts.dig("executable", "value")
    exec(launcher, *following)
  end
rescue SystemCallError => e
  File.open(out, "a:UTF-8") { |file| file.puts(JSON.generate(jsonable({ "gen" => gen, "exec failed" => "#{e.class}: #{e.message}" }))) }
  exit 1
end
