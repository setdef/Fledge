/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * The computer's own libfuse, for an AppImage's runtime (ADR 009).
 *
 * AppImage's type 2 runtime links libfuse 3 statically, and libfuse is
 * LGPL-2.1: Fledge puts nothing LGPL into an app but as a separate
 * library a person can replace (decision 8; AGENTS.md, Licensing). So
 * Fledge's build of the runtime links no libfuse at all. It loads the
 * libfuse the computer already has, libfuse3.so.3, the library every
 * FUSE 3 installation ships beside fusermount3, when it is about to
 * mount, and only then, as AppImageKit's old runtime loaded libfuse.so.2.
 * A computer without one runs the AppImage by extracting it instead
 * (runtime.patch), so the runtime starts, extracts, and prints its help
 * without FUSE.
 *
 * Each function below stands in for libfuse's own, with the prototype
 * fuse_lowlevel.h gives it, and calls the one dlvsym found at the symbol
 * version of the headers the runtime was compiled against (libfuse
 * 3.14's fuse_versionscript): FUSE_3.0 for all but fuse_parse_cmdline,
 * whose struct fuse_cmdline_opts changed at FUSE_3.12. The headers
 * contribute only declarations and structure layouts, which LGPL-2.1,
 * section 5, leaves outside the library.
 */

#define _GNU_SOURCE
#define FUSE_USE_VERSION 31

#include <dlfcn.h>
#include <fuse_lowlevel.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#ifndef LIBFUSE_BUILT_WITH_VERSIONED_SYMBOLS
#error "fuse.c needs the headers of a libfuse built with versioned symbols, as Ubuntu and Debian build it"
#endif

#define FLEDGE_FUSE_FUNCTIONS(X)                                                                                       \
    X(fuse_add_direntry, "FUSE_3.0")                                                                                   \
    X(fuse_cmdline_help, "FUSE_3.0")                                                                                   \
    X(fuse_daemonize, "FUSE_3.0")                                                                                      \
    X(fuse_opt_free_args, "FUSE_3.0")                                                                                  \
    X(fuse_opt_parse, "FUSE_3.0")                                                                                      \
    X(fuse_parse_cmdline, "FUSE_3.12")                                                                                 \
    X(fuse_remove_signal_handlers, "FUSE_3.0")                                                                         \
    X(fuse_reply_attr, "FUSE_3.0")                                                                                     \
    X(fuse_reply_buf, "FUSE_3.0")                                                                                      \
    X(fuse_reply_entry, "FUSE_3.0")                                                                                    \
    X(fuse_reply_err, "FUSE_3.0")                                                                                      \
    X(fuse_reply_none, "FUSE_3.0")                                                                                     \
    X(fuse_reply_open, "FUSE_3.0")                                                                                     \
    X(fuse_reply_readlink, "FUSE_3.0")                                                                                 \
    X(fuse_reply_statfs, "FUSE_3.0")                                                                                   \
    X(fuse_reply_xattr, "FUSE_3.0")                                                                                    \
    X(fuse_req_userdata, "FUSE_3.0")                                                                                   \
    X(fuse_session_destroy, "FUSE_3.0")                                                                                \
    X(fuse_session_loop, "FUSE_3.0")                                                                                   \
    X(fuse_session_mount, "FUSE_3.0")                                                                                  \
    X(fuse_session_new, "FUSE_3.0")                                                                                    \
    X(fuse_session_unmount, "FUSE_3.0")                                                                                \
    X(fuse_set_signal_handlers, "FUSE_3.0")

#define FLEDGE_FUSE_POINTER(name, version) static __typeof__(name) *fledge_##name;
FLEDGE_FUSE_FUNCTIONS(FLEDGE_FUSE_POINTER)

bool fledge_fuse_usable(void);

/*
 * Whether this computer can mount the AppImage: it has a FUSE device
 * this person may open, and a libfuse 3 with every function the runtime
 * calls. Loads that libfuse the first time.
 */
bool
fledge_fuse_usable(void)
{
    static int loaded = -1;

    if (loaded != -1) return loaded == 1;
    loaded = 0;
    if (access("/dev/fuse", R_OK | W_OK) != 0) return false;

    void *library = dlopen("libfuse3.so.3", RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) return false;

    /* dlvsym returns an object pointer; POSIX's dlsym(3) says to copy it
     * into the function pointer, which ISO C does not let a cast do. */
#define FLEDGE_FUSE_LOAD(name, version)                                                                                \
    symbol = dlvsym(library, #name, version);                                                                          \
    if (symbol == NULL) return false;                                                                                  \
    memcpy(&fledge_##name, &symbol, sizeof symbol);
    void *symbol;
    FLEDGE_FUSE_FUNCTIONS(FLEDGE_FUSE_LOAD)

    loaded = 1;
    return true;
}

size_t
fuse_add_direntry(fuse_req_t req, char *buf, size_t bufsize, const char *name, const struct stat *stbuf, off_t off)
{
    return fledge_fuse_add_direntry(req, buf, bufsize, name, stbuf, off);
}

void
fuse_cmdline_help(void)
{
    fledge_fuse_cmdline_help();
}

int
fuse_daemonize(int foreground)
{
    return fledge_fuse_daemonize(foreground);
}

void
fuse_opt_free_args(struct fuse_args *args)
{
    fledge_fuse_opt_free_args(args);
}

int
fuse_opt_parse(struct fuse_args *args, void *data, const struct fuse_opt opts[], fuse_opt_proc_t proc)
{
    return fledge_fuse_opt_parse(args, data, opts, proc);
}

int
fuse_parse_cmdline(struct fuse_args *args, struct fuse_cmdline_opts *opts)
{
    return fledge_fuse_parse_cmdline(args, opts);
}

void
fuse_remove_signal_handlers(struct fuse_session *se)
{
    fledge_fuse_remove_signal_handlers(se);
}

int
fuse_reply_attr(fuse_req_t req, const struct stat *attr, double attr_timeout)
{
    return fledge_fuse_reply_attr(req, attr, attr_timeout);
}

int
fuse_reply_buf(fuse_req_t req, const char *buf, size_t size)
{
    return fledge_fuse_reply_buf(req, buf, size);
}

int
fuse_reply_entry(fuse_req_t req, const struct fuse_entry_param *e)
{
    return fledge_fuse_reply_entry(req, e);
}

int
fuse_reply_err(fuse_req_t req, int err)
{
    return fledge_fuse_reply_err(req, err);
}

void
fuse_reply_none(fuse_req_t req)
{
    fledge_fuse_reply_none(req);
}

int
fuse_reply_open(fuse_req_t req, const struct fuse_file_info *fi)
{
    return fledge_fuse_reply_open(req, fi);
}

int
fuse_reply_readlink(fuse_req_t req, const char *link)
{
    return fledge_fuse_reply_readlink(req, link);
}

int
fuse_reply_statfs(fuse_req_t req, const struct statvfs *stbuf)
{
    return fledge_fuse_reply_statfs(req, stbuf);
}

int
fuse_reply_xattr(fuse_req_t req, size_t count)
{
    return fledge_fuse_reply_xattr(req, count);
}

void *
fuse_req_userdata(fuse_req_t req)
{
    return fledge_fuse_req_userdata(req);
}

void
fuse_session_destroy(struct fuse_session *se)
{
    fledge_fuse_session_destroy(se);
}

int
fuse_session_loop(struct fuse_session *se)
{
    return fledge_fuse_session_loop(se);
}

int
fuse_session_mount(struct fuse_session *se, const char *mountpoint)
{
    return fledge_fuse_session_mount(se, mountpoint);
}

struct fuse_session *
fuse_session_new(struct fuse_args *args, const struct fuse_lowlevel_ops *op, size_t op_size, void *userdata)
{
    return fledge_fuse_session_new(args, op, op_size, userdata);
}

void
fuse_session_unmount(struct fuse_session *se)
{
    fledge_fuse_session_unmount(se);
}

int
fuse_set_signal_handlers(struct fuse_session *se)
{
    return fledge_fuse_set_signal_handlers(se);
}
