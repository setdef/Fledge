<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a RubyGems bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://github.com/ruby/rubygems/issues/new, with the title below, and everything after the line as the body (GitHub takes Markdown).

Before filing: search RubyGems' issues and pull requests for "YAMLSerializer encoding", "limit_read", and "ASCII-8BIT executables", since the parser is new in 4.1 and someone may have reported it already (the tracker was not searched: agents here cannot reach it); and read the body start to finish as your own words. Found when `fledge build` failed on Windows for a gem whose executable is named `日本`, and for any gem with executables when the temporary folder was under an account named `Jürgen 日本`. The reproduction below ran on macOS with Ruby 4.1.0-preview1 (RubyGems 4.1.0.beta2) and Ruby 4.0.x (RubyGems 4.0.20); the suggested fix has not been run.

- **Title:** 4.1: a packed gem's specification has BINARY strings, so installing an executable named outside ASCII into a folder named outside ASCII raises Encoding::CompatibilityError

---

Since 4.1, `Gem::Package#spec` gives every string of a `.gem`'s specification (`name`, `file_name`, `executables`, `files`) as ASCII-8BIT, where 4.0 gave UTF-8. Installing a gem whose executable is named outside ASCII into a `GEM_HOME` whose path is outside ASCII then fails in `Gem::Installer#generate_bin`, on every platform. On Windows the BINARY names do more harm, since `File.expand_path` of a BINARY string reads the current folder in code page 1252 (`win32/file.c`, `code_page`), so a gem's `file_name` expanded under `C:\Users\Jürgen 日本` names `J\xFCrgen ??` and cannot be opened.

## Reproduction

```ruby
require "rubygems/package"
require "rubygems/installer"
require "fileutils"
require "tmpdir"

Dir.mktmpdir do |tmp|
  src = File.join(tmp, "src")
  FileUtils.mkdir_p(File.join(src, "exe"))
  File.write(File.join(src, "exe", "日本"), "puts 1\n")
  spec = Gem::Specification.new do |s|
    s.name = "nihon"; s.version = "1.0"; s.summary = "x"; s.authors = ["x"]
    s.files = ["exe/日本"]; s.bindir = "exe"; s.executables = ["日本"]
  end
  gem = Dir.chdir(src) { File.join(src, Gem::Package.build(spec, true)) }
  packed = Gem::Package.new(gem).spec
  p rubygems: Gem::VERSION, name: packed.name.encoding, executables: packed.executables.map(&:encoding)
  home = File.join(tmp, "Jürgen")
  Gem::Installer.at(gem, install_dir: home, bin_dir: File.join(home, "bin"), document: [], wrappers: true).install
  puts "installed"
end
```

With RubyGems 4.0.20:

```
{rubygems: "4.0.20", name: #<Encoding:UTF-8>, executables: [#<Encoding:UTF-8>]}
installed
```

With RubyGems 4.1.0.beta2 (and the Windows RubyInstaller head build's 4.1.0.beta3 gives the same BINARY names):

```
{rubygems: "4.1.0.beta2", name: #<Encoding:BINARY (ASCII-8BIT)>, executables: [#<Encoding:BINARY (ASCII-8BIT)>]}
rubygems/installer.rb:490:in 'File.join': incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT) (Encoding::CompatibilityError)
```

With `RUBYGEMS_USE_PSYCH=true`, 4.1.0.beta2 gives UTF-8 and installs.

## Cause

`Gem::Package#load_spec_from_metadata` opens `metadata.gz` with `Zlib::GzipReader.wrap(entry, external_encoding: Encoding::UTF_8)`, but reads it through `#limit_read`, which calls `io.read(limit + 1)`; `IO#read` with a length returns ASCII-8BIT whatever the stream's external encoding. Psych, which 4.0 used, gave UTF-8 strings for that input; `Gem::YAMLSerializer`, which `Gem::SafeYAML.safe_load` uses since 4.1 unless `Gem.use_psych?` (`DEFAULT_USE_PSYCH = false` in `config_file.rb`), keeps the input's encoding. The code is the same on ruby/ruby's master as of 2026-11-21.

## Suggested fix

Label the metadata with the encoding the reader was opened with, in `limit_read` or in `load_spec_from_metadata`:

```ruby
def limit_read(io, name, limit)
  bytes = io.read(limit + 1)
  raise Gem::Package::FormatError, "#{name} is too big (over #{limit} bytes)" if bytes.size > limit
  bytes.force_encoding(io.external_encoding) if io.respond_to?(:external_encoding) && io.external_encoding
  bytes
end
```

`safe_load` already falls back to its own parser for metadata that is not valid UTF-8, so legacy metadata keeps loading.
