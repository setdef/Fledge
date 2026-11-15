<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Bundler pull request, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, as a pull request to https://github.com/ruby/rubygems: fork it, make a branch from `master` (the change was made on c6c69d31d4, 2026-11-13), apply the patch below with `git apply`, commit it with a message that names no issue or person (`doc/PULL_REQUESTS.md` asks for no `#123` or `@name` in commits), push the branch to the fork, and open the pull request with the title below and everything after the line as its description, which follows the repository's pull request template. Its label would be "bundler: bug fix", which only a maintainer can set.

The repository's `CONTRIBUTING.md` asks that a bug fix come with a test that reproduces the bug, and `doc/PULL_REQUESTS.md` that RuboCop pass and that at least the unit specs and the specs of the area changed are run if the whole suite is not; it says nothing about AI-assisted contributions either way, and #9973, merged, was one. A new spec file must also be listed in `spec/support/shards.rb`, or `bin/rspec` refuses it; the patch adds it to `shard_d`, as that file asks. What ran here, on stock Ruby 4.1.0-preview1 on macOS: the new spec file and the four spec files of the code changed (104 examples, no failures); each of the seven changes reverted alone, which fails exactly one example of the new file; and `bin/rake rubocop` on the whole repository (no offenses). The whole suite (`bin/parallel_rspec`) was not run. Before filing: run it, or let the pull request's CI run it; search the issues and pull requests for "clean_load_path", "invalid byte sequence in US-ASCII", "incompatible character encodings", "setup_manpath", and "ruby_shebang", since someone may have reported it after 2026-11-14 (on that day nothing matched; #139, closed in 2011, was RubyGems with no locale, and #8196, #9968, and #9973, merged, fixed other places where a path outside ASCII or an ASCII locale broke RubyGems and Bundler); and read the description start to finish as your own words, since you are the one filing it.

Found when Fledge, which runs Ruby with no locale, set up the gems of an app whose Ruby sits in a folder named outside ASCII (`doc/contributors/research/2026-11-13-c-locale.md`). Fledge sidesteps it by giving Ruby a UTF-8 locale (`doc/contributors/design/launcher.md`, "The locale"), so nothing in Fledge changes when this is merged; it is for anyone who runs `bundle` or `bundler/setup` that way with stock Ruby. Bundler's vendored Thor fails too; that fix is Thor's ([thor-c-locale-paths.md](thor-c-locale-paths.md)), and the commands below run only with both.

- **Title:** Compare and join paths as bytes, so Bundler runs under the C locale from a folder whose name is not ASCII

---

## What was the end-user or developer problem that led to this PR?

With no locale at all (as cron, launchd, a systemd unit, `env -i`, or a minimal container gives a process) or with `LANG=C`, Ruby's encoding for paths is US-ASCII. A path whose name is not ASCII then reaches Bundler in three encodings, depending on where Ruby made it: BINARY (`ENV`, `Dir.pwd`, the default `$LOAD_PATH`), US-ASCII with bytes that are not valid in it (`__dir__`, `-I` and `RUBYLIB` entries, the features Ruby loads before encodings exist), and UTF-8 (paths built from `RbConfig` and from string literals). Comparing, joining, or matching two of them raises. That happens to anyone whose Ruby is installed under such a folder, such as a user named José whose Ruby lives in `~/.rubies`, `~/.rbenv`, or a version manager's folder in his home, as soon as Bundler runs without a locale.

### Steps to reproduce

ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-darwin23], rv-ruby's relocatable build of it (release 20261023, `arm64_sonoma`), unpacked to `.../josé/.rubies/ruby-4.1.0-preview1`, with its default Bundler, 4.1.0.beta2. An app beside it, in `.../josé/app`, whose Gemfile holds `gem "rake"`, locked and installed with a UTF-8 locale. Then, in the app, with no locale:

