/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The Android half of the embedding API: the system log, logcat, where
 * standard output's lines are information and standard error's warnings,
 * as CPython's Android support logs them; and the JNI functions through
 * which org.setdef.fledge.FledgeRuby (runtime/mobile/android/) calls
 * fledge_ruby.h.
 *
 * Java's strings reach C as "modified UTF-8" through GetStringUTFChars,
 * which writes a character outside Unicode's first plane as two
 * three-byte halves, so a path or argument with an emoji in it would not
 * be the bytes Ruby expects. The Java class sends each string as its
 * UTF-8 bytes instead, all of them in one array, each followed by a NUL.
 *
 * And OpenSSL reads no environment variable in an Android app: it reads
 * them only through ossl_safe_getenv, which refuses them in a process
 * whose AT_SECURE is set (crypto/uid.c, OPENSSL_issetugid, at 3.6.5),
 * and every app inherits AT_SECURE from zygote, which Android starts in
 * an SELinux domain of its own. So PORTABLE_RUBY_SSL_CERT_FILE, which
 * openssl.rb sets and OpenSSL reads on iOS, as on a desktop
 * (tasks/runtime_builder/certificates.rb), goes unread by OpenSSL, which
 * would trust only its compiled-in file, the build machine's. The
 * runtime's library is linked with the linker's own
 * --wrap=X509_get_default_cert_file (tasks/runtime_builder/android.rb),
 * which sends OpenSSL's every call of that function here, so its default
 * file is the one that variable names, with getenv, which AT_SECURE does
 * not stop: SSL_CERT_FILE's, or else the runtime's CA certificates, as
 * on a desktop; and OpenSSL::X509::DEFAULT_CERT_FILE names it.
 *
 * And the runtime's ruby program, which RbConfig.ruby names (ADR 083):
 * fledge_ruby_link_program makes ROOT/bin/ruby a link to it before an
 * app's Ruby boots, and fledge_ruby_program_main is its main function.
 */

#include "fledge_ruby.h"
#include "mobile.h"

#include <android/log.h>
#include <dlfcn.h>
#include <errno.h>
#include <jni.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/stat.h>
#include <unistd.h>

/*
 * The runtime's ruby program, and the library of an app's gems'
 * extensions, as the package installer extracts them beside
 * libfledgeruby.so (ADR 082).
 */
#define FLEDGE_RUBY_PROGRAM "libfledgerubyexe.so"
#define FLEDGE_EXTENSIONS "libfledgeext.so"

/* The JNI functions FledgeRuby declares native. */
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeForwardOutput(JNIEnv *env, jclass type, jbyteArray tag);
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeRun(JNIEnv *env, jclass type, jbyteArray strings_array,
                                                                   jint argc);
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeRunApp(JNIEnv *env, jclass type,
                                                                      jbyteArray strings_array, jint argc);

/* OpenSSL's own X509_get_default_cert_file, and the one linked in its place. */
const char *__real_X509_get_default_cert_file(void);
const char *__wrap_X509_get_default_cert_file(void);

const char *
__wrap_X509_get_default_cert_file(void)
{
    const char *named = getenv("PORTABLE_RUBY_SSL_CERT_FILE");
    if (named != NULL && named[0] != '\0') return named;
    const char *certificates = fledge_ruby_certificates();

    return certificates != NULL ? certificates : __real_X509_get_default_cert_file();
}

static char *log_tag;

/* logcat copies nothing to an app's standard error. */
int
fledge_log_echoes(void)
{
    return 0;
}

int
fledge_log_open(const char *tag)
{
    free(log_tag);
    log_tag = strdup(tag);
    return log_tag != NULL ? 0 : -1;
}

void
fledge_log_write(int error, const char *text, size_t length)
{
    __android_log_print(error ? ANDROID_LOG_WARN : ANDROID_LOG_INFO, log_tag, "%.*s", (int)length, text);
}

/*
 * The count strings in the bytes of a Java byte[] (each followed by a
 * NUL), as a new array of pointers into a new copy of the bytes, or NULL
 * when out of memory or when the bytes hold fewer strings.
 */
