# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Makes every file Binaries::CATALOG (test/support/binaries.rb) lists,
# with LLVM's own compiler and linker, which make ELF, Mach-O, and PE
# files on any computer: clang compiles a C file that refers to one
# symbol in each library the file is to need, and lld links it against a
# stub of each library, as a gem's extension is linked against the
# system's. The stubs are an empty shared object named for each ELF
# library (and for libc.so.6 one whose symbols carry the glibc versions
# asked for), a text stub (.tbd) for each Mach-O dylib, and an import
# library llvm-dlltool writes for each DLL.
#
#   ruby test/fixtures/binaries/build.rb [LLVM_BIN]
#
# LLVM_BIN, or FLEDGE_LLVM, is the bin folder of the llvm-mingw that
# runtime/sources.yml pins, which has clang, lld, and llvm-dlltool. The
# files are checked in; run this only to add one to the catalog.
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../../support/binaries"

# Makes one catalog entry's file.
class FixtureBuilder
  def initialize(llvm, work)
    @llvm = llvm
    @work = work
  end

  def build(spec)
    spec = Binaries.normalize(spec)
    output = File.join(Binaries::DIR, Binaries.name(spec))
    dir = File.join(@work, File.basename(output))
    FileUtils.mkdir_p(dir)
    __send__(spec.fetch(:format), spec, dir, output)
    puts "#{File.basename(output)}: #{spec}"
  end

  private def run(*command)
    output, status = Open3.capture2e(*command)
    raise "#{command.join(' ')} failed:\n#{output}" unless status.success?
  end

  private def tool(name)
    File.join(@llvm, name)
  end

  private def symbol(index)
    "fledge_fixture_#{index}"
  end

  # A C file whose one function calls +count+ functions, one from each
  # library, declared as +declaration+ makes them.
  private def source(dir, count, declaration = "extern void %s(void);")
    path = File.join(dir, "fixture.c")
    names = Array.new(count) { |index| symbol(index) }
    File.write(path, "#{names.map { |name| format(declaration, name) }.join("\n")}\nvoid fledge_fixture(void) { #{names.map { |name| "#{name}();" }.join(' ')} }\n")
    path
  end

  private def elf(spec, dir, output)
    needed = spec.fetch(:needed)
    versions = spec.fetch(:versions)
    calls = needed.size + versions.size
    object = File.join(dir, "fixture.o")
    run(tool("clang"), "--target=x86_64-linux-gnu", "-fPIC", "-c", source(dir, calls), "-o", object)
    stubs = needed.each_with_index.map do |library, index|
      exported = [symbol(index)]
      exported += versions.each_index.map { |offset| symbol(needed.size + offset) } if library == "libc.so.6"
      elf_stub(dir, library, exported, (library == "libc.so.6") ? versions : [])
    end
    run(tool("ld.lld"), "-shared", "--no-as-needed", "--hash-style=gnu", object, *stubs, "-o", output)
  end

  # A shared object named +library+ that defines +symbols+, the last of
  # them each at one of +versions+.
  private def elf_stub(dir, library, symbols, versions)
    stub = File.join(dir, "stub-#{library}")
    FileUtils.mkdir_p(stub)
    code = File.join(stub, "stub.c")
    File.write(code, symbols.map { |name| "void #{name}(void) {}\n" }.join)
    object = File.join(stub, "stub.o")
    run(tool("clang"), "--target=x86_64-linux-gnu", "-fPIC", "-c", code, "-o", object)
    arguments = ["-shared", "-soname", library, object, "-o", File.join(stub, library)]
    unless versions.empty?
      script = File.join(stub, "versions.map")
      versioned = symbols.last(versions.size)
      nodes = versions.zip(versioned).map { |version, name| [version, [name]] }
      nodes.first.last.concat(symbols - versioned)
      File.write(script, nodes.map { |version, names| "#{version} { global: #{names.join('; ')}; };\n" }.join)
      arguments += ["--version-script", script]
    end
    run(tool("ld.lld"), *arguments)
    File.join(stub, library)
  end

  private def macho(spec, dir, output)
    needed = spec.fetch(:needed)
    object = File.join(dir, "fixture.o")
    target = (spec.fetch(:platform) == "ios") ? "arm64-apple-ios#{spec.fetch(:minos)}" : "arm64-apple-macos#{spec.fetch(:minos)}"
    run(tool("clang"), "--target=#{target}", "-c", source(dir, needed.size), "-o", object)
    stubs = needed.each_with_index.map { |library, index| tbd(dir, library, index, spec.fetch(:platform)) }
    run(tool("lld"), "-flavor", "darwin", "-arch", "arm64", "-bundle", "-platform_version", spec.fetch(:platform), spec.fetch(:minos),
      spec.fetch(:minos), object, *stubs, "-o", output)
  end

  # A text stub of the dylib whose install name is +library+, exporting
  # the +index+th symbol, as Apple's SDKs describe their libraries.
  private def tbd(dir, library, index, platform)
    path = File.join(dir, "stub-#{index}.tbd")
    File.write(path, "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-#{platform} ]\ninstall-name: '#{library}'\n" \
      "exports:\n  - targets: [ arm64-#{platform} ]\n    symbols: [ _#{symbol(index)} ]\n...\n")
    path
  end

  private def pe(spec, dir, output)
    libraries = spec.fetch(:needed) + spec.fetch(:delayed)
    object = File.join(dir, "fixture.o")
    helper = spec.fetch(:delayed).empty? ? "" : "void *__delayLoadHelper2(void *a, void *b) { return 0; }\n"
    entry = spec.fetch(:program) ? "int fledge_entry(void) { return 0; }\n" : ""
    code = source(dir, libraries.size, "__declspec(dllimport) void %s(void);")
    File.write(code, File.read(code) + helper + entry)
    run(tool("clang"), "--target=x86_64-pc-windows-msvc", "-c", code, "-o", object)
    imports = libraries.each_with_index.map do |library, index|
      definition = File.join(dir, "import-#{index}.def")
      File.write(definition, "LIBRARY #{library}\nEXPORTS\n#{symbol(index)}\n")
      run(tool("llvm-dlltool"), "-m", "i386:x86-64", "-d", definition, "-l", File.join(dir, "import-#{index}.lib"))
      File.join(dir, "import-#{index}.lib")
    end
    kind = spec.fetch(:program) ? ["/subsystem:#{spec.fetch(:program)}", "/entry:fledge_entry"] : ["/dll", "/noentry"]
    run(tool("lld"), "-flavor", "link", *kind, "/machine:x64", "/nodefaultlib", "/Brepro", "/export:fledge_fixture", "/implib:#{File.join(dir, 'fixture.lib')}", object, *imports,
      *spec.fetch(:delayed).map { |library| "/delayload:#{library}" }, "/out:#{output}")
  end
end

llvm = ARGV[0] || ENV.fetch("FLEDGE_LLVM") { abort "usage: ruby test/fixtures/binaries/build.rb LLVM_BIN (or set FLEDGE_LLVM)" }
Dir.mktmpdir("fixtures") do |work|
  builder = FixtureBuilder.new(llvm, work)
  Binaries::CATALOG.each { |spec| builder.build(spec) }
end
