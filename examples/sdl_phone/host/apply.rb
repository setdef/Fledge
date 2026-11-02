# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# Turns the project fledge build ios or fledge build android wrote into
# one whose host is SDL3's (ADR 025), as a framework that owns the main
# loop would after each build:
#
#   ruby host/apply.rb ios PROJECT [--tap]
#   ruby host/apply.rb android PROJECT SDL3_BUILDS
#
# On iOS it puts host/ios/main.m in place of the project's, names SDL's
# scene delegate in Info.plist, asks for a 64 MB stack for the main
# thread, where Ruby runs, and has XcodeGen write the project again.
# --tap adds the UI test the Mobile apps job taps the screen with. On
# Android it puts host/android/MainActivity.java in place of the
# project's, an SDLActivity, and adds SDL's Java classes from the folder
# sdl3/build.sh wrote. fledge build has already put libSDL3.so beside
# libfledgeext.so, since the gem's extension links it.
require "fileutils"
require "yaml"

# The folder of SDL's host files, this file's own.
HOST = __dir__

# The main thread's stack, as -Wl,-stack_size takes it: 64 MB, the stack
# Fledge's hosts give Ruby's thread.
STACK_SIZE = "0x4000000"

# The iOS project at +project+, changed as the comment above says.
def ios(project, tap:)
  FileUtils.cp(File.join(HOST, "ios", "main.m"), File.join(project, "Host", "main.m"))
  plist = File.join(project, "Host", "Info.plist")
  File.write(plist, File.read(plist).sub("<string>SceneDelegate</string>", "<string>SDLUIKitSceneDelegate</string>"))
  spec = File.join(project, "project.yml")
  yml = YAML.load_file(spec)
  name, target = yml.fetch("targets").first
  settings = target.fetch("settings").fetch("base")
  settings["OTHER_LDFLAGS"] = "#{settings.fetch('OTHER_LDFLAGS')} -Wl,-stack_size,#{STACK_SIZE}"
  # The Debug configuration's debug dylib holds the app's code, and ld
  # takes -stack_size only for the main executable.
  settings["ENABLE_DEBUG_DYLIB"] = "NO"
  add_tap_test(project, yml, name) if tap
  File.write(spec, YAML.dump(yml))
  system("xcodegen", "generate", "--quiet", "--spec", spec, "--project", project, exception: true)
end

# Adds a UI test target, which taps the screen once the game draws, and
# runs it from the app's scheme.
def add_tap_test(project, yml, name)
  FileUtils.cp_r(File.join(HOST, "ios", "UITests"), project)
  yml.fetch("targets")["#{name}UITests"] = {
    "type" => "bundle.ui-testing",
    "platform" => "iOS",
    "sources" => [{ "path" => "UITests" }],
    "dependencies" => [{ "target" => name }],
    "settings" => {
"base" => {
"GENERATE_INFOPLIST_FILE" => "YES",
"TEST_TARGET_NAME" => name,
"PRODUCT_BUNDLE_IDENTIFIER" => "com.setdef.fledge.#{name}UITests",
"CLANG_ENABLE_MODULES" => "YES",
},
},
  }
  yml.fetch("targets").fetch(name)["scheme"] = { "testTargets" => ["#{name}UITests"] }
end

# The Android project at +project+, changed as the comment above says,
# with SDL's Java from +builds+.
def android(project, builds)
  java = File.join(project, "src", "main", "java")
  FileUtils.cp(File.join(HOST, "android", "MainActivity.java"), File.join(java, "org", "setdef", "fledge", "host", "MainActivity.java"))
  FileUtils.mkdir_p(File.join(java, "org", "libsdl"))
  FileUtils.cp_r(File.join(builds, "java", "org", "libsdl", "app"), File.join(java, "org", "libsdl"))
end

system_name, project, *rest = ARGV
case system_name
when "ios" then ios(File.expand_path(project.to_s), tap: rest.include?("--tap"))
when "android" then android(File.expand_path(project.to_s), File.expand_path(rest.fetch(0)))
else abort "usage: ruby host/apply.rb ios PROJECT [--tap] | android PROJECT SDL3_BUILDS"
end
