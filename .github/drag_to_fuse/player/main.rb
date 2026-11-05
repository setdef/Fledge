# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Experiment only (experiment/drag-to-fuse), never for trunk: a "player"
# built with fledge build, as a Lota player would be, that does two
# things, as LÖVE's executable does.
#
# With a game inside it (app/game/main.rb), it runs that game: fused
# mode. Otherwise, given a game folder or a .zip of one as its first
# argument, which is how Windows hands a program the paths dropped on
# it, it writes a fused copy of itself beside the game: itself copied,
# the game copied into app/game, renamed, its identity rewritten, and on
# macOS sealed again with codesign. It uses only Ruby's standard library
# and the operating system's own tools (tar.exe on Windows, ditto,
# plutil, and codesign on macOS), with no Ruby, compiler, network, or
# Bundler from the computer. It rewrites fledge.cfg, which only Fledge
# may do (ADR 029, section 3); that is what the experiment shows Fledge
# must own. Every step reports to a JSON log, since a windowed program
# has no console on Windows.

require "fileutils"
require "json"
require "tmpdir"

GAME = File.join(__dir__, "game")
PLAYER = "FusePlayer"
LOG = File.join(Gem.win_platform? ? Dir.tmpdir : "/tmp", "fuse_player.json")

def log(facts)
  File.write(LOG, "#{JSON.generate(facts)}\n")
end

def run!(*command)
  system(*command, exception: true)
end

if File.file?(File.join(GAME, "main.rb"))
  load File.join(GAME, "main.rb")
  exit
end

source = ARGV.first
unless source
  log("mode" => "idle", "argv" => ARGV, "dir" => __dir__)
  exit
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
source = File.expand_path(source)
staging = Dir.mktmpdir("fuse")
game =
  if File.directory?(source)
    source
  else
    unpacked = File.join(staging, "game")
    FileUtils.mkdir_p(unpacked)
    if Gem.win_platform?
      run!(File.join(ENV.fetch("SystemRoot"), "System32", "tar.exe"), "-xf", source, "-C", unpacked)
    else
      run!("/usr/bin/ditto", "-x", "-k", source, unpacked)
    end
    unpacked
  end

# What Lota would read from conf.rb (t.identity, t.window.title); the
# experiment reads two string assignments, and derives the identifier.
conf = File.read(File.join(game, "conf.rb"))
identity = conf[/t\.identity\s*=\s*"([^"]+)"/, 1] or abort "conf.rb sets no t.identity"
title = conf[/t\.window\.title\s*=\s*"([^"]+)"/, 1] || identity
name = title.gsub(/[^A-Za-z0-9 _-]/, "")
identifier = "org.lota.game.#{identity.gsub(/[^A-Za-z0-9-]/, "-")}"
out = File.join(File.dirname(source), "fused")
FileUtils.mkdir_p(out)

def rewrite_identifier(config, identifier)
  text = File.read(config)
  text = text.sub(/^identifier = .*$/, "identifier = #{identifier}")
  File.write(config, text)
end

if Gem.win_platform?
  player = File.dirname(__dir__)
  fused = File.join(out, "#{name}-x64-mingw-ucrt")
  FileUtils.rm_rf(fused)
  FileUtils.cp_r(player, fused)
  FileUtils.cp_r(game, File.join(fused, "app", "game"))
  File.rename(File.join(fused, "#{PLAYER}.exe"), File.join(fused, "#{name}.exe"))
  rewrite_identifier(File.join(fused, "fledge.cfg"), identifier)
else
  player = File.expand_path("../../..", __dir__)
  abort "#{player} is not an app bundle" unless player.end_with?(".app")
  fused = File.join(out, "#{name}.app")
  FileUtils.rm_rf(fused)
  FileUtils.cp_r(player, fused)
  resources = File.join(fused, "Contents", "Resources")
  FileUtils.cp_r(game, File.join(resources, "app", "game"))
  macos = File.join(fused, "Contents", "MacOS")
  File.rename(File.join(macos, PLAYER), File.join(macos, name))
  plist = File.join(fused, "Contents", "Info.plist")
  { "CFBundleExecutable" => name, "CFBundleName" => name, "CFBundleDisplayName" => name, "CFBundleIdentifier" => identifier }.each do |key, value|
    run!("/usr/bin/plutil", "-replace", key, "-string", value, plist)
  end
  rewrite_identifier(File.join(resources, "fledge.cfg"), identifier)
  run!("/usr/bin/codesign", "--force", "--sign", "-", "--identifier", identifier, fused)
end

log(
  "mode" => "fuse",
  "argv" => ARGV,
  "source" => source,
  "fused" => fused,
  "identifier" => identifier,
  "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
)
