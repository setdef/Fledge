<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Thor pull request, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, as a pull request to https://github.com/rails/thor: fork it, make a branch from `main` (the change was made on cb11e8e87b), apply the patch below with `git apply`, commit it, push the branch to the fork, and open the pull request with the title below and everything after the line as its description (GitHub takes Markdown).

Thor's `CONTRIBUTING.md` asks for specs with the change, for `bundle exec rspec` and `bundle exec rubocop` to pass, and for its 🌈 at the top of the ticket, to show the guide was read; the description below starts with it. It says nothing about AI-assisted contributions either way. Before filing: search rails/thor's issues and pull requests for "invalid byte sequence", "register_klass_file", and "FILE_REGEXP", since someone may have reported it after 2026-11-14 (on that day nothing matched; #184, closed in 2011, is a different line failing the same way, and #406, open, asks for less backtrace work in `register_klass_file`, which this change also does); run Thor's whole suite once, which was not run here (the new spec file and eight that cover the changed code were: 265 examples, no failures, on stock Ruby 4.1.0-preview1 on macOS, and `rubocop` on the four files found no offenses); and read the description start to finish as your own words, since you are the one filing it.

Found when Fledge, which runs Ruby with no locale, set up Bundler for an app in a folder named outside ASCII: Bundler vendors Thor, and its copy fails first (`doc/contributors/research/2026-11-13-c-locale.md`). Everything below runs on stock Ruby, without Fledge. Once this is merged and Bundler vendors the Thor that has it, the Bundler draft beside this one ([bundler-c-locale-paths.md](bundler-c-locale-paths.md)) needs nothing more from Thor.

- **Title:** Run under the C locale from a folder whose name is not ASCII

---

🌈

## The problem

With no locale, or `LC_ALL=C`, Ruby's encoding for paths is US-ASCII, and a path whose name is not ASCII comes back as a string that is not valid in its own encoding: `__dir__`, `$0`, `-I` and `RUBYLIB` entries, and the frames of `caller` that name such a file. A Regexp cannot match those strings, and Thor matches three of them:

1. `Thor::Base.register_klass_file` takes the caller's file from `caller[1].match(/(.*):\d+/)` (`lib/thor/base.rb`, line 146). Any Thor class defined in a script run by its absolute path from such a folder fails there, as a CLI found on `PATH` is run.
2. `Thor.subcommand_help` defines `help` with a `class_eval` of a string and no file (`lib/thor.rb`, line 651). `register_klass_file` then expands the frame's path, `(eval at /.../thor.rb:651)`, against the current directory, and when Thor itself lives in such a folder (a gem installed under `/home/josé`) and the current directory is one too, `File.expand_path` raises "incompatible character encodings: UTF-8 and US-ASCII" (`lib/thor/base.rb`, line 149).
3. `Thor::Command#sans_backtrace` matches each frame against `FILE_REGEXP` and two other Regexps (`lib/thor/command.rb`, line 110), so reporting a command called with the wrong arguments raises instead. And `FILE_REGEXP` itself (`lib/thor/command.rb`, line 3) cannot be built when `__FILE__` is such a string: Bundler's vendored copy of Thor fails there with "invalid multibyte character" on Linux, with Ruby installed under a folder named outside ASCII.

A CLI with a subcommand:

```ruby
require "thor"

class Remote < Thor
  desc "list", "List remotes"
  def list
    puts "origin"
  end
end

class CLI < Thor
  desc "hello", "Say hello"
  def hello
    puts "hello"
  end

  desc "remote SUBCOMMAND", "Manage remotes"
  subcommand "remote", Remote
end

CLI.start(ARGV)
```

Saved as `cli.rb` in a folder named `Ünï`, with Thor at `main` (cb11e8e87b) on the load path, on ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-darwin27]:

