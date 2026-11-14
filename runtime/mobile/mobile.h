/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * What the mobile runtimes' C files share: output.c, which forwards
 * standard output and standard error to the system's log, with the file
 * that writes to that log on each system, apple.c (os_log) and android.c
 * (logcat); fledge_ruby.c, which knows where the runtime's CA
 * certificates are, with android.c, which tells OpenSSL; and the
 * runtime's ruby program on Android, which fledge_ruby.c runs and
 * android.c finds and links.
 */

#ifndef FLEDGE_MOBILE_H
#define FLEDGE_MOBILE_H

#include <stddef.h>

/*
 * The most bytes of a line one log entry carries. logcat cuts an entry
 * at about 4,000 bytes (LOGGER_ENTRY_MAX_PAYLOAD, 4,068, less its tag),
 * and the unified log may shorten one past 1,024, so lines are sent in
 * entries of at most this many bytes.
 */
#define FLEDGE_LOG_ENTRY_MAX 1000

/*
 * How many of the length bytes of text the next log entry carries: all
 * of them when they fit in FLEDGE_LOG_ENTRY_MAX, and otherwise as many
 * as fit without cutting a UTF-8 character in two or ending in
 * whitespace, which the unified log trims from an entry's end.
 */
size_t fledge_log_chunk(const char *text, size_t length);

/*
 * Nonzero when the system's log already copies each entry to standard
 * error, for a developer tool that reads the app's streams (apple.c,
 * android.c): forwarding standard error to the log would then feed the
 * log its own entries.
 */
int fledge_log_echoes(void);

/* Opens the system's log for the app named tag (apple.c, android.c). */
int fledge_log_open(const char *tag);

/*
 * Writes one entry of length bytes of text to the system's log, as an
 * error or warning when error is nonzero (standard error's lines).
 */
void fledge_log_write(int error, const char *text, size_t length);

/*
 * The runtime's CA certificates, ROOT/libexec/cert.pem, once
 * fledge_ruby_run has found them, or NULL.
 */
const char *fledge_ruby_certificates(void);

/*
 * Makes root/bin/ruby, where RbConfig.ruby looks, a link to the
 * runtime's ruby program, where the system lets an app run one, before
 * Ruby boots in the app (android.c, ADR 082). iOS lets no app run a
 * program, so apple.c does nothing.
 */
void fledge_ruby_link_program(const char *root);

/*
 * Makes each path under root that root/fledge.links lists for abi a link
 * to the library it names in folder, the app's native library folder,
 * whenever it is not that link already, and removes the link of a
 * library folder lacks (library_links.c). Returns how many lines it
 * could not link, each said on standard error; none without the list.
 */
int fledge_link_libraries(const char *root, const char *folder, const char *abi);

/*
 * The main function of the runtime's ruby program, with Ruby's prefix
 * at root (fledge_ruby.c, ADR 082): Ruby's main.c, with the locale and
 * the certificates as fledge_ruby_run has them, and the extensions an
 * app links registered; and, when its first argument is the program
 * root/fledge.cfg names, fledge_ruby_run_app with the arguments after
 * it, as the desktop's bin/ruby hands an app's program to its launcher
 * (ADR 096).
 */
int fledge_ruby_main(const char *root, int argc, char **argv);

/*
 * The main function of the runtime's ruby program on Android, which
 * runtime/mobile/ruby_program.c calls: finds the root it was run from
 * and the app's extensions, then runs fledge_ruby_main (android.c).
 */
int fledge_ruby_program_main(int argc, char **argv);

#endif
