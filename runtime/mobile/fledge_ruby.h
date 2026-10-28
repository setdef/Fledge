/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Fledge's embedding API for Ruby on iOS, iPadOS, and Android (ADR 011,
 * section 5).
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
 * The status fledge_ruby_run returns when it cannot start Ruby, from
 * sysexits(3), as Fledge's launcher exits (ADR 002).
 */
enum { FLEDGE_RUBY_SOFTWARE = 70 };

/*
 * Runs the Ruby program script, a file, with the argc strings of argv
 * as its ARGV, on the calling thread, and returns its exit status, as
 * ruby script ARGS would. Ruby's prefix is root: its standard library,
 * default gems, and bundled gems are root/lib/ruby, and OpenSSL trusts
 * the certificate authorities in root/libexec/cert.pem (SSL_CERT_FILE,
 * unless the environment names another). A bare C locale becomes a
 * UTF-8 one, as under the desktop launcher.
 *
 * Ruby boots once per process, so a second call returns
 * FLEDGE_RUBY_SOFTWARE at once. Ruby needs the deep stack a process's
 * main thread has: on Android, call it on a thread made with a large
 * stack, as org.setdef.fledge.FledgeRuby.start does.
 */
int fledge_ruby_run(const char *root, const char *script, int argc, char *const *argv);

/*
 * Sends what this process writes to standard output and standard error
 * to the system's log, line by line, which iOS and Android otherwise
 * discard: to os_log with tag as its subsystem on Apple systems, and to
 * logcat with tag as its tag on Android, where standard error's lines
 * are warnings. Name the app, as by its bundle identifier or package.
 * A line longer than a log entry holds goes as several entries in a row.
 * Returns 0, or -1 with errno set.
 */
int fledge_ruby_forward_output(const char *tag);

#ifdef __cplusplus
}
#endif

#endif