```
$ LC_ALL=C ruby -I /path/to/thor/lib "$PWD/cli.rb" hello
/path/to/thor/lib/thor/base.rb:146:in 'Regexp#match': invalid byte sequence in US-ASCII (ArgumentError)

        file = caller[1].match(/(.*):\d+/)[1]
                               ^^^^^^^^^^
	from /path/to/thor/lib/thor/base.rb:146:in 'String#match'
	from /path/to/thor/lib/thor/base.rb:146:in 'Thor::Base.register_klass_file'
	from /path/to/thor/lib/thor/base.rb:724:in 'Thor::Base::ClassMethods#inherited'
	from /path/to/Ünï/cli.rb:3:in '<main>'
```

With the first fix alone, a CLI without the subcommand runs, but a command called with too many arguments raises in `sans_backtrace`:

```
$ LC_ALL=C ruby -I /path/to/thor/lib "$PWD/cli.rb" hello extra
/path/to/thor/lib/thor/command.rb:110:in 'block in Thor::Command#sans_backtrace': invalid byte sequence in US-ASCII (ArgumentError)
```

And with Thor's lib copied into the folder too, the subcommand fails at load:

```
$ LC_ALL=C ruby -I "$PWD/thorlib" "$PWD/cli.rb" remote list
/path/to/Ünï/thorlib/thor/base.rb:149:in 'File.expand_path': incompatible character encodings: UTF-8 and US-ASCII (Encoding::CompatibilityError)
	from /path/to/Ünï/thorlib/thor/base.rb:149:in 'Thor::Base.register_klass_file'
	from /path/to/Ünï/thorlib/thor/base.rb:745:in 'Thor::Base::ClassMethods#method_added'
	from (eval at /path/to/Ünï/thorlib/thor.rb:651):2:in 'Thor.subcommand_help'
```

The same happened on Ubuntu 26.04 (glibc 2.43) with Ruby 4.1.0-preview1 for x86_64-linux. With a UTF-8 locale, all three run.

## The fix

