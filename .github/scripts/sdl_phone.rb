# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The SDL3 spike's check (ADR 025), for the experiment/sdl-phones
# branch: examples/sdl_phone built with fledge build, its project given
# SDL's host by host/apply.rb, built, run in the iOS Simulator or on an
# Android emulator, touched once, and its log read back.
#
#   ruby .github/scripts/sdl_phone.rb ios RUNTIMES SDL3 OUT
#   ruby .github/scripts/sdl_phone.rb android-build RUNTIMES SDL3 OUT
#   ruby .github/scripts/sdl_phone.rb android OUT
require "fileutils"
require "json"
require "open3"

ROOT = File.expand_path("../..", __dir__)
EXAMPLE = File.join(ROOT, "examples", "sdl_phone")
ID = "com.setdef.fledge.SdlPhone"
TIMEOUT = 240

def run!(*command, **options)
  puts "+ #{command.join(' ')}"
  system(*command, exception: true, **options)
end

def capture!(*command)
  out, status = Open3.capture2(*command)
  raise "#{command.join(' ')} failed:\n#{out}" unless status.success?

  out
end

# The project fledge build writes for +phone+, with the SDL3 builds in +sdl3+.
def project(phone, runtimes, sdl3, out)
  env = { "FLEDGE_RUNTIME_DIR" => runtimes, "BUNDLE_BUILD__SDL_DEMO" => "--with-sdl3-builds=#{sdl3}" }
  printed, status = Open3.capture2(env, RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "fledge"), "build", phone,
    "-o", out, EXAMPLE, chdir: ROOT)
  raise "fledge build #{phone} failed" unless status.success?

  File.expand_path(printed.strip, ROOT)
end

# Fails unless +lines+ show the game ran on +where+, drew, took a touch,
# and ended with status 0; prints the evidence.
def check(lines, device)
  wanted = {
    "thread" => /\ASdlDemo runs Ruby on /, "frames" => /\ASdlDemo drew \d+ frames\z/, "touch" => /\ASdlDemo touch down at /,
    "end" => /\ASdlDemo drew \d+ frames in all, after a touch\z/, "status" => / exited with status 0\z/
  }
  found = wanted.transform_values { |pattern| lines.find { |line| line.match?(pattern) } }
  missing = found.select { |_, line| line.nil? }.keys
  raise "#{device}: no #{missing.join(', ')} line in:\n#{lines.last(60).join("\n")}" unless missing.empty?

  found.each_value { |line| puts "#{device}: #{line}" }
  File.write(ENV.fetch("GITHUB_STEP_SUMMARY", File::NULL), "#{device}\n```\n#{found.values.join("\n")}\n```\n", mode: "a")
end

def ios(runtimes, sdl3, out)
  project = project("ios", runtimes, sdl3, out)
  run!(RbConfig.ruby, File.join(EXAMPLE, "host", "apply.rb"), "ios", project, "--tap")
  xcodeproj = File.join(project, "SdlPhone.xcodeproj")
  device = File.join(out, "derived-device")
  run!("xcodebuild", "-project", xcodeproj, "-scheme", "SdlPhone", "-configuration", "Release", "-sdk", "iphoneos",
    "-derivedDataPath", device, "build", "CODE_SIGNING_ALLOWED=NO", out: File.join(out, "xcodebuild-device.log"), err: [:child, :out])
  executable = File.join(device, "Build", "Products", "Release-iphoneos", "SdlPhone.app", "SdlPhone")
  puts "Built for devices, unsigned: #{capture!('xcrun', 'vtool', '-show-build', executable).lines.grep(/platform|minos/).map(&:strip).join(', ')}; " \
    "main thread stack #{capture!('xcrun', 'otool', '-l', executable)[/stacksize (\d+)/, 1]} bytes"
  %w[iPhone iPad].each { |family| on_simulator(family, xcodeproj, out) }
end

def newest(family)
  runtime = JSON.parse(capture!("xcrun", "simctl", "list", "runtimes", "-j")).fetch("runtimes")
    .select { |candidate| candidate["platform"] == "iOS" && candidate["isAvailable"] }.max_by { |candidate| Gem::Version.new(candidate["version"]) }
  # A current model: the first of the family Xcode set up a simulator of
  # for the runtime, as tasks/mobile_parity/ios.rb chooses.
  set_up = JSON.parse(capture!("xcrun", "simctl", "list", "devices", "available", "-j")).fetch("devices")
    .fetch(runtime.fetch("identifier"), []).map { |device| device.fetch("deviceTypeIdentifier") }
  types = runtime.fetch("supportedDeviceTypes").select { |candidate| candidate["productFamily"] == family }
  type = types.find { |candidate| set_up.include?(candidate.fetch("identifier")) } || types.last
  [runtime.fetch("identifier"), type.fetch("identifier"), "#{type.fetch('name')}, iOS #{runtime.fetch('version')}"]
end

