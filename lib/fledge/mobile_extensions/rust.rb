# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "../error"

module Fledge
  class MobileExtensions
    # What compiles a Rust extension for one target of a phone: one an
    # <tt>extconf.rb</tt> writes with rb-sys's <tt>create_rust_makefile</tt>.
    #
    # rb-sys's Makefile runs <tt>cargo rustc</tt> for the target in
    # <tt>CARGO_BUILD_TARGET</tt>, and its build script reads the Ruby it
    # compiles for from the <tt>RBCONFIG_</tt> variables that Makefile
    # exports, which come from the phone runtime's <tt>rbconfig.rb</tt>,
    # with the phone's headers (MobileExtensions::SHIM). bindgen reads those
    # headers for the target, given the target's SDK or sysroot here
    # (BINDGEN_EXTRA_CLANG_ARGS_TARGET, which bindgen documents). The shim
    # (SHIM) asks Cargo for a static library, as Tauri builds a Rust
    # library into an iOS or Android app, and asks rustc which native
    # libraries it needs (<tt>--print native-static-libs</tt>), which the
    # app links with it. The extension keeps its own
    # <tt>Init_</tt> function, which rb-sys's macro names after the
    # extension, so two Rust extensions of one name cannot be in one app.
    #
    # Use Rust.environment for the target's variables, Rust.check for its
    # standard library, and Rust::SHIM before an <tt>extconf.rb</tt> that
    # needs rb_sys.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions::Rust.triple("ios-arm64-simulator") # => "aarch64-apple-ios-sim"
    #--
    # SPDX-SnippetEnd
    #++
    module Rust
      # Rust's target for each target of a phone: an iOS slice's, and an
      # Android ABI's Ruby architecture, which is already Rust's name.
      TRIPLES = {
        "ios-arm64" => "aarch64-apple-ios",
        "ios-arm64-simulator" => "aarch64-apple-ios-sim",
        "aarch64-linux-android" => "aarch64-linux-android",
        "x86_64-linux-android" => "x86_64-linux-android",
      }.freeze

      # The file the shim has rustc write the native libraries the static
      # library needs into, in the extension's folder.
      NATIVE_LIBS = "fledge-native-static-libs.txt"

      # The file make writes the static library's path into, in the
      # extension's folder (MAKEFILE).
      LIBRARY = "fledge-rustlib.txt"

      # The Makefile that builds only the static library: rb-sys's own,
      # with one goal that names its <tt>$(RUSTLIB)</tt>.
      MAKEFILE = "fledge-rust.mk"

      # What the runtime's Ruby loads after MobileExtensions::SHIM for an
      # extension that needs rb_sys: rb-sys's <tt>create_rust_makefile</tt>,
      # which needs RubyGems' builder (so RubyGems, which the shim's Ruby
      # runs without, as an extconf.rb under RubyGems has it), wrapped so
      # that Cargo makes a static library with the gem's own
      # Cargo arguments (or the developer's, in RB_SYS_EXTRA_CARGO_ARGS,
      # which rb-sys's Makefile takes first), rustc writes the native
      # libraries it needs, and the report names it as Rust. For iOS it
      # gives rb-sys's build script Rust's name for the system,
      # <tt>ios</tt> (FLEDGE_RUST_TARGET_OS), where the runtime's
      # <tt>rbconfig.rb</tt> records <tt>darwin</tt>, the system Ruby's
      # configure took it for: rb-sys refuses headers of another family of
      # systems than Cargo's target's, and counts <tt>darwin</tt> and
      # <tt>ios</tt> as two (<tt>RbConfig#validate_cargo_target</tt>,
      # <tt>rb-sys-build/src/rb_config.rs</tt>, lines 236 to 250 and 531
      # to 587 at 0.9.130).
      SHIM = <<~'RUBY'
        require "rubygems"
        require "shellwords"
        require "rb_sys/mkmf"
        module RbSys::Mkmf
          alias_method :fledge_create_rust_makefile, :create_rust_makefile
          def create_rust_makefile(target, &block)
            result = fledge_create_rust_makefile(target) do |config|
              block&.call(config)
              raise "Fledge compiles a Rust extension for a phone with cargo rustc, and #{target} asks for cargo build" if config.use_cargo_build

              args = ENV.key?("RB_SYS_EXTRA_CARGO_ARGS") ? ENV.fetch("RB_SYS_EXTRA_CARGO_ARGS").shellsplit : config.extra_cargo_args
              config.extra_cargo_args = [*args, "--crate-type", "staticlib"]
              config.extra_rustc_args += ["--print=native-static-libs=#{File.join(Dir.pwd, ENV.fetch('FLEDGE_RUST_NATIVE_LIBS'))}"]
              config.env = config.env.merge("RBCONFIG_target_os" => ENV.fetch("FLEDGE_RUST_TARGET_OS")) if ENV.key?("FLEDGE_RUST_TARGET_OS")
            end
            File.write(ENV.fetch("FLEDGE_RUST_MAKEFILE"), "include Makefile\nfledge-rust: $(RUSTLIB)\n\t@echo \"$(RUSTLIB)\" > #{ENV.fetch('FLEDGE_RUST_LIBRARY')}\n")
            reports = File.exist?(ENV.fetch("FLEDGE_REPORT")) ? JSON.parse(File.read(ENV.fetch("FLEDGE_REPORT"))) : []
            reports << { "feature" => target, "rust" => "yes", "dir" => Dir.pwd }
            File.write(ENV.fetch("FLEDGE_REPORT"), JSON.generate(reports))
            result
          end
        end
      RUBY

      # Rust's target for the phone's target +name+.
      def self.triple(name)
        TRIPLES.fetch(name) { raise Error, "Fledge knows no Rust target for #{name}" }
      end

      # The variables that aim Cargo, rustc, and bindgen at the phone's
      # target +name+: Cargo's target; for iOS, the deployment target of
      # the runtime's triple (rustc reads it) and the SDK at +sysroot+ for
      # bindgen; for Android, the NDK's compilers +cc+ and +ar+ for a
      # crate that compiles C with the cc crate, and the NDK's sysroot
      # for bindgen.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Rust.ios("ios-arm64", triple: "arm64-apple-ios15.0", sysroot: sdk)
      #   # => { "CARGO_BUILD_TARGET" => "aarch64-apple-ios", "IPHONEOS_DEPLOYMENT_TARGET" => "15.0", ... }
      #--
      # SPDX-SnippetEnd
      #++
      def self.ios(name, triple:, sysroot:)
        version = triple[/-ios([\d.]+)/, 1] or raise Error, "#{triple} is not a target triple of iOS"
        rust = triple(name)
        {
          "CARGO_BUILD_TARGET" => rust,
          "IPHONEOS_DEPLOYMENT_TARGET" => version,
          bindgen(rust) => "-isysroot #{sysroot}",
          "FLEDGE_RUST_TARGET_OS" => "ios",
        }
      end

      # The same for the Android target +name+ with the NDK's tools in
      # +bin+, its compiler +cc+, and that compiler's own headers in
      # +builtins+ (<tt>stdarg.h</tt> and the rest, which
      # <tt>cc -print-file-name=include</tt> names). bindgen's libclang is
      # this computer's, whose own headers may be missing or another
      # version's, so bindgen gets the NDK clang's, as rb-sys's
      # <tt>mkmf.rb</tt> gives a libclang it brings the compiler's
      # (<tt>try_load_bundled_libclang</tt> and
      # <tt>compiler_builtin_include_dir</tt>, <tt>lib/rb_sys/mkmf.rb</tt>,
      # lines 362 to 402 at 0.9.130). bindgen also gets the clang target
      # +cc+ is named for, with the API level the runtime was built for
      # (<tt>aarch64-linux-android26</tt>): left to itself it passes
      # Rust's, which has none, and the NDK's headers refuse a target
      # without one (<tt>sys/cdefs.h</tt>); bindgen takes an explicit
      # <tt>--target</tt> over its own (<tt>find_effective_target</tt>,
      # <tt>bindgen/lib.rs</tt>, lines 728 to 801 at 0.72.1).
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Rust.android("x86_64-linux-android", bin: ndk.bin, cc:, builtins:)
      #   # => { "CARGO_BUILD_TARGET" => "x86_64-linux-android", "CC_x86_64_linux_android" => cc, ... }
      #--
      # SPDX-SnippetEnd
      #++
      def self.android(name, bin:, cc:, builtins:)
        rust = triple(name)
        variable = rust.tr("-", "_")
        {
          "CARGO_BUILD_TARGET" => rust,
          "CC_#{variable}" => cc,
          "CXX_#{variable}" => "#{cc}++",
          "AR_#{variable}" => File.join(bin, "llvm-ar"),
          bindgen(rust) => "--target=#{File.basename(cc).delete_suffix('-clang')} --sysroot=#{File.join(File.dirname(bin), 'sysroot')} -isystem #{builtins}",
        }
      end

      # bindgen's variable of extra clang arguments for the Rust target
      # +rust+ alone, so that a build script compiled for this computer
      # does not get them.
      def self.bindgen(rust)
        "BINDGEN_EXTRA_CLANG_ARGS_#{rust.tr('-', '_')}"
      end
      private_class_method :bindgen

      # Raises Fledge::Error unless the Rust found in +env+ has the
      # standard library of the Rust target +rust+, saying how to add it.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Rust.check("aarch64-apple-ios", gem: "ferro-idna 0.1.0", env: {})
      #--
      # SPDX-SnippetEnd
      #++
      def self.check(rust, gem:, env:)
        folder, _, status = Open3.capture3(env, "rustc", "--print", "target-libdir", "--target", rust)
        return if status.success? && Dir.exist?(folder.strip)

        raise Error, "#{gem} is a Rust extension, and compiling it for #{rust} needs Rust and Cargo with Rust's standard " \
          "library for #{rust}, which this computer's Rust does not have. Install Rust, and add the target with " \
          "rustup target add #{rust}."
      rescue SystemCallError
        raise Error, "#{gem} is a Rust extension, and compiling it needs Rust and Cargo, which fledge build could not run " \
          "here. Install Rust, and add the target with rustup target add #{rust}."
      end
    end
  end
end
