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
#include <string.h>
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

/* Writes the line of length bytes to the log, in entries that fit. */
static void
log_line(int error, const char *line, size_t length)
{
    size_t offset = 0;

    do {
        size_t chunk = fledge_log_chunk(line + offset, length - offset);
        fledge_log_write(error, line + offset, chunk);
        offset += chunk;
    } while (offset < length);
}

/*
 * Reads the pipe with read(2), not stdio, so that the thread holds no
 * FILE's lock while it waits: glibc's exit() takes every stream's lock to
 * flush it, and would wait for ever on a thread blocked in getline.
 */
static void *
forward(void *argument)
{
    intptr_t value = (intptr_t)argument;
    int error = (int)(value & 1);
    int fd = (int)(value >> 1);
    size_t capacity = 4096, length = 0;
    char *line = malloc(capacity);
    ssize_t count;

    if (line == NULL) return NULL;
    while ((count = read(fd, line + length, capacity - length)) != 0) {
        if (count < 0) {
            if (errno == EINTR) continue;
            break;
        }
        length += (size_t)count;
        char *start = line, *end;
        while ((end = memchr(start, '\n', length - (size_t)(start - line))) != NULL) {
            log_line(error, start, (size_t)(end - start));
            start = end + 1;
        }
        length -= (size_t)(start - line);
        memmove(line, start, length);
        if (length == capacity) {
            char *grown = realloc(line, capacity * 2);
            if (grown == NULL) {
                log_line(error, line, length);
                length = 0;
                continue;
            }
            line = grown;
            capacity *= 2;
        }
    }
    if (length > 0) log_line(error, line, length);
    free(line);
    close(fd);
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
