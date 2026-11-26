/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
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
 * entry holds goes as several entries in a row (fledge_log_chunk), and a
 * NUL byte goes as a stand-in a log can carry (NUL_FORM).
 *
 * When a developer tool holds a stream, as `devicectl device process
 * launch --console` holds an iPhone app's two (a pipe or a terminal in
 * place of the /dev/null a launch from the Home Screen gives), each line
 * goes to the tool as well as to the log, through the descriptor the
 * stream was before the pipe replaced it: the pipe would otherwise take
 * the console's only source away, and the console showed none of the
 * app's output unless the tool also set OS_ACTIVITY_DT_MODE.
 *
 * When the log itself copies each entry to standard error for a
 * developer tool (fledge_log_echoes), the tool already reads the
 * streams, and forwarding standard error would send each entry back to
 * the log, which would copy it to the pipe again, until the pipe filled
 * and the app blocked writing to it. Then the streams are left alone,
 * as CPython's iOS support leaves the process's own descriptors: it
 * replaces only Python's sys.stdout and sys.stderr.
 */

#include "fledge_ruby.h"
#include "mobile.h"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Whitespace the unified log trims from the end of an entry. */
static int
is_blank(char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\v' || c == '\f';
}

size_t
fledge_log_chunk(const char *text, size_t length)
{
    if (length <= FLEDGE_LOG_ENTRY_MAX) return length;

    size_t end = FLEDGE_LOG_ENTRY_MAX;
    /* A UTF-8 continuation byte is 10xxxxxx; back up to the start of its character. */
    while (end > 0 && ((unsigned char)text[end] & 0xC0) == 0x80) end--;
    /*
     * The unified log drops an entry's trailing whitespace (log show
     * prints "a " as "a"), so a cut after a space would lose it from the
     * line the entries make; cut before the whitespace instead, which
     * begins the next entry, where the log keeps it.
     */
    size_t word = end;
    while (word > 0 && is_blank(text[word - 1])) word--;
    if (word > 0) end = word;
    return end > 0 ? end : FLEDGE_LOG_ENTRY_MAX;
}

/* Writes the line of length bytes to the log, in entries that fit. */
static void
log_entries(int error, const char *line, size_t length)
{
    size_t offset = 0;

    do {
        size_t chunk = fledge_log_chunk(line + offset, length - offset);
        fledge_log_write(error, line + offset, chunk);
        offset += chunk;
    } while (offset < length);
}

/*
 * What a NUL byte goes as. Each entry is a C string to both logs
 * (__android_log_print's "%.*s" and os_log's stop at a NUL whatever the
 * length), so a NUL byte in the line would cut the entry short and lose
 * the rest. On Android it goes as the two bytes 0xC0 0x80, "modified
 * UTF-8", as CPython's Android streams write it (Lib/_android_support.py:
 * "Encode null bytes using modified UTF-8 to avoid them truncating the
 * message") and as Android's JNI writes it; logcat carries them. os_log
 * does not: an entry with bytes that are no UTF-8 is lost whole, shown as
 * "<compose failure [illegible log arguments]>" (iOS 26.1 Simulator). So
 * on Apple's systems it goes as U+2400, SYMBOL FOR NULL, which is valid
 * UTF-8 and reads as what it stands for.
 */
#ifdef __APPLE__
#define NUL_FORM "\xE2\x90\x80"
#else
#define NUL_FORM "\xC0\x80"
#endif

/* Writes the line of length bytes to the log, each NUL as NUL_FORM. */
static void
log_line(int error, const char *line, size_t length)
{
    const size_t form = sizeof NUL_FORM - 1;

    if (memchr(line, '\0', length) != NULL) {
        char *escaped = malloc(length * form);
        if (escaped != NULL) {
            size_t size = 0;
            for (size_t index = 0; index < length; index++) {
                if (line[index] == '\0') {
                    memcpy(escaped + size, NUL_FORM, form);
                    size += form;
                } else {
                    escaped[size++] = line[index];
                }
            }
            log_entries(error, escaped, size);
            free(escaped);
            return;
        }
    }
    log_entries(error, line, length);
}