```
$ env -i PATH=".../josé/.rubies/ruby-4.1.0-preview1/bin:/usr/bin:/bin" HOME=".../josé" ruby -e 'require "bundler/setup"'
.../josé/.rubies/ruby-4.1.0-preview1/lib/ruby/4.1.0+5/bundler/shared_helpers.rb:391:in 'String#start_with?': incompatible character encodings: US-ASCII and BINARY (ASCII-8BIT) (Encoding::CompatibilityError)
	from .../bundler/shared_helpers.rb:391:in 'block (2 levels) in Bundler::SharedHelpers#clean_load_path'
	from .../bundler/shared_helpers.rb:391:in 'Array#any?'
	from .../bundler/shared_helpers.rb:391:in 'block in Bundler::SharedHelpers#clean_load_path'
	from .../bundler/shared_helpers.rb:389:in 'Array#reject!'
	from .../bundler/shared_helpers.rb:389:in 'Bundler::SharedHelpers#clean_load_path'
	from .../bundler/runtime.rb:18:in 'Bundler::Runtime#setup'
	from .../bundler.rb:164:in 'Bundler.setup'
```

```
$ env -i ... bundle exec ruby main.rb
.../bundler/friendly_errors.rb:98:in 'Array#join': incompatible character encodings: UTF-8 and US-ASCII (Encoding::CompatibilityError)
	from .../bundler/friendly_errors.rb:98:in 'Bundler::FriendlyErrors.serialized_exception_for'
	from .../bundler/friendly_errors.rb:88:in 'Bundler::FriendlyErrors.exception_message'
	from .../bundler/friendly_errors.rb:68:in 'Bundler::FriendlyErrors.request_issue_report_for'
```

`bundle -v` and `bundle exec rake --version` fail the same way. That second failure hides the first: Bundler's report of an unexpected error raises while it joins a backtrace whose lines are in different encodings. Each fix below exposes the next failure, so these are the places, in the order they are met (line numbers at master c6c69d31d4; the same lines in 4.1.0.beta2, but `runtime.rb`, line 352):

1. `Bundler::SharedHelpers#clean_load_path` (`lib/bundler/shared_helpers.rb`, line 391): a boot feature (US-ASCII, invalid) against a `$LOAD_PATH` entry (BINARY).
2. `Bundler::SharedHelpers#set_path` (line 360): `ENV["PATH"]` (BINARY) joined with `"#{Bundler.bundle_path}/bin"` (UTF-8, from `RbConfig`): "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)".
3. `Bundler::FriendlyErrors.serialized_exception_for` (`lib/bundler/friendly_errors.rb`, line 98), above.
4. `Bundler::Env.environment` (`lib/bundler/env.rb`, line 106), which the same report calls next: `caller_locations.last.absolute_path` is US-ASCII and invalid, and `match?` raises "invalid byte sequence in US-ASCII". `bundle env` fails there too.
5. `Bundler::CLI::Exec#ruby_shebang?` (`lib/bundler/cli/exec.rb`, line 125): the script's first line, read as BINARY, against `"#!#{Gem.ruby}\n"`, UTF-8 and outside ASCII. This one needs no locale: `bundle exec ruby main.rb` fails the same way with `LANG=C.UTF-8`, whenever Ruby's own path is not ASCII. Under that locale, on Ubuntu 26.04 with Ruby 4.1.0-preview1 for x86_64-linux in such a folder:

   ```
   Encoding::CompatibilityError: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
     .../bundler/cli/exec.rb:125:in 'String#start_with?'
     .../bundler/cli/exec.rb:125:in 'block in Bundler::CLI::Exec#ruby_shebang?'
     .../bundler/cli/exec.rb:125:in 'Array#any?'
     .../bundler/cli/exec.rb:125:in 'Bundler::CLI::Exec#ruby_shebang?'
     .../bundler/cli/exec.rb:92:in 'Bundler::CLI::Exec#directly_loadable?'
     .../bundler/cli/exec.rb:22:in 'Bundler::CLI::Exec#run'
   ```

6. `Bundler::Runtime#setup_manpath` (`lib/bundler/runtime.rb`, line 351): `path.sub(/lib$/, "man")` on a `-I` or `RUBYLIB` entry, which is US-ASCII and invalid. This one needs no Ruby in such a folder, only a load path entry in one. With the same Ruby built from source by mise and installed at an ASCII path, its default Bundler 4.1.0.beta2, in any bundle, on macOS:

   ```
   $ env -i PATH=... HOME=... ruby -I "/tmp/Ünï/lib" -e 'require "bundler/setup"'
   .../lib/ruby/4.1.0+5/bundler/runtime.rb:352:in 'String#sub': invalid byte sequence in US-ASCII (ArgumentError)

           man_subdir = path.sub(/lib$/, "man")
                                 ^^^^^^^^^^^^^
   	from .../lib/ruby/4.1.0+5/bundler/runtime.rb:352:in 'block in Bundler::Runtime#setup_manpath'
   ```