static char **
strings(JNIEnv *env, jbyteArray array, size_t count)
{
    jsize length = (*env)->GetArrayLength(env, array);
    char *bytes = malloc((size_t)length + 1);
    char **list = calloc(count + 1, sizeof *list);

    if (bytes == NULL || list == NULL) {
        free(bytes);
        free(list);
        return NULL;
    }
    (*env)->GetByteArrayRegion(env, array, 0, length, (jbyte *)bytes);
    bytes[length] = '\0';
    char *next = bytes;
    for (size_t index = 0; index < count; index++) {
        if (next >= bytes + length) {
            free(bytes);
            free(list);
            return NULL;
        }
        list[index] = next;
        next += strlen(next) + 1;
    }
    return list;
}

JNIEXPORT jint JNICALL
Java_org_setdef_fledge_FledgeRuby_nativeForwardOutput(JNIEnv *env, jclass type, jbyteArray tag)
{
    (void)type;
    char **list = strings(env, tag, 1);
    if (list == NULL) return -1;
    int status = fledge_ruby_forward_output(list[0]);
    free(list[0]);
    free(list);
    return status;
}

/*
 * Runs fledge_ruby_run with the strings root, script, and then argc
 * arguments, in that order in the bytes of strings_array. The strings
 * stay allocated, since Ruby keeps ARGV's for as long as the process
 * runs.
 */
JNIEXPORT jint JNICALL
Java_org_setdef_fledge_FledgeRuby_nativeRun(JNIEnv *env, jclass type, jbyteArray strings_array, jint argc)
{
    (void)type;
    if (argc < 0) return FLEDGE_RUBY_SOFTWARE;
    char **list = strings(env, strings_array, (size_t)argc + 2);
    if (list == NULL) return FLEDGE_RUBY_SOFTWARE;
    return fledge_ruby_run(list[0], list[1], argc, list + 2);
}

JNIEXPORT jint JNICALL
Java_org_setdef_fledge_FledgeRuby_nativeRunApp(JNIEnv *env, jclass type, jbyteArray strings_array, jint argc)
{
    (void)type;
    if (argc < 0) return FLEDGE_RUBY_SOFTWARE;
    char **list = strings(env, strings_array, (size_t)argc + 1);
    if (list == NULL) return FLEDGE_RUBY_SOFTWARE;
    return fledge_ruby_run_app(list[0], argc, list + 1);
}

/*
 * Writes the folder this library, libfledgeruby.so, was loaded from
 * into folder, which holds PATH_MAX bytes, and returns 0; or returns -1
 * when it was loaded from inside the APK ("base.apk!/lib/ABI/..."), as
 * it is when the app's native libraries are stored and not extracted,
 * and so no program beside it can run.
 */
static int
library_folder(char *folder)
{
    Dl_info info;

    if (dladdr((void *)library_folder, &info) == 0 || info.dli_fname == NULL || strstr(info.dli_fname, "!/") != NULL) {
        return -1;
    }
    const char *slash = strrchr(info.dli_fname, '/');
    size_t length = slash != NULL ? (size_t)(slash - info.dli_fname) : 0;
    if (length == 0 || length >= PATH_MAX) return -1;
    memcpy(folder, info.dli_fname, length);
    folder[length] = '\0';
    return 0;
}

/*
 * Android lets an app run only the files its package installer
 * extracted, its native libraries, which are named lib*.so, so the
 * runtime's ruby program is libfledgerubyexe.so beside libfledgeruby.so,
 * in nativeLibraryDir, a folder that changes with each install.
 * RbConfig.ruby names ROOT/bin/ruby, from the prefix Ruby derives
 * (bindir and ruby_install_name), so this makes that a link to the
 * program before Ruby boots, whenever it is not one already. The kernel
 * runs the file the link resolves to, which Android's policy lets an
 * app run, and the program finds ROOT from the path it was run by
 * (program_root). Where the libraries are not extracted there is no
 * program to link, and an old link goes.
 */
