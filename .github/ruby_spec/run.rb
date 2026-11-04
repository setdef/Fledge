# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Experiment only (experiment/ruby-spec): runs ruby/spec on the Ruby a
# runtime was made from, as ruby main.rb, and in an app fledge build made
# from that runtime, in a clean environment and in Delivery's hostile one,
# and writes each run's output and wall time to OUT.
#
#   bundle exec ruby .github/ruby_spec/run.rb PLATFORM RUNTIMES SPEC MSPEC OUT [DIR...]
#
# SPEC and MSPEC are checkouts of ruby/spec and ruby/mspec at their pins.
require "fileutils"
require "json"
require "rbconfig"
require_relative "../../tasks/parity"

platform = Fledge::Platform.find(ARGV.fetch(0))
runtimes = File.expand_path(ARGV.fetch(1))
spec = File.expand_path(ARGV.fetch(2))
mspec = File.expand_path(ARGV.fetch(3))
out = File.expand_path(ARGV.fetch(4))
dirs = ARGV.drop(5)
dirs = %w[language core library command_line security] if dirs.empty?
windows = platform.windows?

work = File.join(out, "work")
FileUtils.rm_rf(work)
FileUtils.mkdir_p(work)

# The project: main.rb, with ruby/spec and MSpec as its data.
def project(into, spec, mspec)
  FileUtils.mkdir_p(into)
  FileUtils.cp(File.join(__dir__, "main.rb"), into)
  FileUtils.cp_r(spec, File.join(into, "spec"))
  FileUtils.cp_r(mspec, File.join(into, "mspec"))
  FileUtils.rm_rf(Dir[File.join(into, "{spec,mspec}", ".git{,hub}")] + [File.join(into, "mspec", "spec")])
  into
end

built_project = project(File.join(work, "build", "ruby_spec"), spec, mspec)
reference_project = project(File.join(work, "reference", "ruby_spec"), spec, mspec)

parity = Parity.new(platform:, work: File.join(work, "parity"), runtimes:)
FileUtils.mkdir_p(File.join(work, "parity"))
ruby = parity.send(:unpack_reference)
dist = File.join(work, "dist")
# In Alpine, as CI's musl jobs build apps, without a bundle.
build = ENV["RUBY_SPEC_NO_BUNDLE"] ? %w[ruby -I lib exe/fledge build] : %w[bundle exec fledge build]
system({ "FLEDGE_RUNTIME_DIR" => runtimes }, *build, "-o", dist, built_project,
  chdir: File.expand_path("../..", __dir__), exception: true)
app = File.join(dist, "RubySpec-#{platform}", platform.executable("RubySpec"))
raise "no app at #{app}" unless File.file?(app)

# A PATH with no Ruby on it.
def path_without_ruby(work, windows)
  if windows
    system = ENV.fetch("SystemRoot")
    return "#{system}\\System32;#{system};#{system}\\System32\\Wbem;#{system}\\System32\\WindowsPowerShell\\v1.0"
  end
  folder = File.join(work, "path")
  FileUtils.mkdir_p(folder)
  %w[/usr/local/bin /usr/bin /bin /usr/sbin /sbin].each do |dir|
    Dir.glob(File.join(dir, "*")).each do |file|
      name = File.basename(file)
      next if name.match?(/\A(?:ruby|gem|irb|erb|rake|rdoc|ri|bundle|bundler|rbs|typeprof|racc)[\d.]*\z/)

      target = File.join(folder, name)
      File.symlink(file, target) unless File.exist?(target) || File.symlink?(target)
    end
  end
  folder
end

path = path_without_ruby(work, windows)

def clean(work, label, path, windows)
  home = File.join(work, "home-#{label}")
  FileUtils.rm_rf(home)
  FileUtils.mkdir_p(home)
  # MSpec's temporary folder, short, since a UNIX socket's path may hold
  # no more than 104 bytes on macOS and 108 on Linux.
  specs = windows ? File.join(work, "t-#{label}") : "/tmp/rs-#{label}"
  FileUtils.rm_rf(specs)
  FileUtils.mkdir_p(specs)
  if windows
    temp = File.join(work, "temp-#{label}")
    FileUtils.mkdir_p(temp)
    { "SystemRoot" => ENV.fetch("SystemRoot"), "SystemDrive" => ENV.fetch("SystemDrive"), "windir" => ENV.fetch("SystemRoot"),
      "PATH" => path, "USERPROFILE" => home, "TEMP" => temp.tr("/", "\\"), "TMP" => temp.tr("/", "\\"), "SPEC_TEMP_DIR" => specs }
  else
    { "PATH" => path, "HOME" => home, "SPEC_TEMP_DIR" => specs }
  end