7. `Bundler::Env.append_formatted_table` (`lib/bundler/env.rb`, line 124), once `Env.environment` gets past line 106: `bundle env` joins the report's values, some BINARY (from `ENV`) and some UTF-8 (from `RbConfig`). With Ruby 4.1.0-preview1 built from its release tarball and installed with `--prefix` under such a folder, on Ubuntu 26.04:

   ```
   .../lib/ruby/4.1.0+5/bundler/env.rb:124:in 'block in Bundler::Env.append_formatted_table': incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT) (Encoding::CompatibilityError)
   	from .../lib/ruby/4.1.0+5/bundler/env.rb:123:in 'Array#each'
   ```

On Linux, before any of these, Bundler's vendored Thor fails as it loads, for `require "bundler/setup"` as for `ruby -rbundler/setup` (seen with Ruby 4.1.0-preview1 built from its release tarball with `--prefix` under such a folder, on Ubuntu 26.04): `bundler/vendor/thor/lib/thor/command.rb`, line 3, "invalid multibyte character"; on macOS, after them, the vendored Thor's `register_klass_file` fails as `bundle` defines its commands. Both are Thor's, and are fixed in rails/thor (link the Thor pull request here when it is open).

## What is your fix for the problem, implemented in this PR?

Compare and join paths as bytes where they meet, which is what a path is to the operating system:

- `clean_load_path` compares the bytes of each load path with the bytes of the loaded features, made once rather than for each path;
- `set_path` joins the bytes of the `PATH` entries, and `setup_manpath` rewrites the bytes of a load path, which `ENV` takes either way;
- `ruby_shebang?` compares the bytes it read with the bytes of each shebang, and `Env.environment` matches the bytes of the executable's path, reads its shebang as bytes, and compares those with `Gem.ruby`'s;
- `append_formatted_table` reports each value as valid UTF-8, replacing bytes that are not, so the report's rows can come from anywhere;
- `serialized_exception_for` makes the message and each backtrace line valid UTF-8 before joining them, replacing bytes that are not, so reporting an error cannot raise.

With a UTF-8 locale nothing changes but the encoding of the strings handed to `ENV`, which stores bytes. Converting every path to UTF-8 at the boundary instead would need to know where each came from, and `force_encoding` on an invalid string only moves the failure to the next match.

With this patch and the Thor one, in the setup above, `require "bundler/setup"`, `ruby -rbundler/setup main.rb`, `ruby -I` a folder named outside ASCII `-rbundler/setup main.rb`, `bundle exec ruby main.rb`, `bundle -v`, `bundle exec rake --version`, `bundle install --local`, and `bundle env` all run with no locale (and `bundle exec ruby main.rb` with `LANG=C.UTF-8` too, checked on macOS and with jdx/ruby's build on Linux): on macOS with the rv-ruby build above, and on Ubuntu 26.04 (glibc 2.43) with Ruby 4.1.0-preview1 built from its release tarball and installed with `--prefix` under such a folder. (With jdx/ruby's relocatable build of the same Ruby moved into such a folder on Linux, `bundle exec` alone still failed, in the child Ruby before Bundler ran: it loaded `rbconfig.rb` a second time and raised in it. That build adds its own RubyGems plugin in `site_ruby`, which stock Ruby has not, and the cause was not looked into further.)

`spec/bundler/path_encodings_spec.rb` builds the three kinds of string directly, so it needs no locale: one example for each of the seven places, each failing without its change.

## Make sure the following tasks are checked