void
fledge_ruby_link_program(const char *root)
{
    char folder[PATH_MAX];
    char program[PATH_MAX];
    char bin[PATH_MAX];
    char link[PATH_MAX];
    char fresh[PATH_MAX];
    char current[PATH_MAX];
    struct stat status;

    if (snprintf(bin, sizeof bin, "%s/bin", root) >= (int)sizeof bin ||
        snprintf(link, sizeof link, "%s/ruby", bin) >= (int)sizeof link ||
        snprintf(fresh, sizeof fresh, "%s/.ruby-%d", bin, (int)getpid()) >= (int)sizeof fresh) {
        return;
    }
    if (library_folder(folder) != 0 ||
        snprintf(program, sizeof program, "%s/" FLEDGE_RUBY_PROGRAM, folder) >= (int)sizeof program ||
        access(program, X_OK) != 0) {
        if (lstat(link, &status) == 0 && S_ISLNK(status.st_mode)) unlink(link);
        return;
    }
    ssize_t length = readlink(link, current, sizeof current - 1);
    if (length >= 0) {
        current[length] = '\0';
        if (strcmp(current, program) == 0) return;
    }
    if ((mkdir(bin, 0755) != 0 && errno != EEXIST) || symlink(program, fresh) != 0 || rename(fresh, link) != 0) {
        fprintf(stderr, "fledge_ruby_run: could not link %s to %s: %s\n", link, program, strerror(errno));
        unlink(fresh);
    }
}

/*
 * Writes into root, which holds PATH_MAX bytes, the prefix of the Ruby
 * this program was run as, and returns 0: the parent of the folder of
 * the path given to execve, which the kernel keeps as AT_EXECFN. That
 * path is ROOT/bin/ruby, the link fledge_ruby_link_program makes; the
 * program's own file, which /proc/self/exe and dladdr name, is in
 * nativeLibraryDir, away from ROOT/lib/ruby. The folder is resolved, not
 * the link, so a relative path is taken from the working folder the
 * program started in. Returns -1 when that folder is not a bin folder.
 */
static int
program_root(char *root)
{
    const char *path = (const char *)getauxval(AT_EXECFN);
    char folder[PATH_MAX];

    if (path == NULL) return -1;
    const char *slash = strrchr(path, '/');
    size_t length = slash == NULL ? 0 : slash == path ? 1 : (size_t)(slash - path);
    if (length >= PATH_MAX) return -1;
    if (length == 0) {
        folder[length++] = '.';
    } else {
        memcpy(folder, path, length);
    }
    folder[length] = '\0';
    if (realpath(folder, root) == NULL) return -1;
    length = strlen(root);
    if (length < 5 || strcmp(root + length - 4, "/bin") != 0) return -1;
    root[length - 4] = '\0';
    return 0;
}

/*
 * The runtime's ruby program: finds its root, loads the library of the
 * app's gems' extensions when the app has one, as the host does after
 * libfledgeruby.so, so that its constructor registers them
 * (doc/contributors/design/phone-projects.md, "Registering extensions"),
 * and runs fledge_ruby_main.
 */
int
fledge_ruby_program_main(int argc, char **argv)
{
    char root[PATH_MAX];
    char folder[PATH_MAX];
    char extensions[PATH_MAX];

    if (program_root(root) != 0) {
        fputs("ruby: this program runs as ROOT/bin/ruby, the RbConfig.ruby of an app's Ruby\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    if (library_folder(folder) == 0 &&
        snprintf(extensions, sizeof extensions, "%s/" FLEDGE_EXTENSIONS, folder) < (int)sizeof extensions &&
        access(extensions, F_OK) == 0 && dlopen(extensions, RTLD_NOW) == NULL) {
        fprintf(stderr, "ruby: could not load the app's extensions: %s\n", dlerror());
        return FLEDGE_RUBY_SOFTWARE;
    }
    return fledge_ruby_main(root, argc, argv);
}