end

# Delivery's hostile environment (deliver.sh, deliver.ps1).
def hostile(work, path, windows)
  env = clean(work, "hostile", path, windows)
  home = windows ? env["USERPROFILE"] : env["HOME"]
  evil = File.join(work, "evil")
  FileUtils.mkdir_p(File.join(evil, "lib"))
  %w[json nonexistent bundler_setup].each { |file| File.write(File.join(evil, "#{file}.rb"), "raise \"leaked\"\n") }
  File.write(File.join(evil, "lib", "libcrypt.so.2"), "not a library\n")
  gems = File.join(home, ".gem", "ruby", "4.0.0")
  FileUtils.mkdir_p([File.join(gems, "gems", "json-99.0.0", "lib"), File.join(gems, "specifications")])
  FileUtils.cp(File.join(evil, "json.rb"), File.join(gems, "gems", "json-99.0.0", "lib", "json.rb"))
  File.write(File.join(gems, "specifications", "json-99.0.0.gemspec"),
    "Gem::Specification.new { |s| s.name = 'json'; s.version = '99.0.0'; s.summary = 'leak'; s.authors = ['leak']; " \
    "s.files = ['lib/json.rb'] }\n")
  FileUtils.mkdir_p(File.join(home, ".bundle"))
  File.write(File.join(home, ".bundle", "config"),
    "---\nBUNDLE_GEMFILE: \"#{evil}/Gemfile\"\nBUNDLE_PATH: \"#{evil}\"\nBUNDLE_FORCE_RUBY_PLATFORM: \"true\"\n" \
    "BUNDLE_WITHOUT: \"default\"\nBUNDLE_AUTO_INSTALL: \"true\"\n")
  env.merge(
    "RUBYLIB" => evil, "RUBYOPT" => "-rnonexistent", "RUBYSHELL" => windows ? File.join(evil, "sh.exe") : "/bin/false",
    "GEM_HOME" => gems, "GEM_PATH" => gems, "GEM_SPEC_CACHE" => evil, "GEMRC" => File.join(evil, "json.rb"),
    "BUNDLE_GEMFILE" => File.join(evil, "Gemfile"), "BUNDLE_PATH" => evil, "BUNDLER_SETUP" => File.join(evil, "bundler_setup.rb"),
    "BUNDLE_APP_CONFIG" => evil, "BUNDLE_FROZEN" => "false", "BUNDLE_WITHOUT" => "default", "BUNDLER_VERSION" => "2.1.0",
    "RUBYGEMS_GEMDEPS" => "-", "RUBY_YJIT_ENABLE" => "0",
    **(windows ? { "RUBY_DLL_PATH" => evil, "RI_FORCE_PATH_FOR_DLL" => "1" } : { "LD_LIBRARY_PATH" => File.join(evil, "lib") }),
  )
end

summary = []
run = lambda do |label, command, chdir, env|
  next if ENV["RUBY_SPEC_SKIP"].to_s.split(",").include?(label)

  folder = File.join(out, label)
  FileUtils.mkdir_p(folder)
  dirs.each do |dir|
    file = File.join(folder, "#{dir.tr('/', '_')}.out")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pid = Process.spawn(env, *command, "--timeout", "300", dir, chdir:, unsetenv_others: true,
      out: file, err: %i[child out], in: File::NULL)
    _, status = Process.wait2(pid)
    wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    totals = File.read(file, encoding: "binary").scan(/^\d+ files?, .*$/).last
    line = format("%-14s %-13s status=%-3s wall=%5.0fs %s", label, dir, status.exitstatus.inspect, wall, totals)
    puts line
    summary << line
  end
end

run.call("stock", [ruby, "main.rb"], reference_project, clean(work, "stock", path, windows))
run.call("app-clean", [app], work, clean(work, "app-clean", path, windows))
run.call("app-hostile", [app], work, hostile(work, path, windows))

File.write(File.join(out, "summary.txt"), "#{summary.join("\n")}\n")
step = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
File.write(step, "```\n#{summary.join("\n")}\n```\n", mode: "a") if step
FileUtils.rm_rf(work)