- `register_klass_file` takes the path from `caller_locations(2, 1).first.path`, which is what the Regexp extracted from `caller[1]`, without matching it, and without building the whole backtrace as strings (#406).
- `subcommand_help` passes `__FILE__` and the line to `class_eval`, as Thor's other `class_eval` calls do (`lib/thor/base.rb`, line 609; `lib/thor/group.rb`, lines 64 and 123), so the frame names a real, absolute file and `File.expand_path` has no current directory to join.
- `Thor::Command` keeps the bytes of its directory in `FILE_PREFIX`, and `sans_backtrace` compares each frame's bytes with it, and matches its other two Regexps against the frame's bytes, which ASCII Regexps always can. That removes the constant `FILE_REGEXP`, which only `sans_backtrace` used; sorbet-typed's `thor.rbi` lists it, so a project that reads it would need the new name.

`spec/locale_spec.rb` runs a CLI like the one above, with Thor's lib copied into a temporary folder named `café`, under `LC_ALL=C`: a command, a subcommand, and a command with too many arguments. All three fail without the change.

<!--
SPDX-SnippetBegin
SPDX-SnippetCopyrightText: 2008 Yehuda Katz, Eric Hodel, et al.
SPDX-License-Identifier: MIT
SPDX-SnippetComment: A patch to lib/thor.rb, lib/thor/base.rb, and lib/thor/command.rb of rails/thor at cb11e8e87b, and a new spec for it
-->

```diff
diff --git a/lib/thor.rb b/lib/thor.rb
index 8648505..8bf8c4f 100644
--- a/lib/thor.rb
+++ b/lib/thor.rb
@@ -650,7 +650,7 @@ class Thor
       desc "help [COMMAND]", "Describe subcommands or one specific subcommand"
       class_eval "
         def help(command = nil, subcommand = true); super; end
-"
+", __FILE__, __LINE__ - 2
     end
     alias_method :subtask_help, :subcommand_help
 
diff --git a/lib/thor/base.rb b/lib/thor/base.rb
index 5818789..5835d65 100644
--- a/lib/thor/base.rb
+++ b/lib/thor/base.rb
@@ -143,7 +143,7 @@ class Thor
       # class and the file on Thor::Base. This is the method responsible for it.
       #
       def register_klass_file(klass) #:nodoc:
-        file = caller[1].match(/(.*):\d+/)[1]
+        file = caller_locations(2, 1).first.path
         Thor::Base.subclasses << klass unless Thor::Base.subclasses.include?(klass)
 
         file_subclasses = Thor::Base.subclass_files[File.expand_path(file)]
diff --git a/lib/thor/command.rb b/lib/thor/command.rb
index c6bdf74..07f7267 100644
--- a/lib/thor/command.rb
+++ b/lib/thor/command.rb
@@ -1,6 +1,9 @@
 class Thor
   class Command < Struct.new(:name, :description, :long_description, :wrap_long_description, :usage, :options, :options_relation, :ancestor_name)
-    FILE_REGEXP = /^#{Regexp.escape(File.dirname(__FILE__))}/
+    # Bytes, not a Regexp: in a locale whose encoding is not UTF-8, this path
+    # and the frames of a backtrace can be in different encodings, or invalid
+    # in their own, and a Regexp of one cannot match the other.
+    FILE_PREFIX = File.dirname(__FILE__).b.freeze
 
     def initialize(name, description, long_description, wrap_long_description, usage, options = nil, options_relation = nil)
       super(name.to_s, description, long_description, wrap_long_description, usage, options || {}, options_relation || {})
@@ -107,7 +110,10 @@ class Thor
     end
 
     def sans_backtrace(backtrace, caller) #:nodoc:
-      saned = backtrace.reject { |frame| frame =~ FILE_REGEXP || (frame =~ /\.java:/ && RUBY_PLATFORM =~ /java/) || (frame =~ %r{^kernel/} && RUBY_ENGINE =~ /rbx/) }
+      saned = backtrace.reject do |frame|
+        frame = frame.b
+        frame.start_with?(FILE_PREFIX) || (frame =~ /\.java:/ && RUBY_PLATFORM =~ /java/) || (frame =~ %r{^kernel/} && RUBY_ENGINE =~ /rbx/)
+      end
       saned - caller
     end
 
diff --git a/spec/locale_spec.rb b/spec/locale_spec.rb
new file mode 100644
index 0000000..04e2791
--- /dev/null
+++ b/spec/locale_spec.rb
@@ -0,0 +1,62 @@
+require "helper"
+require "fileutils"
+require "rbconfig"
+require "tmpdir"
+
+describe "a Thor script in a folder whose name is not ASCII, under the C locale" do
+  def script_source
+    <<~RUBY
+      require "thor"
+
+      class Remote < Thor
+        desc "list", "List remotes"
+        def list
+          puts "origin"
+        end
+      end
+
+      class CLI < Thor
+        def self.exit_on_failure?
+          true
+        end
+
+        desc "hello", "Say hello"
+        def hello
+          puts "hello"
+        end
+
+        desc "remote SUBCOMMAND", "Manage remotes"
+        subcommand "remote", Remote
+      end
+
+      CLI.start(ARGV)
+    RUBY
+  end
+
+  # Runs the script by its absolute path, with Thor's lib copied beside it,
+  # as a gem installed under a home folder named outside ASCII would be.
+  def run_script(*args)
+    Dir.mktmpdir do |tmp|
+      dir = File.join(tmp, "café")
+      FileUtils.mkdir(dir)
+      FileUtils.cp_r(File.expand_path("../lib", __dir__), File.join(dir, "lib"))
+      script = File.join(dir, "cli.rb")
+      File.write(script, script_source)
+      env = {"LC_ALL" => "C", "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil}
+      IO.popen(env, [RbConfig.ruby, "-I", File.join(dir, "lib"), script, *args],
+               chdir: dir, err: [:child, :out], &:read)
+    end
+  end
+
+  it "runs a command" do
+    expect(run_script("hello")).to eq("hello\n")
+  end
+
+  it "runs a subcommand" do
+    expect(run_script("remote", "list")).to eq("origin\n")
+  end
+
+  it "reports a command called with too many arguments" do
+    expect(run_script("hello", "extra")).to include('ERROR: "cli.rb hello" was called with arguments ["extra"]')
+  end
+end
```

<!--
SPDX-SnippetEnd
-->

---

This pull request was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