- [x] Describe the problem / feature
- [x] Write [tests](https://github.com/ruby/rubygems/blob/master/doc/PULL_REQUESTS.md#tests) for features and bug fixes
- [x] Write code to solve the problem
- [x] Make sure you follow the [current code style](https://github.com/ruby/rubygems/blob/master/doc/PULL_REQUESTS.md#code-formatting) and [write meaningful commit messages without tags](https://github.com/ruby/rubygems/blob/master/doc/PULL_REQUESTS.md#commit-messages)

<!--
SPDX-SnippetBegin
SPDX-SnippetCopyrightText: Chad Fowler, Rich Kilmer, Jim Weirich and others; portions André Arko and Engine Yard
SPDX-License-Identifier: MIT
SPDX-SnippetComment: A patch to lib/bundler/ and spec/ of ruby/rubygems at c6c69d31d4, and a new spec for it
-->

```diff
diff --git a/lib/bundler/cli/exec.rb b/lib/bundler/cli/exec.rb
index cd8a4d9..b95819e 100644
--- a/lib/bundler/cli/exec.rb
+++ b/lib/bundler/cli/exec.rb
@@ -122,7 +122,7 @@ def ruby_shebang?(file)
       end
 
       first_line = File.open(file, "rb") {|f| f.read(possibilities.map(&:size).max) }
-      possibilities.any? {|shebang| first_line.start_with?(shebang) }
+      possibilities.any? {|shebang| first_line.start_with?(shebang.b) }
     end
   end
 end
diff --git a/lib/bundler/env.rb b/lib/bundler/env.rb
index 99df2e4..d0c38a4 100644
--- a/lib/bundler/env.rb
+++ b/lib/bundler/env.rb
@@ -103,10 +103,10 @@ def self.environment
       end
       out << ["Git", git_version]
 
-      if (exe = caller_locations.last.absolute_path)&.match? %r{(exe|bin)/bundler?\z}
-        shebang = File.read(exe).lines.first
+      if (exe = caller_locations.last.absolute_path&.b)&.match? %r{(exe|bin)/bundler?\z}
+        shebang = String.new(File.binread(exe).lines.first, encoding: Encoding::UTF_8).scrub
         shebang.sub!(/^#!\s*/, "")
-        unless shebang.start_with?(Gem.ruby, "/usr/bin/env ruby")
+        unless shebang.b.start_with?(Gem.ruby.b, "/usr/bin/env ruby")
           out << ["Gem.ruby", Gem.ruby]
           out << ["bundle #!", shebang]
         end
@@ -121,7 +121,9 @@ def self.append_formatted_table(title, pairs, out)
       out << "## #{title}\n\n```\n"
       ljust = pairs.map {|k, _v| k.to_s.length }.max
       pairs.each do |k, v|
-        out << "#{k.to_s.ljust(ljust)}  #{v}\n"
+        # A path can be BINARY here and UTF-8 in the next row, when the
+        # locale's character set is ASCII; report every value as UTF-8.
+        out << "#{k.to_s.ljust(ljust)}  #{String.new(v.to_s, encoding: Encoding::UTF_8).scrub}\n"
       end
       out << "```\n"
     end
diff --git a/lib/bundler/friendly_errors.rb b/lib/bundler/friendly_errors.rb
index 5e8eaee..a7b7eaa 100644
--- a/lib/bundler/friendly_errors.rb
+++ b/lib/bundler/friendly_errors.rb
@@ -94,11 +94,18 @@ def exception_message(error)
 
     def serialized_exception_for(e)
       <<~EOS
-        #{e.class}: #{e.message}
-          #{e.backtrace&.join("\n          ")&.chomp}
+        #{e.class}: #{utf8(e.message)}
+          #{e.backtrace&.map {|line| utf8(line) }&.join("\n          ")&.chomp}
       EOS
     end
 
+    # The message and the backtrace's lines can be in different encodings,
+    # or invalid in their own, as paths are with a locale whose character
+    # set is ASCII. Joining them must not raise while reporting an error.
+    def utf8(string)
+      String.new(string.to_s, encoding: Encoding::UTF_8).scrub
+    end
+
     def issues_url(exception)
       message = exception.message.lines.first.tr(":", " ").chomp
       message = message.split("-").first if exception.is_a?(Errno)
diff --git a/lib/bundler/runtime.rb b/lib/bundler/runtime.rb
index c69925e..917a1ac 100644
--- a/lib/bundler/runtime.rb
+++ b/lib/bundler/runtime.rb
@@ -348,7 +348,7 @@ def prune_git_and_path_cache(resolve, cache_path)
     def setup_manpath
       # Add man/ subdirectories from activated bundles to MANPATH for man(1)
       manuals = $LOAD_PATH.filter_map do |path|
-        man_subdir = path.sub(/lib$/, "man")
+        man_subdir = path.b.sub(/lib$/, "man")
         man_subdir unless SharedHelpers.glob_files_in_dir("man?/", man_subdir).empty?
       end
 
diff --git a/lib/bundler/shared_helpers.rb b/lib/bundler/shared_helpers.rb
index 09cee89..bdd9281 100644
--- a/lib/bundler/shared_helpers.rb
+++ b/lib/bundler/shared_helpers.rb
@@ -357,7 +357,7 @@ def set_path
       validate_bundle_path
       paths = (ENV["PATH"] || "").split(File::PATH_SEPARATOR)
       paths.unshift "#{Bundler.bundle_path}/bin"
-      Bundler::SharedHelpers.set_env "PATH", paths.uniq.join(File::PATH_SEPARATOR)
+      Bundler::SharedHelpers.set_env "PATH", paths.map(&:b).uniq.join(File::PATH_SEPARATOR)
     end
 
     def set_rubyopt
@@ -386,9 +386,14 @@ def bundler_ruby_lib
     def clean_load_path
       loaded_gem_paths = Bundler.rubygems.loaded_gem_paths
 
+      # Compare bytes: with a locale whose character set is ASCII, Ruby can
+      # give one directory different encodings in $LOAD_PATH and in
+      # $LOADED_FEATURES, and String#start_with? raises for those.
+      loaded_features = $LOADED_FEATURES.map(&:b)
+
       $LOAD_PATH.reject! do |p|
-        resolved_path = resolve_path(p)
-        next if $LOADED_FEATURES.any? {|lf| lf.start_with?(resolved_path) }
+        resolved_path = resolve_path(p).b
+        next if loaded_features.any? {|lf| lf.start_with?(resolved_path) }
         loaded_gem_paths.delete(p)
       end
       $LOAD_PATH.uniq!
diff --git a/spec/bundler/path_encodings_spec.rb b/spec/bundler/path_encodings_spec.rb
new file mode 100644
index 0000000..89a05f7
--- /dev/null
+++ b/spec/bundler/path_encodings_spec.rb
@@ -0,0 +1,108 @@
+# frozen_string_literal: true
+
+require "bundler/cli"
+require "bundler/cli/exec"
+require "bundler/friendly_errors"
+
+# With a locale whose character set is ASCII (no LANG at all, or LANG=C), Ruby
+# gives a path whose name is not ASCII different encodings depending on where
+# the path comes from: BINARY for ENV and Dir.pwd, US-ASCII with invalid bytes
+# for __dir__, -I and RUBYLIB entries and some loaded features, and UTF-8 for
+# paths built from RbConfig or from literals. These examples build such strings
+# directly, so they need no particular locale to run.
+RSpec.describe "paths in mixed encodings" do
+  let(:dir) { "/opt/caf\xC3\xA9" }
+  let(:binary) { dir.b }
+  let(:broken_ascii) { dir.dup.force_encoding(Encoding::US_ASCII) }
+  let(:utf8) { dir.dup.force_encoding(Encoding::UTF_8) }
+
+  # Runs the block with only +load_path+ in $LOAD_PATH, and +feature+ added
+  # to $LOADED_FEATURES, then restores both.
+  def with_globals(load_path:, feature: nil)
+    saved_load_path = $LOAD_PATH.dup
+    $LOAD_PATH.replace(load_path)
+    $LOADED_FEATURES << feature if feature
+    yield
+  ensure
+    $LOADED_FEATURES.delete(feature) if feature
+    $LOAD_PATH.replace(saved_load_path)
+  end
+
+  describe "Bundler::SharedHelpers#clean_load_path" do
+    it "compares load paths and loaded features as bytes" do
+      allow(Bundler.rubygems).to receive(:loaded_gem_paths).and_return([])
+      kept = nil
+
+      with_globals(load_path: ["#{binary}/lib".b], feature: "#{broken_ascii}/lib/foo.rb".dup.force_encoding(Encoding::US_ASCII)) do
+        Bundler::SharedHelpers.send(:clean_load_path)
+        kept = $LOAD_PATH.dup
+      end
+
+      expect(kept).to eq(["#{binary}/lib".b])
+    end
+  end
+
+  describe "Bundler::SharedHelpers#set_path" do
+    it "joins a PATH and a bundle path in different encodings" do
+      allow(Bundler).to receive(:bundle_path).and_return(Pathname.new("#{utf8}/gems"))
+      allow(ENV).to receive(:[]).and_call_original
+      allow(ENV).to receive(:[]).with("PATH").and_return("#{binary}/bin".b)
+      expect(Bundler::SharedHelpers).to receive(:set_env).with("PATH", "#{binary}/gems/bin#{File::PATH_SEPARATOR}#{binary}/bin".b)
+
+      Bundler::SharedHelpers.send(:set_path)
+    end
+  end
+
+  describe "Bundler::Runtime#setup_manpath" do
+    it "takes a load path that is invalid in its encoding" do
+      runtime = Bundler::Runtime.allocate
+      error = nil
+
+      with_globals(load_path: ["#{broken_ascii}/lib".dup.force_encoding(Encoding::US_ASCII)]) do
+        runtime.send(:setup_manpath)
+      rescue StandardError => e
+        error = e
+      end
+
+      expect(error).to be_nil
+    end
+  end
+
+  describe "Bundler::CLI::Exec#ruby_shebang?" do
+    it "compares the shebang with a Ruby whose path is not ASCII" do
+      script = tmp("script")
+      File.write(script, "#!#{utf8}/bin/ruby\nputs 1\n")
+      allow(Gem).to receive(:ruby).and_return("#{utf8}/bin/ruby")
+
+      expect(Bundler::CLI::Exec.new(double("options", keep_file_descriptors?: false), []).send(:ruby_shebang?, script)).to be(true)
+    end
+  end
+
+  describe "Bundler::Env.report" do
+    it "reads the bundle executable from a path that is invalid in its encoding, and reports its shebang" do
+      exe = tmp("café/exe/bundle")
+      FileUtils.mkdir_p(File.dirname(exe))
+      File.write(exe, "#!#{utf8}/bin/ruby\n")
+      allow(Bundler::Env).to receive(:caller_locations).and_return([double(absolute_path: exe.to_s.dup.force_encoding(Encoding::US_ASCII))])
+
+      expect(Bundler::Env.report).to include("#{utf8}/bin/ruby")
+    end
+
+    it "reports paths in different encodings in one table" do
+      allow(Gem).to receive(:ruby).and_return("#{utf8}/bin/ruby")
+      allow(Gem).to receive(:user_home).and_return("#{binary}/home".b)
+
+      expect(Bundler::Env.report).to include("#{utf8}/bin/ruby", "#{utf8}/home")
+    end
+  end
+
+  describe "Bundler::FriendlyErrors.request_issue_report_for" do
+    it "reports an error whose backtrace mixes encodings" do
+      error = StandardError.new("failed")
+      error.set_backtrace(["#{utf8}/a.rb:1:in 'a'", "#{broken_ascii}/b.rb:2:in 'b'".dup.force_encoding(Encoding::US_ASCII)])
+      allow(Bundler::FriendlyErrors).to receive(:issues_url).and_return("")
+
+      expect { Bundler::FriendlyErrors.request_issue_report_for(error) }.not_to raise_error
+    end
+  end
+end
diff --git a/spec/support/shards.rb b/spec/support/shards.rb
index e3cadf9..445c12a 100644
--- a/spec/support/shards.rb
+++ b/spec/support/shards.rb
@@ -145,6 +145,7 @@ module Shards
       ],
       shard_d: [
         "spec/bundler/cli/exec_spec.rb",
+        "spec/bundler/path_encodings_spec.rb",
         "spec/bundler/rubygems_ext_spec.rb",
         "spec/bundler/resolver/cooldown_spec.rb",
         "spec/install/cooldown_spec.rb",
```

<!--
SPDX-SnippetEnd
-->

---

This pull request was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
