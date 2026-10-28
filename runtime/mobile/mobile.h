/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * What the mobile runtimes' C files share: output.c, which forwards
 * standard output and standard error to the system's log, with the file
 * that writes to that log on each system, apple.c (os_log) and android.c
 * (logcat); and fledge_ruby.c, which knows where the runtime's CA
 * certificates are, with android.c, which tells OpenSSL.
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
 * as fit without cutting a UTF-8 character in two.
 */
size_t fledge_log_chunk(const char *text, size_t length);

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

#endif
