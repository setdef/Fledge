# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"

class RuntimeBuilder
  # The edits a mobile runtime makes to Ruby's own source before it builds
  # it (doc/contributors/design/phone-runtimes.md, "Scripted edits to
  # Ruby's source"). Each replaces lines of Ruby 4.1.0-preview1's files
  # that it names, and raises when they are not there, so that a new Ruby
  # whose files moved on fails the build at the edit to look at again,
  # rather than building a Ruby that is quietly different.
  module RubySource
    # The file each edit changes, relative to Ruby's source.
    FILES = {
      psych_extconf: "ext/psych/extconf.rb",
      vm_dump: "vm_dump.c",
      configure: "configure",
      configure_macos_minimum: "configure",
      ruby_c: "ruby.c",
      load_c: "load.c",
      file_c: "file.c",
      process_c: "process.c",
      process_c_umask: "process.c",
      file_c_umask: "file.c",
      thread_pthread_c: "thread_pthread.c",
      thread_c: "thread.c",
      dir_c: "dir.c",
      setproctitle_c: "missing/setproctitle.c",
    }.freeze

    # Applies the edits named in +edits+ (keys of FILES) to the source
    # tree +source+.
    def self.apply(source, edits)
      edits.each { |edit| edit(source, edit) }
    end

    # Applies the one edit +edit+ (a key of FILES), given the arguments
    # after the file's text, to the source tree +source+.
    def self.edit(source, edit, *)
      path = File.join(source, FILES.fetch(edit))
      File.write(path, public_send(edit, File.read(path), *))
    end

    # psych's extconf.rb prefers pkg-config's yaml-0.1, which is the
    # build machine's libyaml (Homebrew's, on a Mac), over the libyaml
    # the build names with --with-libyaml-dir; xord/cruby's Rakefile
    # (lines 312 to 317, at 11d62c4) makes the same edit.
    def self.psych_extconf(text)
      replace(text, /^elsif pkg_config\(['"]yaml-[\d.]+['"]\)$/, "elsif false", "psych's extconf.rb asks pkg-config for yaml-0.1")
    end

    # vm_dump.c starts the command in RUBY_ON_BUG with system() when Ruby
    # crashes; iOS has no system(), and configure is told so
    # (ac_cv_func_system=no), as in xord/cruby's Rakefile (lines 299 to
    # 310).
    def self.vm_dump(text)
      replace(text, /^(\s*)int r = system\(buf\);\n/,
        "#if defined(HAVE_SYSTEM)\n\\1int r = system(buf);\n#else\n\\1int r = -1;\n#endif\n", "vm_dump.c calls system(buf)")
    end

    # configure appends -android to a target system that already names
    # Android (configure.ac, line 617 at 4.1.0-preview1), so a --host of
    # aarch64-linux-android gives a RUBY_PLATFORM of
    # aarch64-linux-android-android. Termux guards the line
    # (termux-packages, packages/ruby/android-sdk-level.patch); this guards
    # it in the generated configure, which needs no autoreconf.
    def self.configure(text)
      replace(text, /^(\s*)target_os=\$\{target_os\}-android$/,
        "\\1case $target_os in *android*) ;; *) target_os=${target_os}-android ;; esac", "configure appends -android")
    end

    # configure refuses a darwin target whose MAC_OS_X_VERSION_MIN_REQUIRED
    # is below 10.6 (configure.ac, lines 439 to 451 at 4.1.0-preview1, from
    # ruby/ruby 3e96f16643, "Require Mac OS X 10.6 or later"). An iOS
    # target is darwin too, and the iOS SDK's AvailabilityMacros.h, given
    # no macOS deployment target by clang
    # (__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__), sets the macro to
    # 10.5 (lines 96 to 111), so configure stops with "Unsupported OS X
    # version is required". This keeps the check for a macOS target only,
    # in the generated configure, which needs no autoreconf.
    def self.configure_macos_minimum(text)
      replace(text, /^(\s*)#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6$/,
        "\\1#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6",
        "configure requires Mac OS X 10.6")
    end

    # Built with --enable-load-relative, Ruby derives its prefix from the
    # path of the file that holds libruby (ruby.c, runtime_libruby_path,
    # lines 594 to 663 at 4.1.0-preview1). On Android that file sits in a folder
    # of native libraries alone, and an iOS app may keep Ruby's library
    # anywhere in its bundle, so ruby_embed_libruby_path lets the embedder
    # name the path Ruby would otherwise read from dladdr.
    def self.ruby_c(text)
      edited = replace(text, /^(#elif defined\(HAVE_DLADDR\)\n    Dl_info dli;\n    VALUE fname, path;\n    const void\* addr = .*\n)\n/,
        "\\1\n    extern const char *ruby_embed_libruby_path;\n" \
          "    if (ruby_embed_libruby_path) return rb_str_new_cstr(ruby_embed_libruby_path);\n\n",
        "ruby.c finds libruby with dladdr")
      "#{edited}\nconst char *ruby_embed_libruby_path;\n"
    end

    # The gate before load.c's lookup of statically linked extensions
    # (search_required, lines 1199 to 1218 at 4.1.0-preview1), which a
    # require that finds no file reaches. +extensions+ is the full name of
    # the bundled gem each linked extension belongs to, by the feature
    # its gem requires it as (bigdecimal.so). A desktop Ruby finds a
    # gem's shared object only in the gem's own folders, which RubyGems
    # adds to $LOAD_PATH as it activates the gem (Gem::BasicSpecification#full_require_paths,
    # lib/rubygems/basic_specification.rb, lines 184 to 195): the gem's
    # extension folder, named for the gem's full name, among them. So
    # the gate lets the lookup find a gem's linked extension only while
    # a folder of that name is on $LOAD_PATH. Without it, a plain
    # require "bigdecimal" finds the linked bigdecimal.so before RubyGems
    # activates the gem, whose lib/bigdecimal.rb then never loads
    # (lib/rubygems/core_ext/kernel_require.rb, lines 79 to 81 and 138 to
    # 148: RubyGems tries Ruby's own require first, and activates a gem
    # only when that fails).
    def self.load_c(text, extensions)
      raise ArgumentError, "the gate needs a gem's extension to guard" if extensions.empty?

      table = extensions.sort.map { |feature, full| "    {#{feature.dump}, #{full.dump}},\n" }.join
      gated = replace(text, /^(            if \(st_lookup\(&vm->static_ext_inits, \(st_data_t\)ftptr, NULL\))\) \{\n/,
        "\\1 && fledge_gem_extension_reachable_p(box, ftptr)) {\n", "search_required looks up a linked extension")
      replace(gated, /^static int\nsearch_required\(/, "#{format(GATE, table:)}\nstatic int\nsearch_required(",
        "load.c defines search_required")
    end

    # rb_group_member, which File::Stat#readable?, #writable?,
    # #executable?, and #grpowned? ask about a file of a group that is
    # not the process's own (file.c, lines 1834 to 1862 at
    # 4.1.0-preview1), takes what getgroups(0, NULL) returns for a
    # count, -1 too, and ALLOCV_N then raises ArgumentError ("malloc:
    # possible integer overflow"). In an iOS app getgroups fails with
    # EINVAL: configure builds Ruby on Darwin with _DARWIN_C_SOURCE
    # (configure.ac, line 1154), which selects Libc's getgroups in place
    # of the kernel's (unistd.h's getgroups$DARWIN_EXTSN), and that one
    # looks the process's user up with getpwuid and fails when it finds
    # none (Libc, sys/getgroups.c, lines 35 to 58 at Libc-1752.120.2), as
    # an iOS app finds no user for its own user ID. The edit answers that
    # the process is in no other group, as file.c answers where there is
    # no getgroups, so the check goes on to the file's permission bits for
    # others, as it does on a desktop for a group the user is not in.
    # Ruby's master has the same lines (file.c, lines 1956 to 1958 at
    # ee74a10ca9).
    def self.file_c(text)
      replace(text, /^(    groups = getgroups\(0, NULL\);\n)(    gary = ALLOCV_N\(GETGROUPS_T, v, groups\);\n)/,
        "\\1    if (groups == -1) return FALSE;\n\\2", "rb_group_member counts the groups with getgroups")
    end

    # rb_fork_ruby unlocks the fork lock in the child as in the parent,
    # but on FreeBSD (process.c, lines 4084 to 4095 at 4.1.0-preview1),
    # then destroys it and initializes it again (thread_pthread.c,
    # rb_thread_reset_fork_lock, lines 1454 to 1466). The parent's
    # thread holds it for writing across fork, and bionic's
    # pthread_rwlock_unlock refuses with EPERM a write lock whose writer
    # is not the calling thread, by thread ID (libc/bionic/pthread_rwlock.cpp,
    # lines 487 to 495 at 731631f), while the child's only thread has an
    # ID of its own, which fork's clone writes into it
    # (libc/bionic/fork.cpp, lines 36 to 50), so the child stops in
    # Ruby's [BUG] handler. Had it got past, bionic's
    # pthread_rwlock_destroy returns EBUSY for a lock that is held (lines
    # 255 to 262). Ruby's master resets the child's copy without
    # unlocking it (ruby/ruby e06b9da3f2, [Bug #22445], for macOS's
    # EBUSY), which these two edits take.
    def self.process_c(text)
      replace(text, Regexp.new(Regexp.escape(FORK_UNLOCK)), FORK_RESET, "rb_fork_ruby releases the fork lock in the child but on FreeBSD")
    end

    # Process.spawn's, #exec's, and #system's umask: option, and
    # File.umask, pass the mask they are given to umask(2) as it is
    # (process.c, rb_execarg_run_options, line 3441, and file.c,
    # rb_file_s_umask, line 4485, at 4.1.0-preview1; the same at master
    # acc624e47b), so umask: -1 passes every bit set. Linux keeps a
    # mask's permission bits and drops the rest (kernel/sys.c, lines
    # 1906 to 1910 at v6.12, mask & S_IRWXUGO), and glibc's umask asks
    # the kernel. Ruby's build compiles with -D_FORTIFY_SOURCE=2
    # (configure.ac's hardenflags), with which bionic's sys/stat.h sends
    # a umask whose argument is not a constant to __umask_chk
    # (libc/include/bits/fortify/stat.h, lines 36 to 47 at 731631f),
    # and that aborts the process for a mask with any bit beyond 0777
    # (libc/bionic/fortify.cpp, lines 400 to 406). These two edits keep
    # the permission bits before the call, as the kernel would.
    def self.process_c_umask(text)
      replace(text, /^(        mode_t oldmask = umask\(mask)\);/, "\\1 & 0777);", "rb_execarg_run_options calls umask with the option's mask")
    end

    def self.file_c_umask(text)
      replace(text, /^(        omask = umask\(NUM2MODET\(argv\[0\]\))\);/, "\\1 & 0777);", "rb_file_s_umask calls umask with its argument")
    end

    def self.thread_pthread_c(text)
      replace(text, /^(rb_thread_reset_fork_lock\(void\)\n\{\n).*?^\}\n/m, "\\1#{RESET_FORK_LOCK}}\n",
        "rb_thread_reset_fork_lock destroys and initializes the lock")
    end

    # Thread#name= names the native thread of a thread that has ended
    # (thread.c, rb_thread_setname, lines 3977 to 3980 at
    # 4.1.0-preview1), whose pthread_t the C library has freed with the
    # thread. bionic looks a pthread_t up among its live threads and,
    # for an app that targets API level 26 or later, aborts on one it
    # does not find (libc/bionic/pthread_internal.cpp,
    # __pthread_internal_find, lines 96 to 125 at 731631f), as
    # pthread_setname_np does (libc/bionic/pthread_setname_np.cpp, line
    # 98). Ruby's master names only a thread that has not ended
    # (ruby/ruby 6fdd452087, [Bug #22471]), which this takes.
    def self.thread_c(text)
      replace(text, /^(    if \(threadptr_initialized\(target_th\) && target_th->has_dedicated_nt)\) \{\n/,
        "\\1 &&\n        target_th->status != THREAD_KILLED) {\n", "rb_thread_setname names the native thread")
    end

    # dir.c reads each entry's type from readdir's d_type only where the
    # C library defines IFTODT (lines 229 to 233 at 4.1.0-preview1), and
    # bionic's dirent.h defines DT_UNKNOWN but not IFTODT
    # (libc/include/dirent.h at 731631f), so Ruby on Android stats every
    # entry a glob reads. That stat is glob_helper's one call that gives
    # fstatat, relative to a base: Dir's descriptor, the entry's path
    # with the base's own path before it (line 3127), where its call for
    # a symbolic link takes the path relative to the base (at_subpath,
    # line 3135), so a Dir opened by a relative path found nothing. glibc
    # defines IFTODT (dirent/dirent.h), and Linux's Ruby takes each
    # entry's type from d_type and makes that stat only for an entry of
    # type DT_UNKNOWN. This defines IFTODT as glibc does, so Android's
    # Ruby reads entries as Linux's does.
    def self.dir_c(text)
      replace(text, /^(#if defined\(IFTODT\) && defined\(DT_UNKNOWN\)\n)/,
        "#if !defined(IFTODT) && defined(DT_UNKNOWN)\n# define IFTODT(mode) (((mode) & 0170000) >> 12)\n#endif\n\\1",
        "dir.c emulates IFTODT where it is missing")
    end

    # $0= and Process.setproctitle write the title over the argv Ruby was
    # started with (missing/setproctitle.c, setproctitle, lines 193 to 232
    # at 4.1.0-preview1, given argv by ruby.c, line 3259), where the
    # kernel reads a process's command line (/proc/PID/cmdline). An
    # Android app's Ruby is a library in a process the zygote forked, and
    # its argv is one fledge_ruby_run allocates, so the title went
    # nowhere the kernel looks. Android names the process by writing the
    # zygote's own argument area: AndroidRuntime::setArgv0 clears it and
    # copies the name in, cut to its length (core/jni/AndroidRuntime.cpp,
    # lines 328 to 347 at android-14.0.0_r1), and hides the call from
    # apps. The kernel names that area in /proc/self/stat (arg_start and
    # arg_end, fields 48 and 49, proc(5)), so where argv[0] is not in it,
    # compat_init_setproctitle's edit points setproctitle there, which
    # then clears and writes it as setArgv0 does. A ruby program the app
    # starts has its argv in its own area, and keeps Ruby's way. Neither
    # renames a thread: setArgv0 names the thread that calls it, Android's
    # main thread, where Ruby's runs on a thread of its own, and Linux's
    # Ruby leaves the kernel's name for its process as it was.
    #
    # An iOS app's Ruby is given an argv fledge_ruby_run allocates too,
    # where Darwin reads a process's arguments from the strings its
    # process started with (sysctl's KERN_PROCARGS2, which ps reads), so
    # the title went nowhere there either (measured in the Simulator,
    # 2026-11-12: ps and KERN_PROCARGS2 still showed the executable's
    # path). Darwin keeps the process's own argv for anyone to find
    # (_NSGetArgc and _NSGetArgv, crt_externs.h, in the iOS SDK), so
    # there compat_init_setproctitle measures that argv instead of the
    # one it was given, and Ruby then writes over the process's own
    # strings, as macOS's Ruby, started by the kernel, does.
    def self.setproctitle_c(text)
      found = replace(text, /^(void\ncompat_init_setproctitle\(int argc, char \*argv\[\]\)\n\{\n)/,
        "#{ARGUMENT_AREA}\n\\1#{PROCESS_ARGUMENTS}", "setproctitle.c defines compat_init_setproctitle")
      replace(found, %r{^(\talloc_environ\[i\] = environ\[i\] = NULL;\n)(#endif /\* SPT_REUSEARGV \*/\n\}\n)},
        "\\1#if defined(__ANDROID__)\n\tfledge_use_process_argument_area(argv[0]);\n#endif\n\\2",
        "compat_init_setproctitle copies environ")
    end

    # The first lines of compat_init_setproctitle on Darwin: the argv the
    # process started with, in place of the one Ruby was given.
    PROCESS_ARGUMENTS = <<~C
      #if ALLOCATE_ENVIRON && defined(__APPLE__)
      \tif (*_NSGetArgv() != NULL && argv != *_NSGetArgv()) {
      \t\targc = *_NSGetArgc();
      \t\targv = *_NSGetArgv();
      \t}
      #endif
    C

    # The C before compat_init_setproctitle that finds an Android
    # process's argument area, and on Darwin the declarations of the
    # process's own argv.
    ARGUMENT_AREA = <<~C
      #if ALLOCATE_ENVIRON && defined(__APPLE__)
      #include <crt_externs.h>
      #endif
      #if ALLOCATE_ENVIRON && defined(__ANDROID__)
      #include <stdint.h>
      #include <stdio.h>
      #include <string.h>
      /* Fledge: where argv[0] is not in the process's own argument area, as
         an Android app's Ruby's is not, the title goes into that area, which
         the kernel names in /proc/self/stat, as Android's setArgv0 puts a
         process's name there. */
      static void
      fledge_use_process_argument_area(const char *argv0)
      {
          char stat[2048];
          unsigned long start, end;
          FILE *file = fopen("/proc/self/stat", "re");
          if (file == NULL) return;
          size_t size = fread(stat, 1, sizeof(stat) - 1, file);
          fclose(file);
          stat[size] = 0;
          char *field = strrchr(stat, ')');
          for (int number = 3; field != NULL && number <= 48; number++) field = strchr(field + 1, ' ');
          if (field == NULL || sscanf(field, "%lu %lu", &start, &end) != 2 || end <= start) return;
          if ((uintptr_t)argv0 >= start && (uintptr_t)argv0 < end) return;
          argv_start = (char *)start;
          argv_len = argv_env_len = end - start;
      }
      #endif
    C

    # rb_fork_ruby's release of the fork lock after fork, at
    # 4.1.0-preview1.
    FORK_UNLOCK = <<~C
              if (
      #if defined(__FreeBSD__)
                  pid != 0 &&
      #endif
                  true) {
                  rb_thread_release_fork_lock();
              }
              if (pid == 0) {
                  rb_thread_reset_fork_lock();
              }
    C

    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Ruby OR BSD-2-Clause
    # SPDX-SnippetCopyrightText: Douglas Eichelberger
    # SPDX-SnippetComment: From ruby/ruby e06b9da3f20455ba4cff99a7821f013b7bdde5de,
    #   "Reset the fork lock in the child without unlocking it" (process.c,
    #   release_fork_lock_after_fork, and thread_pthread.c,
    #   rb_thread_reset_fork_lock).
    #++
    FORK_RESET = <<~C.gsub(/^/, " " * 8)
      if (pid == 0) {
          rb_thread_reset_fork_lock();
      }
      else {
          rb_thread_release_fork_lock();
      }
    C

    RESET_FORK_LOCK = <<~C.gsub(/^/, " " * 4)
      // On macOS the child's copy still counts a thread waiting for this lock
      // at fork: unlocking it leaves kernel state that later waiters hang on,
      // and destroying or initializing it fails with EBUSY.
      rb_thread_fork_rw_lock = (pthread_rwlock_t)PTHREAD_RWLOCK_INITIALIZER;
    C
    #--
    # SPDX-SnippetEnd
    #++

    # The gate's C, before search_required; %<table>s is each gem's
    # extension feature with its gem's full name.
    GATE = <<~C
      /* Fledge: each bundled gem's extension this Ruby links in, by the
         feature it is registered as, with the full name of its gem. */
      static const char *const fledge_gem_extensions[][2] = {
      %<table>s};

      /* Whether the linked extension +feature+ may be found: always, but for
         a gem's, which only while a folder named for its gem is on
         $LOAD_PATH, as RubyGems puts the gem's extension folder there when
         it activates the gem. */
      static int
      fledge_gem_extension_reachable_p(const rb_box_t *box, const char *feature)
      {
          for (size_t i = 0; i < sizeof(fledge_gem_extensions) / sizeof(fledge_gem_extensions[0]); i++) {
              if (strcmp(feature, fledge_gem_extensions[i][0]) != 0) continue;
              const char *gem = fledge_gem_extensions[i][1];
              long length = (long)strlen(gem);
              VALUE load_path = get_expanded_load_path((rb_box_t *)box);
              for (long j = 0; j < RARRAY_LEN(load_path); j++) {
                  VALUE folder = RARRAY_AREF(load_path, j);
                  const char *name = RSTRING_PTR(folder);
                  long size = RSTRING_LEN(folder);
                  if (size > length && name[size - length - 1] == '/' && memcmp(name + size - length, gem, length) == 0) return 1;
              }
              return 0;
          }
          return 1;
      }
    C

    # Writes sys/vnode.h into the folder +stub+, which a build puts first
    # on its include path: the iOS SDK lacks it, and dir.c includes it on
    # Apple systems for the vnode types and file system tags it uses.
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT
    # SPDX-SnippetCopyrightText: 2014 xord.org
    # SPDX-SnippetComment: The stub sys/vnode.h from xord/cruby's Rakefile,
    #   lines 553 to 560, at 11d62c4.
    #++
    VNODE = <<~H
      #ifndef DUMMY_VNODE_H_INCLUDED
      #define DUMMY_VNODE_H_INCLUDED
      enum {VREG = 1, VDIR = 2, VLNK = 5, VT_HFS = 16, VT_CIFS = 23};
      #endif
    H
    #--
    # SPDX-SnippetEnd
    #++

    def self.write_vnode_stub(stub)
      FileUtils.mkdir_p(File.join(stub, "sys"))
      File.write(File.join(stub, "sys", "vnode.h"), VNODE)
    end

    private_class_method def self.replace(text, pattern, replacement, what)
      raise "Ruby's source has changed: an edit expects #{what}, and it does not" unless text.match?(pattern)

      text.sub(pattern, replacement)
    end
  end
end