/* What a forwarding thread reads, and where its lines go besides the log. */
struct stream {
    int fd;
    int error;
    int console; /* a descriptor a developer tool reads, or -1 */
};

/* Writes all of the length bytes of text to the descriptor console, giving it up for good when a write fails. */
static void
write_console(int *console, const char *text, size_t length)
{
    while (*console >= 0 && length > 0) {
        ssize_t count = write(*console, text, length);
        if (count < 0) {
            if (errno == EINTR) continue;
            close(*console);
            *console = -1;
            return;
        }
        text += count;
        length -= (size_t)count;
    }
}

/* Sends the line of length bytes, and its newline when newline is nonzero, to the console and the log. */
static void
emit(struct stream *stream, const char *line, size_t length, int newline)
{
    /* The newline is the byte after the line, so one write carries both. */
    write_console(&stream->console, line, length + (newline ? 1 : 0));
    log_line(stream->error, line, length);
}

/*
 * Reads the pipe with read(2), not stdio, so that the thread holds no
 * FILE's lock while it waits: glibc's exit() takes every stream's lock to
 * flush it, and would wait for ever on a thread blocked in getline.
 */
static void *
forward(void *argument)
{
    struct stream *stream = argument;
    int fd = stream->fd;
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
            emit(stream, start, (size_t)(end - start), 1);
            start = end + 1;
        }
        length -= (size_t)(start - line);
        memmove(line, start, length);
        if (length == capacity) {
            char *grown = realloc(line, capacity * 2);
            if (grown == NULL) {
                emit(stream, line, length, 0);
                length = 0;
                continue;
            }
            line = grown;
            capacity *= 2;
        }
    }
    if (length > 0) emit(stream, line, length, 0);
    free(line);
    close(fd);
    if (stream->console >= 0) close(stream->console);
    free(stream);
    return NULL;
}

/*
 * A copy of descriptor fd when a developer tool may read what it
 * carries, as one may unless it is closed or is the null device, which is
 * where a launch from the Home Screen points a phone app's streams; else
 * -1.
 */
static int
console_of(int fd)
{
    struct stat have, null;
    int copy = dup(fd);

    if (copy < 0) return -1;
    if (fstat(copy, &have) != 0 ||
        (S_ISCHR(have.st_mode) && stat("/dev/null", &null) == 0 && have.st_rdev == null.st_rdev)) {
        close(copy);
        return -1;
    }
#ifdef F_SETNOSIGPIPE
    /* A tool that ends while the app runs must not end the app with SIGPIPE. */
    fcntl(copy, F_SETNOSIGPIPE, 1);
#endif
    return copy;
}

/* Makes descriptor fd the write end of a pipe a new thread forwards. */
static int
forward_descriptor(int fd, int error)
{
    int ends[2];
    pthread_t thread;
    struct stream *stream = malloc(sizeof *stream);

    if (stream == NULL) return -1;
    if (pipe(ends) != 0) {
        free(stream);
        return -1;
    }
    stream->console = console_of(fd);
    if (dup2(ends[1], fd) < 0) {
        int saved = errno;
        close(ends[0]);
        close(ends[1]);
        if (stream->console >= 0) close(stream->console);
        free(stream);
        errno = saved;
        return -1;
    }
    close(ends[1]);
    stream->fd = ends[0];
    stream->error = error;
    int status = pthread_create(&thread, NULL, forward, stream);
    if (status != 0) {
        close(ends[0]);
        if (stream->console >= 0) close(stream->console);
        free(stream);
        errno = status;
        return -1;
    }
    pthread_detach(thread);
    return 0;
}

int
fledge_ruby_forward_output(const char *tag)
{
    if (fledge_log_echoes()) return 0;
    if (fledge_log_open(tag) != 0) return -1;
    fflush(stdout);
    fflush(stderr);
    if (forward_descriptor(STDOUT_FILENO, 0) != 0 || forward_descriptor(STDERR_FILENO, 1) != 0) return -1;
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    return 0;
}
