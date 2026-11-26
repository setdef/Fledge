# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Checks that opengl32.dll and glu32.dll are in this Windows computer's
# System32 and that the machine type each file declares in its PE header
# is ARM64 or ARM64X, read with the llvm-readobj this computer's runtime
# carries, as Fledge reads a gem's DLLs (Fledge::AppGems), and prints
# what it read. lib/fledge/linkage/windows.yml names both DLLs for
# ARM64 because a reading on Windows 11 for ARM64 found them so
# (tasks/windows_dlls.rb, ADDITIONS); this keeps that true if the
# runner's Windows changes. CI's Test (aarch64-mingw-ucrt, 1 of 2) job
# runs it, on windows-11-arm, with the runtime the job downloaded into
# FLEDGE_RUNTIME_DIR:
#
#   ruby .github/scripts/read-system-opengl.rb
#
# It exits 1 unless each DLL is present and ARM64 or ARM64X.
require "fileutils"
require "open3"
require "tmpdir"

# What the check holds of a reading of System32.
module SystemOpenGL
  # The DLLs Fledge lists for ARM64 beyond delvewheel's list.
  DLLS = %w[opengl32.dll glu32.dll].freeze

  # The machine types llvm-readobj prints for a file a native ARM64
  # process loads.
  MACHINES = %w[IMAGE_FILE_MACHINE_ARM64 IMAGE_FILE_MACHINE_ARM64X].freeze

  # The machine type in llvm-readobj's +output+ of --file-headers, such as
  # "IMAGE_FILE_MACHINE_ARM64X", or nil.
  def self.machine(output)
    output[/^\s*Machine:\s*(IMAGE_FILE_MACHINE_\w+)/, 1]
  end

  # Why a reading fails the check, one sentence for each DLL that does,
  # from +readings+: a hash of each DLL's name to the machine type of the
  # file in System32 (or to a sentence saying why none was read), with no
  # key for a DLL System32 lacks.
  def self.failures(readings)
    DLLS.filter_map do |name|
      if !readings.key?(name)
        "#{name} is not in System32"
      elsif !MACHINES.include?(readings.fetch(name))
        "#{name} declares #{readings.fetch(name).inspect}, not ARM64 or ARM64X"
      end
    end
  end

  # Prints the reading of System32 and exits 1 when #failures finds any.
  def self.run
    $LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
    require "fledge"
    system32 = File.join(ENV.fetch("SystemRoot", "C:\\Windows"), "System32")
    puts "Windows #{ENV.fetch('OS', '?')}, #{RUBY_PLATFORM}, reading #{system32}"
    problems = failures(read(system32))
    puts problems.empty? ? "Both DLLs are present, ARM64 or ARM64X." : problems.map { |problem| "FAIL: #{problem}" }
    exit(problems.empty? ? 0 : 1)
  end

  # Each DLL's machine type, by name, from System32 at +system32+, read
  # and printed; a name System32 lacks is not a key.
  def self.read(system32)
    readings = {}
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
        readings[name] = "llvm-readobj not in the runtime"
        next unless readobj

        out, status = Open3.capture2e(readobj, "--file-headers", path)
        if status.success?
          puts out.lines.grep(/\A\s*(?:Format|Arch|Machine):/).map { |line| "  #{line.strip}" }
          readings[name] = machine(out) || "no machine type"
        else
          puts "  llvm-readobj failed (#{status.exitstatus}): #{out.lines.first(3).join}"
          readings[name] = "llvm-readobj failed"
        end
      end
    rescue StandardError => e
      puts "The reading failed: #{e.class}: #{e.message}"
    ensure
      # Windows on ARM's x86-64 emulator may hold llvm-readobj.exe open for a
      # while after it exits; the system's temporary folder clears what stays.
      FileUtils.rm_rf(dir)
    end
    readings
  end
end

SystemOpenGL.run if $PROGRAM_NAME == __FILE__
