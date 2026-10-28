# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): the bundled program both mobile host apps run. It
# requires json, prints the line CI looks for, then probes what a Ruby
# script would notice on a phone (FINDINGS.md, question 4).
require "json"
puts "FLEDGE-SPIKE-OK #{JSON.generate({ruby: RUBY_VERSION, platform: RUBY_PLATFORM, json: JSON::VERSION})}"
$stdout.flush

def probe(name)
  value = yield
  puts "probe #{name} = #{value.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "probe #{name} ! #{e.class}: #{e.message.lines.first&.chomp}"
end

probe("RUBY_DESCRIPTION") { RUBY_DESCRIPTION }
probe("Gem::Platform.local") { Gem::Platform.local.to_s }
probe("$0") { $0 }
probe("__FILE__") { __FILE__ }
probe("__dir__") { __dir__ }
probe("Dir.pwd") { Dir.pwd }
probe("Dir.home") { Dir.home }
probe("ENV.size") { ENV.size }
probe("ENV.keys") { ENV.keys.sort }
probe("ENV[HOME]") { ENV["HOME"] }
probe("ENV[TMPDIR]") { ENV["TMPDIR"] }
probe("ENV[PATH]") { ENV["PATH"] }
probe("ENV[LANG]") { ENV["LANG"] }
probe("Encoding.default_external") { Encoding.default_external.to_s }
probe("$stdout.tty?") { $stdout.tty? }
probe("$stdin.read_nonblock") { $stdin.read_nonblock(1) }
probe("RbConfig prefix") { RbConfig::CONFIG["prefix"] }
probe("RbConfig.ruby exists") { [RbConfig.ruby, File.exist?(RbConfig.ruby)] }
probe("$LOAD_PATH") { $LOAD_PATH }
probe("Gem.dir") { Gem.dir }
probe("Gem::Specification.count") { Gem::Specification.count }
probe("read own file") { File.read(__FILE__).bytesize }
probe("list own dir") { Dir.children(__dir__).sort }
probe("write beside main.rb") { File.write(File.join(__dir__, "probe.txt"), "x") }
require "tmpdir"
probe("Dir.tmpdir") { Dir.tmpdir }
probe("write Dir.tmpdir") { File.write(File.join(Dir.tmpdir, "probe.txt"), "x") }
probe("write ~/Documents") { File.write(File.join(Dir.home, "Documents", "probe.txt"), "x") }
probe("write ~/Library/Caches") { File.write(File.join(Dir.home, "Library", "Caches", "probe.txt"), "x") }
probe("write Dir.home") { File.write(File.join(Dir.home, "probe.txt"), "x") }
probe("Etc.getlogin") { require "etc"; Etc.getlogin }
probe("Etc.getpwuid") { require "etc"; Etc.getpwuid.to_a.first(1) + [Etc.getpwuid.dir] }
probe("Etc.nprocessors") { require "etc"; Etc.nprocessors }
probe("Socket.gethostname") { require "socket"; Socket.gethostname }
probe("TCP to 1.1.1.1:443") { require "socket"; Socket.tcp("1.1.1.1", 443, connect_timeout: 3).close; :connected }
probe("Thread") { Thread.new { 21 * 2 }.value }
probe("Ractor") { Ractor.new { 7 }.value rescue Ractor.new { 7 }.take }
probe("Process.pid") { Process.pid }
probe("system(true)") { system("true") }
probe("backticks") { `echo hi` }
probe("Process.spawn") { Process.wait(Process.spawn("true")); $?.exitstatus }
probe("IO.popen") { IO.popen(["echo", "hi"], &:read) }
probe("Open3") { require "open3"; Open3.capture2("echo", "hi") }
probe("exec in thread") { :skipped }
probe("trap INT") { trap("INT") { } ; :ok }
probe("OpenSSL") { require "openssl"; [OpenSSL::OPENSSL_LIBRARY_VERSION, OpenSSL::X509::DEFAULT_CERT_FILE, File.exist?(OpenSSL::X509::DEFAULT_CERT_FILE)] }
probe("HTTPS HEAD www.ruby-lang.org") do
  require "net/http"
  Net::HTTP.start("www.ruby-lang.org", 443, use_ssl: true, open_timeout: 5, read_timeout: 5) { |http| http.head("/").code }
end
probe("String#crypt") { "secret".crypt("ab") }
probe("SecureRandom") { require "securerandom"; SecureRandom.hex(4).size }
probe("Psych/libyaml") { require "yaml"; [Psych::LIBYAML_VERSION, YAML.load("a: 1")] }
probe("Zlib") { require "zlib"; [Zlib::ZLIB_VERSION, Zlib.inflate(Zlib.deflate("abc"))] }
probe("BigDecimal") { require "bigdecimal"; (BigDecimal("0.1") + BigDecimal("0.2")).to_s }
probe("Gem.loaded_specs bigdecimal") { Gem.loaded_specs["bigdecimal"]&.version.to_s }
probe("CSV (bundled, pure Ruby)") { require "csv"; [CSV.parse_line("a,b"), Gem.loaded_specs["csv"]&.version.to_s] }
%w[nkf racc/cparse date ripper syslog io/console pty fiddle objspace coverage strscan stringio digest/sha2 etc fcntl
  monitor cgi/escape erb/escape readline reline irb rbs debug prism win32ole].each do |lib|
  probe("require #{lib}") { require lib }
end
probe("Time.now.zone") { Time.now.zone }
probe("Process.clock_gettime") { Process.clock_gettime(Process::CLOCK_MONOTONIC) > 0 }
probe("GC.stat heap") { GC.stat[:heap_allocated_pages] }
probe("RubyVM::YJIT") { defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : :undefined }
probe("at_exit runs") { at_exit { puts "FLEDGE-SPIKE-AT-EXIT" }; :registered }
puts "FLEDGE-SPIKE-DONE"
$stdout.flush
# Last, since forking a phone app's process (on Android, the whole ART
# runtime and its threads) is the probe most likely to hang.
probe("fork") { pid = fork { exit!(0) }; Process.wait(pid); $?.exitstatus }
