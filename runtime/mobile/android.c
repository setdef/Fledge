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
 * OpenSSL's CA certificates are openssl_certificates.c's, in Ruby's
 * openssl extension, where OpenSSL is linked in.
 *
 * And the runtime's ruby program, which RbConfig.ruby names:
 * fledge_ruby_link_program makes ROOT/bin/ruby a link to it before an
 * app's Ruby boots, and fledge_ruby_program_main is its main function.
 * With it, each link ROOT/fledge.links lists, from where the app's Ruby
 * looks for a file to a native library of the app's
 * (fledge_link_libraries, library_links.c), each gem's command among
 * them, which the program runs as its name says (commands.c), and each
 * file a gem's build left for this ABI alone, which ROOT/fledge.files
 * lists, moved to its path (fledge_place_abi_files). And before
 * Ruby boots, the library of the app's linked extensions, libfledgeext.so
 * (fledge_ruby_load_extensions).
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
 * The runtime's ruby program, as the package installer extracts it
 * beside libfledgeruby.so.
 */
#define FLEDGE_RUBY_PROGRAM "libfledgerubyexe.so"

/* The ABI this library was compiled for, as Android names the folder of its native libraries. */
#if defined(__aarch64__)
#define FLEDGE_ABI "arm64-v8a"
#elif defined(__x86_64__)
#define FLEDGE_ABI "x86_64"
#elif defined(__arm__)
#define FLEDGE_ABI "armeabi-v7a"
#elif defined(__i386__)
#define FLEDGE_ABI "x86"
#else
#error "an ABI Android has no native library folder for"
#endif

/* The JNI functions FledgeRuby declares native. */
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeForwardOutput(JNIEnv *env, jclass type, jbyteArray tag);
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeRun(JNIEnv *env, jclass type, jbyteArray strings_array,
                                                                   jint argc);
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeRunApp(JNIEnv *env, jclass type,
                                                                      jbyteArray strings_array, jint argc);

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
    if (library_folder(folder) != 0) folder[0] = '\0';
    fledge_place_abi_files(root, FLEDGE_ABI);
    fledge_link_libraries(root, folder, FLEDGE_ABI);
    if (folder[0] == '\0' ||
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
 * Opens libfledgeext.so from beside libfledgeruby.so, or by its name
 * where the native libraries stay inside the APK, before Ruby boots in
 * the app or in the runtime's ruby program, so that its constructor
 * registers the extensions linked into it whether or not the app's host
 * loads it.
 */
int
fledge_ruby_load_extensions(const char *caller)
{
    char folder[PATH_MAX];

    if (library_folder(folder) != 0) folder[0] = '\0';
    return fledge_load_extensions(folder, caller);
}

/*
 * The runtime's ruby program: finds its root and runs fledge_ruby_main,
 * which opens the app's extensions' library as fledge_ruby_run does.
 * Run as a gem's command, ROOT/bin/NAME, whose wrapper FLEDGE_COMMANDS holds,
 * it runs Ruby as that wrapper's shell prolog execs it on a desktop,
 * ruby -x ROOT/bin/NAME ARGS (Gem::Installer#bash_prolog_script,
 * rubygems/installer.rb, lines 1039 to 1054 at Ruby 4.1.0-preview1),
 * and Ruby reads the wrapper in its place (commands.c).
 */
int
fledge_ruby_program_main(int argc, char **argv)
{
    static char execute[] = "-x";
    char root[PATH_MAX];
    char wrapper[PATH_MAX];
    struct stat status;

    if (program_root(root) != 0) {
        fputs("ruby: this program runs as ROOT/bin/ruby, the RbConfig.ruby of an app's Ruby\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    char *path = (char *)getauxval(AT_EXECFN);
    const char *slash = strrchr(path, '/');
    const char *name = slash != NULL ? slash + 1 : path;
    if (argc < 1 || strcmp(name, "ruby") == 0 || name[0] == '.' ||
        snprintf(wrapper, sizeof wrapper, "%s" FLEDGE_COMMANDS "/%s", root, name) >= (int)sizeof wrapper ||
        stat(wrapper, &status) != 0 || !S_ISREG(status.st_mode)) {
        return fledge_ruby_main(root, argc, argv);
    }

    char **command = calloc((size_t)argc + 3, sizeof *command);
    if (command == NULL) {
        fputs("ruby: out of memory\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    command[0] = argv[0];
    command[1] = execute;
    command[2] = path;
    for (int index = 1; index < argc; index++) command[index + 2] = argv[index];
    return fledge_ruby_main(root, argc + 2, command);
}
