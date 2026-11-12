# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "rbconfig"
require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The edits that mend Ruby 4.1.0-preview1 where a phone's C library meets
# a bug of CRuby's that a desktop's does not (doc/contributors/design/phone-runtimes.md,
# "Scripted edits to Ruby's source"), each against the lines of Ruby's
# own files it changes, and each failing loudly when a new Ruby no longer
# has them. Where the bug can be shown on this computer, the edited C is
# compiled with mkmf against this Ruby and run, beside the C as Ruby has
# it.
class RubySourceFixesTest < Minitest::Test
  Edits = RuntimeBuilder::RubySource

  # In an iOS app getgroups fails, and rb_group_member took its -1 for a
  # count, so File::Stat#readable? raised ArgumentError for a file of
  # another group. The edit answers that the process is in no other
  # group, and the check goes on to the bits for others.
  def test_a_failing_getgroups_puts_the_process_in_no_other_group
    assert_equal "    groups = getgroups(0, NULL);\n    if (groups == -1) return FALSE;\n" \
      "    gary = ALLOCV_N(GETGROUPS_T, v, groups);\n", Edits.file_c(GROUP_MEMBER_LINES)
    assert_raises(RuntimeError) { Edits.file_c("    groups = getgroups(0, NULL);\n    if (groups < 0) return FALSE;\n") }
  end

  def test_rb_group_member_answers_false_where_getgroups_fails
    skip "the phones' runtimes are built on macOS and Linux" if Gem.win_platform?
    assert_equal "malloc: possible integer overflow", compile_and_run("member", GROUP_MEMBER_HARNESS, GROUP_MEMBER_SCRIPT)[0, 33]
    assert_equal "false\n", compile_and_run("member", Edits.file_c(GROUP_MEMBER_HARNESS), GROUP_MEMBER_SCRIPT)
  end

  # rb_group_member's lines that count the process's groups, at
  # 4.1.0-preview1.
  GROUP_MEMBER_LINES = "    groups = getgroups(0, NULL);\n    gary = ALLOCV_N(GETGROUPS_T, v, groups);\n"

  # The lines inside an extension of this Ruby's, with a getgroups that
  # fails as an iOS app's does.
  GROUP_MEMBER_HARNESS = <<~C
    #include <ruby.h>
    #include <errno.h>
    #include <unistd.h>
    #define GETGROUPS_T gid_t
    static int fails(int size, GETGROUPS_T *list) { (void)size; (void)list; errno = EINVAL; return -1; }
    #define getgroups fails
    static int
    member(GETGROUPS_T gid)
    {
        int rv = FALSE;
        int groups;
        VALUE v = 0;
        GETGROUPS_T *gary;
        int anum = -1;

    #{GROUP_MEMBER_LINES.chomp}
        anum = getgroups(groups, gary);
        while (--anum >= 0) if (gary[anum] == gid) rv = TRUE;
        if (v) ALLOCV_END(v);
        return rv;
    }
    static VALUE member_p(VALUE self, VALUE gid) { (void)self; return member((GETGROUPS_T)NUM2INT(gid)) ? Qtrue : Qfalse; }
    void Init_member(void) { rb_define_global_function("fledge_group_member?", member_p, 1); }
  C

  GROUP_MEMBER_SCRIPT = <<~RUBY
    require %<extension>s
    begin
      p fledge_group_member?(12_345)
    rescue ArgumentError => e
      puts e.message
    end
  RUBY

  # The child of a fork resets its copy of the fork lock without
  # unlocking it, which bionic refuses for a thread that is not the
  # lock's writer, as Ruby's master does (ruby/ruby e06b9da3f2).
  def test_the_child_of_a_fork_resets_the_fork_lock_without_unlocking_it
    edited = Edits.process_c("        disable_child_handler_fork_parent(&old); /* yes, bad name */\n#{Edits::FORK_UNLOCK}" \
      "        after_fork_ruby(pid);\n")

    assert_includes edited, "        if (pid == 0) {\n            rb_thread_reset_fork_lock();\n        }\n" \
      "        else {\n            rb_thread_release_fork_lock();\n        }\n        after_fork_ruby(pid);\n"
    refute_includes edited, "__FreeBSD__"
    assert_raises(RuntimeError) { Edits.process_c("        rb_thread_release_fork_lock();\n") }
  end

  def test_resetting_the_fork_lock_assigns_it_a_fresh_lock
    text = "void\nrb_thread_reset_fork_lock(void)\n{\n    int r;\n" \
      "    if ((r = pthread_rwlock_destroy(&rb_thread_fork_rw_lock))) {\n        rb_bug_errno(\"pthread_rwlock_destroy\", r);\n    }\n" \
      "\n    if ((r = pthread_rwlock_init(&rb_thread_fork_rw_lock, NULL))) {\n        rb_bug_errno(\"pthread_rwlock_init\", r);\n    }\n" \
      "}\n\nvoid *\nrb_thread_prevent_fork(void *(*func)(void *), void *data)\n{\n    int r;\n}\n"

    edited = Edits.thread_pthread_c(text)
    assert_includes edited, "{\n#{Edits::RESET_FORK_LOCK}}\n\nvoid *\nrb_thread_prevent_fork("
    assert_includes Edits::RESET_FORK_LOCK, "    rb_thread_fork_rw_lock = (pthread_rwlock_t)PTHREAD_RWLOCK_INITIALIZER;\n"
    refute_includes edited, "pthread_rwlock_destroy"
    assert_includes edited, "rb_thread_prevent_fork(void *(*func)(void *), void *data)\n{\n    int r;\n}\n"
    assert_raises(RuntimeError) { Edits.thread_pthread_c("rb_thread_reset_fork_lock(int fd)\n{\n}\n") }
  end

  # Thread#name= names a native thread only while its thread has not
  # ended, as Ruby's master does (ruby/ruby 6fdd452087): bionic aborts
  # on the pthread_t of one that has.
  def test_naming_a_thread_that_has_ended_leaves_its_native_thread_alone
    text = "    target_th->name = name;\n    if (threadptr_initialized(target_th) && target_th->has_dedicated_nt) {\n" \
      "        native_set_another_thread_name(target_th->nt->thread_id, name);\n"

    assert_includes Edits.thread_c(text), "    if (threadptr_initialized(target_th) && target_th->has_dedicated_nt &&\n" \
      "        target_th->status != THREAD_KILLED) {\n        native_set_another_thread_name("
    assert_raises(RuntimeError) { Edits.thread_c("    if (target_th->has_dedicated_nt) {\n") }
  end

  # bionic has d_type but no IFTODT, so Ruby's dir.c stats each entry a
  # glob reads, and one of those stats takes the wrong path against a
  # base: Dir. The edit defines IFTODT as glibc does, so dir.c reads
  # d_type as on Linux.
  def test_dir_c_reads_each_entrys_type_from_d_type_where_the_c_library_has_no_iftodt
    assert_includes Edits.dir_c(IFTODT_LINES), "#if !defined(IFTODT) && defined(DT_UNKNOWN)\n" \
      "# define IFTODT(mode) (((mode) & 0170000) >> 12)\n#endif\n#{IFTODT_LINES}"
    assert_raises(RuntimeError) { Edits.dir_c("#ifdef IFTODT\n") }
  end

  def test_the_iftodt_it_defines_gives_each_type_as_readdir_names_it
    skip "the phones' runtimes are built on macOS and Linux" if Gem.win_platform?
    assert_equal "[1]\n", compile_and_run("iftodt", format(IFTODT_HARNESS, lines: IFTODT_LINES), IFTODT_SCRIPT)
    assert_equal "[0, true, true, true, true]\n",
      compile_and_run("iftodt", format(IFTODT_HARNESS, lines: Edits.dir_c(IFTODT_LINES)), IFTODT_SCRIPT)
  end

  # dir.c's choice, at 4.1.0-preview1, lines 229 to 233.
  IFTODT_LINES = "#if defined(IFTODT) && defined(DT_UNKNOWN)\n# define EMULATE_IFTODT 0\n#else\n# define EMULATE_IFTODT 1\n#endif\n"

  # The choice in an extension of this Ruby's, on a C library made to
  # lack IFTODT, as bionic does.
  IFTODT_HARNESS = <<~C
    #include <ruby.h>
    #include <dirent.h>
    #include <sys/stat.h>
    #undef IFTODT
    #define TRUTH(test) ((test) ? Qtrue : Qfalse)
    %<lines>s
    static VALUE types(VALUE self) {
        (void)self;
    #if EMULATE_IFTODT
        return rb_ary_new_from_args(1, INT2FIX(EMULATE_IFTODT));
    #else
        return rb_ary_new_from_args(5, INT2FIX(EMULATE_IFTODT), TRUTH(IFTODT(S_IFDIR) == DT_DIR),
            TRUTH(IFTODT(S_IFREG) == DT_REG), TRUTH(IFTODT(S_IFLNK) == DT_LNK), TRUTH(IFTODT(S_IFIFO) == DT_FIFO));
    #endif
    }
    void Init_iftodt(void) { rb_define_global_function("fledge_iftodt", types, 0); }
  C

  IFTODT_SCRIPT = "require %<extension>s\np fledge_iftodt\n"

  private def compile_and_run(name, source, script)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "#{name}.c"), source)
      sh(dir, RbConfig.ruby, "-rmkmf", "-e", "create_makefile(#{name.dump})")
      sh(dir, "make")
      sh(dir, RbConfig.ruby, "-e", format(script, extension: File.join(dir, name).dump))
    end
  end

  private def sh(dir, *command)
    out, status = Open3.capture2e(*command, chdir: dir)
    assert status.success?, "#{command.join(' ')} failed:\n#{out}"
    out
  end
end
