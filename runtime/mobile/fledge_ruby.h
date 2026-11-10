/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * Fledge's embedding API for Ruby on iOS, iPadOS, and Android (ADR 061;
 * doc/contributors/design/phones.md, "The embedding API").
 *
 * A phone runs no program of Fledge's own: the app is the developer's,
 * or a framework's (Lota's SDL_main, Tokra's Tauri host), and Ruby is a
 * library inside it. These two functions are what such a host needs to
 * run an app's Ruby as Fledge's desktop launcher does:
 *
 *   fledge_ruby_forward_output("com.example.MyCoolApp");
 *   int status = fledge_ruby_run(root, script, argc, argv);
 *
 * where root is the folder holding the runtime's lib/ruby and libexec/
 * (on iOS, copied into the app's bundle from the XCFramework slice it
 * was built for; on Android, unpacked from the app's assets by
 * org.setdef.fledge.FledgeRuby). On Android, call them through that
 * Java class, which also unpacks the folder.
 */

#ifndef FLEDGE_RUBY_H
#define FLEDGE_RUBY_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The statuses fledge_ruby_run and fledge_ruby_run_app return when they
 * cannot start Ruby, from sysexits(3), as Fledge's launcher exits (ADR
 * 002): EX_NOINPUT for an app whose fledge.cfg or program is missing,
 * and EX_SOFTWARE for anything else.
 */
enum { FLEDGE_RUBY_NO_APP = 66, FLEDGE_RUBY_SOFTWARE = 70 };

/*
 * Runs the Ruby program script, a file, with the argc strings of argv
 * as its ARGV, on the calling thread, and returns its exit status, as
 * ruby script ARGS would. Ruby's prefix is root: its standard library,
 * default gems, and bundled gems are root/lib/ruby, and OpenSSL trusts
 * the certificate authorities in root/libexec/cert.pem (SSL_CERT_FILE,
 * unless the environment names another). A bare C locale becomes a
 * UTF-8 one, as under the desktop launcher. When standard output is not
 * a terminal, as on a phone it never is, $stdout is in sync mode before
 * the program runs, so that each line reaches the log or the developer
 * tool reading it when it is printed, as it reaches a terminal, rather
 * than when the program ends.
 *
 * Ruby boots once per process, so a second call returns
 * FLEDGE_RUBY_SOFTWARE at once. Ruby needs the deep stack a process's
 * main thread has: on Android, call it on a thread made with a large
 * stack, as org.setdef.fledge.FledgeRuby.start does.
 */
int fledge_ruby_run(const char *root, const char *script, int argc, char *const *argv);

/*
 * Runs the app fledge build put in root, as Fledge's desktop launcher
 * runs one (ADR 061): root/fledge.cfg names its program, in root/app,
 * and, for an app with a Gemfile, the Gemfile whose gems Bundler sets up
 * before the program runs, as bundle exec would, with Bundler's settings
 * from root/app/.bundle/config. Otherwise as fledge_ruby_run, whose
 * statuses it returns, and FLEDGE_RUBY_NO_APP when fledge.cfg or the
 * program is missing.
 */
int fledge_ruby_run_app(const char *root, int argc, char *const *argv);

/*
 * Tells Ruby that the extension whose Init function is init is linked
 * into this process, so that require "feature" runs init instead of
 * looking for a file, which a phone's Ruby never loads (ADR 022).
 * feature is the name the extension's extconf.rb gives create_makefile,
 * such as "greeter/greeter", with no ".so". Call it before fledge_ruby_run
 * or fledge_ruby_run_app, from a constructor or the host's startup: Ruby
 * registers every extension added by then once it has booted, before the
 * program runs, and an extension added after Ruby has started is never
 * registered. The library fledge build writes for an app's gems
 * (fledge_extensions.c) calls it for each of them. Returns 0, or -1 with
 * errno set: EINVAL for a missing or empty name or function, EALREADY
 * once Ruby has started, ENOMEM.
 */
int fledge_ruby_add_extension(const char *feature, void (*init)(void));

/*
 * Sends what this process writes to standard output and standard error
 * to the system's log, line by line, which iOS and Android otherwise
 * discard: to os_log with tag as its subsystem on Apple systems, and to
 * logcat with tag as its tag on Android, where standard error's lines
 * are warnings. Name the app, as by its bundle identifier or package.
 * A line longer than a log entry holds goes as several entries in a row.
 * Each of Ruby's lines arrives as it is printed (fledge_ruby_run).
 * When the log already copies its entries to standard error, as Apple's
 * does for a developer tool that sets OS_ACTIVITY_DT_MODE, it leaves the
 * streams to that tool. Returns 0, or -1 with errno set.
 */
int fledge_ruby_forward_output(const char *tag);

#ifdef __cplusplus
}
#endif

#endif
