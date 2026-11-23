# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Prints whether opengl32.dll and glu32.dll are in this Windows computer's
# System32 and the machine type each file declares in its PE header, read
# with the llvm-readobj this computer's runtime carries, as Fledge
# reads a gem's DLLs (Fledge::AppGems). It is a reading for issue 8:
# lib/fledge/linkage/windows.yml names both DLLs for x64 and neither for
# ARM64, and whether Windows 11 on ARM64 has them is a fact no computer
# available before a push could show. CI's Test (aarch64-mingw-ucrt, 1
# of 2) job runs it, on windows-11-arm, with the runtime the job
# downloaded into FLEDGE_RUNTIME_DIR:
#
#   ruby .github/scripts/read-system-opengl.rb
#
# It always exits 0: the answer, either way, is the point, and a job
# must not fail on it.
require "fileutils"
require "open3"
require "tmpdir"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "fledge"

DLLS = %w[opengl32.dll glu32.dll].freeze

system32 = File.join(ENV.fetch("SystemRoot", "C:\\Windows"), "System32")
puts "Windows #{ENV.fetch('OS', '?')}, #{RUBY_PLATFORM}, reading #{system32}"

dir = Dir.mktmpdir("fledge-readobj")
begin
  archive = Fledge::Runtimes.new.archive(Fledge::Platform.local)
  readobj = Fledge::RuntimeContents.read(archive).tool(Fledge::AppGems::READOBJ, into: dir)
  puts "#{Fledge::AppGems::READOBJ}: #{readobj || 'not in the runtime'}"

  DLLS.each do |name|
    path = File.join(system32, name)
    unless File.file?(path)
      puts "#{path}: MISSING"
      next
    end

    puts "#{path}: PRESENT, #{File.size(path)} bytes"
    next unless readobj

    out, status = Open3.capture2e(readobj, "--file-headers", path)
    puts status.success? ? out.lines.grep(/\A\s*(?:Format|Arch|Machine):/).map { |line| "  #{line.strip}" } : "  llvm-readobj failed (#{status.exitstatus}): #{out.lines.first(3).join}"
  end
rescue StandardError => e
  puts "The reading failed: #{e.class}: #{e.message}"
ensure
  # Windows on ARM's x86-64 emulator may hold llvm-readobj.exe open for a
  # while after it exits; the system's temporary folder clears what stays.
  FileUtils.rm_rf(dir)
end
