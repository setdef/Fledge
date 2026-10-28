/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Standard output and standard error, forwarded to the system's log
 * (fledge_ruby.h, fledge_ruby_forward_output).
 *
 * iOS and Android discard what an app writes to its standard streams
 * unless a debugger holds them, so a puts would go nowhere. As the
 * mobile spike's hosts did, and as CPython's iOS and Android support
 * does with its own streams, each stream becomes the write end of a
 * pipe, and a thread of its own reads the other end line by line and
 * writes each line to the log: standard error's as errors, so a
 * developer reading the log sees which is which. A line longer than an
 * entry holds goes as several entries in a row (fledge_log_chunk).
 */

#include "fledge_ruby.h"
#include "mobile.h"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

size_t
fledge_log_chunk(const char *text, size_t length)
{
    if (length <= FLEDGE_LOG_ENTRY_MAX) return length;

    size_t end = FLEDGE_LOG_ENTRY_MAX;
    /* A UTF-8 continuation byte is 10xxxxxx; back up to the start of its character. */
    while (end > 0 && ((unsigned char)text[end] & 0xC0) == 0x80) end--;
    return end > 0 ? end : FLEDGE_LOG_ENTRY_MAX;
}

static void *
forward(void *argument)
{
    intptr_t value = (intptr_t)argument;
    int error = (int)(value & 1);
    FILE *stream = fdopen((int)(value >> 1), "r");
    char *line = NULL;
    size_t capacity = 0;
    ssize_t count;

    if (stream == NULL) return NULL;
    while ((count = getline(&line, &capacity, stream)) >= 0) {
        size_t length = (size_t)count;
        if (length > 0 && line[length - 1] == '\n') length--;
        size_t offset = 0;
        do {
            size_t chunk = fledge_log_chunk(line + offset, length - offset);
            fledge_log_write(error, line + offset, chunk);
            offset += chunk;
        } while (offset < length);
    }
    free(line);
    fclose(stream);
    return NULL;
}

/* Makes descriptor fd the write end of a pipe a new thread forwards. */
static int
forward_descriptor(int fd, int error)
{
    int ends[2];
    pthread_t thread;

    if (pipe(ends) != 0) return -1;
    if (dup2(ends[1], fd) < 0) {
        int saved = errno;
        close(ends[0]);
        close(ends[1]);
        errno = saved;
        return -1;
    }
    close(ends[1]);
    int status = pthread_create(&thread, NULL, forward, (void *)(((intptr_t)ends[0] << 1) | error));
    if (status != 0) {
        close(ends[0]);
        errno = status;
        return -1;
    }
    pthread_detach(thread);
    return 0;
}

int
fledge_ruby_forward_output(const char *tag)
{
    if (fledge_log_open(tag) != 0) return -1;
    fflush(stdout);
    fflush(stderr);
    if (forward_descriptor(STDOUT_FILENO, 0) != 0 || forward_descriptor(STDERR_FILENO, 1) != 0) return -1;
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    return 0;
}