def on_simulator(family, xcodeproj, out)
  runtime, type, name = newest(family)
  udid = capture!("xcrun", "simctl", "create", "sdl-#{family}", type, runtime).strip
  run!("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL)
  since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
  log = File.join(out, "xcodebuild-test-#{family}.log")
  test = Process.spawn("xcodebuild", "-project", xcodeproj, "-scheme", "SdlPhone", "-destination", "platform=iOS Simulator,id=#{udid}",
    "-derivedDataPath", File.join(out, "derived-sim"), "test", "CODE_SIGNING_ALLOWED=NO", out: log, err: [:child, :out])
  shot = false
  until Process.wait(test, Process::WNOHANG)
    if !shot && messages(udid, since).any? { |line| line.include?("drew 300 frames") }
      shot = system("xcrun", "simctl", "io", udid, "screenshot", File.join(out, "screenshot-#{family}.png"), out: File::NULL, err: File::NULL)
    end
    sleep 1
  end
  raise "xcodebuild test failed on #{name}:\n#{File.readlines(log).last(40).join}" unless $?.success?

  check(messages(udid, since), "iOS Simulator, #{name}")
ensure
  system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL) if udid
end

def messages(udid, since)
  out, = Open3.capture2("xcrun", "simctl", "spawn", udid, "log", "show", "--start", since, "--style", "ndjson", "--info",
    "--predicate", "subsystem == \"#{ID}\"")
  out.lines.filter_map do |line|
    entry = JSON.parse(line)
    entry["eventMessage"] if entry.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end
end

def android_build(runtimes, sdl3, out)
  project = project("android", runtimes, sdl3, out)
  run!(RbConfig.ruby, File.join(EXAMPLE, "host", "apply.rb"), "android", project, sdl3)
  run!(File.join(project, "gradlew"), "--no-daemon", "--quiet", "--project-dir", project, "assembleDebug", "assembleRelease")
  tools = Dir.glob(File.join(ENV.fetch("ANDROID_HOME"), "build-tools", "*")).max_by { |path| Gem::Version.new(File.basename(path)) }
  apks = Dir.glob(File.join(project, "build", "outputs", "apk", "{debug,release}", "*.apk"))
  apks.each do |apk|
    run!(File.join(tools, "zipalign"), "-c", "-P", "16", "4", apk)
    puts "#{File.basename(apk)}: #{capture!('unzip', '-l', apk).lines.grep(%r{lib/}).map { |line| line.split.last }.join(', ')}"
  end
  readelf = File.join(Dir.glob(File.join(ENV.fetch("ANDROID_NDK_ROOT"), "toolchains", "llvm", "prebuilt", "*", "bin")).first, "llvm-readelf")
  Dir.glob(File.join(project, "src", "main", "jniLibs", "*", "*.so")).each do |library|
    needed = capture!(readelf, "-d", library).scan(/\(NEEDED\).*\[(.+)\]/).flatten
    puts "#{library.delete_prefix("#{project}/")}: NEEDED #{needed.join(', ')}"
  end
  FileUtils.cp(apks.grep(/debug/).first, File.join(out, "SdlPhone-debug.apk"))
end

def adb(*arguments)
  capture!("adb", *arguments)
end

def logged
  adb("logcat", "-d", "-v", "raw", "-s", "#{ID}:V").lines.map(&:chomp).reject { |line| line.start_with?("--------- ") }
end

def android(out)
  abi = adb("shell", "getprop", "ro.product.cpu.abi").strip
  device = "Android #{abi} API #{adb('shell', 'getprop', 'ro.build.version.sdk').strip}, #{adb('shell', 'getconf', 'PAGE_SIZE').strip}-byte pages"
  adb("logcat", "-G", "16M")
  adb("install", "-r", File.join(out, "SdlPhone-debug.apk"))
  width, height = adb("shell", "wm", "size")[/(\d+)x(\d+)/].split("x").map(&:to_i)
  [[], ["--ez", "fledge.sdlthread", "true"]].each_with_index do |extra, index|
    adb("logcat", "-c")
    adb("shell", "am", "start", "-W", "-n", "#{ID}/org.setdef.fledge.host.MainActivity", *extra)
    wait { logged.any? { |line| line.include?("drew 300 frames") } }
    system("adb", "exec-out", "screencap", "-p", out: File.join(out, "screenshot-android-#{index}.png"))
    adb("shell", "input", "tap", (width * 0.33).round.to_s, (height * 0.33).round.to_s)
    wait { logged.any? { |line| line.match?(/ exited with status/) } }
    check(logged, "#{device}#{extra.empty? ? '' : ', Ruby on SDLThread'}")
    adb("shell", "am", "force-stop", ID)
  end
rescue RuntimeError
  File.write(File.join(out, "logcat.txt"), adb("logcat", "-d", "-v", "threadtime"))
  raise
end

def wait
  deadline = Time.now + TIMEOUT
  until yield
    raise "timed out:\n#{logged.last(40).join("\n")}" if Time.now > deadline

    sleep 2
  end
end

command, *arguments = ARGV
FileUtils.mkdir_p(arguments.last.to_s)
case command
when "ios" then ios(*arguments.first(2).map { |path| File.expand_path(path) }, File.expand_path(arguments.fetch(2)))
when "android-build" then android_build(*arguments.first(2).map { |path| File.expand_path(path) }, File.expand_path(arguments.fetch(2)))
when "android" then android(File.expand_path(arguments.fetch(0)))
else abort "usage: sdl_phone.rb ios|android-build RUNTIMES SDL3 OUT | android OUT"
end
