# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPIKE: reports what the embedded Ruby sees, for FINDINGS.md. The first
# argument picks a mode: exit3, raise, unicode, or (default) report.
case ARGV.first
when "exit3" then exit 3
when "raise" then raise "boom from main.rb"
when "unicode"
  $stdout.binmode
  $stdout.write("caf\u00e9 \u2713\n")
  exit
end

require "rbconfig" # not loaded by --disable-gems

def report(label, value) = puts("#{label}: #{value.inspect}")

report "RUBY_PLATFORM", RUBY_PLATFORM
report "RUBY_DESCRIPTION", RUBY_DESCRIPTION
report "Gem::Platform.local", (defined?(Gem) ? Gem::Platform.local.to_s : "(no rubygems)")
report "RbConfig::TOPDIR", RbConfig::TOPDIR
report "rubyarchdir", RbConfig::CONFIG["rubyarchdir"]
report "LIBRUBY_SO", RbConfig::CONFIG["LIBRUBY_SO"]
report "$0", $PROGRAM_NAME
report "__dir__", __dir__
report "ARGV", ARGV
report "ARGV encodings", ARGV.map(&:encoding)
report "$LOAD_PATH", $LOAD_PATH
report "default_external", Encoding.default_external
report "default_internal", Encoding.default_internal
report "locale_charmap", Encoding.locale_charmap
report "filesystem", Encoding.find("filesystem")
%w[RUBYLIB RUBYOPT GEM_HOME GEM_PATH BUNDLE_GEMFILE BUNDLE_PATH RUBY_DLL_PATH HOME].each do |name|
  report "ENV[#{name}]", ENV.fetch(name, nil)
end
report "Gem.default_dir", (defined?(Gem) ? Gem.default_dir : nil)
report "Gem.path", (defined?(Gem) ? Gem.path : nil)
report "RubyInstaller::Runtime", defined?(RubyInstaller::Runtime)
if defined?(RubyInstaller::Runtime)
  report "msys2 mingwdir", RubyInstaller::Runtime.msys2_installation.mingwdir&.path
end

%w[json openssl psych zlib fiddle socket date digest etc ripper bigdecimal].each do |lib|
  require lib
  report "require #{lib}", "ok"
rescue LoadError, StandardError => e
  report "require #{lib}", "#{e.class}: #{e.message}"
end
report "OpenSSL", OpenSSL::OPENSSL_LIBRARY_VERSION if defined?(OpenSSL)
report "Psych libyaml", Psych::LIBYAML_VERSION if defined?(Psych)
report "Zlib", Zlib.zlib_version if defined?(Zlib)

# The DLLs this process has loaded, from outside (Ruby has no API for it).
ps = File.join(ENV.fetch("SystemRoot", "C:/Windows"), "System32/WindowsPowerShell/v1.0/powershell.exe")
modules = IO.popen([
  ps,
  "-NoProfile",
  "-Command",
  "(Get-Process -Id #{Process.pid}).Modules | ForEach-Object FileName",
], &:read)
modules.to_s.lines.map(&:strip).reject { |m| m.match?(/\\Windows\\/i) }.each { |m| report "module", m }
